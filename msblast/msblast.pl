#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(extractListEntriesInArray getDate parameters stderr);
use LsmboExcel qw(extractIds writeExcelLine);
use LsmboMPI qw(getNbCpu);

use File::Copy;

# input data:
# - a text file with a list of peptides (one per line)
# - a fasta file
# output: a zip file containing an excel file and an html file
my ($paramFile, $fastaFileName, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my $ncbiVersion = "ncbi-blast-2.11.0+";
my $maxUniquePeptide = 50;
my $scoreTable = 100;
my $dirname = dirname(__FILE__);
my $ncbi_path = "$dirname/$ncbiVersion/bin";

# step 1: create an adapted peptide file
my @peptides;
my $inputCopy = "input.xlsx";
if($PARAMS{"peptides"}{"source"} eq "list") {
    # if it's a id list, put it in the array
    @peptides = extractListEntriesInArray($PARAMS{"peptides"}{"peptideList"});
} elsif($PARAMS{"peptides"}{"source"} eq "file") {
    # if it's a text file, read its entries
    open(my $fh, "<", $PARAMS{"peptides"}{"peptideFile"}) or stderr("Can't open input file: $!");
    while(<$fh>) {
      chomp;
      push(@peptides, $_);
    }
    close $fh;
} elsif($PARAMS{"peptides"}{"source"} eq "xlsx") {
    # if it's an excel file, copy it locally and extract the ids to a local file
    # copy the excel file locally, otherwise it's not readable (i guess the library does not like files without the proper extension)
    copy($PARAMS{"peptides"}{"excelFile"}, $inputCopy);
    @peptides = extractIds($inputCopy, $PARAMS{"peptides"}{"sheetNumber"}, $PARAMS{"peptides"}{"cellAddress"});
}

# write the peptides in a file with the proper format for msblast
my $inputFile = "peptides.tmp";
open(my $fh, ">", "$inputFile") or stderr("Can't create $inputFile: $!");
print $fh ">msblast\t".scalar(@peptides)." peptides\n";
print $fh join(" ", @peptides);
close $fh;
my $fullPeptideList = join("", @peptides);

# count the number of peptides
my $nbPeptides = scalar(@peptides);
$nbPeptides = $maxUniquePeptide if($nbPeptides > $maxUniquePeptide);

my ($bordernumber, @scoringRow) = getMsParseConf($scoreTable, $nbPeptides);


# step 2: convert the fasta file
print("Preparing fasta file for Blast\n");
# my $fastaFile = $PARAMS{"fastaFile"};
my $fastaFile = $fastaFileName;
copy($PARAMS{"fastaFile"}, $fastaFile);
run("$ncbi_path/makeblastdb -dbtype prot -in $fastaFile");
stderr("Error $?") unless $? == 0;



# step 3: running blast
my $nbCpu = getNbCpu(0.5); # use half the cpu for blastp
print("Running blastp on fasta file [nb threads: $nbCpu]\n");
my $blpFile = "$fastaFile.blp";
run("$ncbi_path/blastp -db $fastaFile -query $inputFile -evalue=100 -num_descriptions 50000 -num_alignments 50000 -comp_based_stats F -ungapped -matrix PAM30 -max_hsps 100 -sorthsps 1 -num_threads $nbCpu -out $blpFile");
stderr("Error $?") unless $? == 0;



# step 4: attribute a confidence level to the proteins (positive, borderline, negative)
# get the proper score references based on the number of peptides (see msparse.conf with scoretable 100)
# read the blp file and create ab array with all peptide scores combined (score 1, score 1+2, score 1+2+3, etc)
# compare the scores from the blp file to the scores of the score table (see msparse.pl lines 254 to 277)
print("Extracting Blastp output\n");
my %proteins;
open($fh, "<", "$blpFile") || stderr("Failed to open $blpFile: $!");
my $version = <$fh>;
$version = choomp($version);
do {} until (<$fh> =~ /^Sequences producing significant alignments/);
<$fh>; # empty line
# protein data are first
while(<$fh> =~ m/^(\S+).*[\s\t]([\d\.]+)\t*\s+([\de\-\.]+)\s*$/) {
	my ($acc, $score, $evalue) = ($1, $2, $3);
	$proteins{$acc}{"score"} = $score;
	$proteins{$acc}{"evalue"} = $evalue;
}
print(scalar(keys(%proteins))." proteins have matched\n");

# then peptidic sequences
my $nbPeptidesResults = 0;
my $acc = "";
while(<$fh>) {
	s/\r?\n//; # chomp
	next if(m/^$/);
	if(m/>(\S+) (.*)/) {
		($acc, my $desc) = ($1, $2);
		my $nl = <$fh>;
		while($nl !~ m/^Length/) {
			$desc .= choomp($nl);
			$nl = <$fh>;
		}
		$nl =~ m/^Length=(\d+)$/;
		$proteins{$acc}{"length"} = $1;
		$proteins{$acc}{"description"} = $desc;
	} elsif(m/\s+Score = .* bits \((\d+)\),  Expect = (.*)$/) {
		$nbPeptidesResults++;
		
		my ($score, $evalue) = ($1, $2);
		
		# update score array
		push(@{$proteins{$acc}{"sorted_scores"}}, $score);
		
		# next line contains identities, positives and gaps
		<$fh> =~ m/\s+Identities = (\d+)\/\d+ \((\d+%)\), Positives = (\d+)\/\d+ \((\d+%)\), Gaps = (\d+)\/\d+ \((\d+%)\)$/;
		my ($idVal, $idPct, $posVal, $posPct, $gapVal, $gapPct) = ($1, $2, $3, $4, $5, $6);
		<$fh>; # next line is empty
		
		# next line contains query
		<$fh> =~ m/^Query[\s\t]+(\d+)[\s\t]+([A-Z]+)[\s\t]+(\d+)$/;
		my ($qstart, $qseq, $qend) = ($1, $2, $3);
		
		# next line contains common AA
		my $commonAA = <$fh>;
		chomp($commonAA);
		
		# next line contains subject
		<$fh> =~ m/^Sbjct[\s\t]+(\d+)[\s\t]+([A-Z]+)[\s\t]+(\d+)$/;
		my ($sstart, $sseq, $send) = ($1, $2, $3);
		
		my $trueQuery = substr($fullPeptideList, $qstart-1, $qend-$qstart+1);
		$proteins{$acc}{"peptides"}{$trueQuery} = {
			"score" => $score,
			"evalue" => $evalue,
			"identities" => $idVal, "identities_pct" => $idPct,
			"positives" => $posVal, "positives_pct" => $posPct,
			"gaps" => $gapVal, "gaps_pct" => $gapPct,
			"query" => $qseq, 
			"subject" => $sseq, "start" => $sstart, "end" => $send,
			"common" => $commonAA
		};
	}
}
close $fh;



# step 5: transforms the blp file into an excel file
print("Creation of the final Excel file\n");
# my $workbook = Excel::Writer::XLSX->new($outputFile);
my $workbook;
if($PARAMS{"peptides"}{"source"} ne "xlsx") {
    $workbook = Excel::Writer::XLSX->new($outputFile);
} else {
    # if the input file is an Excel file, use it as source
    (my $self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputCopy);
    $self->parse_template();
}

my $sheetBlast = $workbook->add_worksheet("MSBlast results");
my $line = 0;

# write metadata first
writeExcelLine($sheetBlast, $line++, "Version", $version);
# writeExcelLine($sheetBlast, $line++, "Date", strftime("%Y/%m/%d", localtime));
writeExcelLine($sheetBlast, $line++, "Date", getDate("%Y/%m/%d"));
$fastaFile =~ s/.*\///; # only keep file name
writeExcelLine($sheetBlast, $line++, "Database", $fastaFile);
writeExcelLine($sheetBlast, $line++, "Nb queries", scalar(@peptides));
writeExcelLine($sheetBlast, $line++, "Nb proteins", scalar(keys(%proteins)));
writeExcelLine($sheetBlast, $line++, "Nb peptidic sequences", $nbPeptidesResults);
writeExcelLine($sheetBlast, $line++);

# add headers
my @titles = ("Protein accession number", "Description", "MSBlast protein score", "Protein length", "Quality estimation", "User query", "MSBlast query", 
	"MSBlast subject", "MSBlast peptide score", "Subject start position", "Subject stop position", "Sequence length", "Query compared to Subject", "MSBlast Identities", 
	"MSBlast Positives", "Max consecutive AA (including '+')", "Max consecutive AA (not including '+')", 
	"Max consecutive AA (allowing one '-' or one '+')", "Max consecutive AA (allowing one '-')");
writeExcelLine($sheetBlast, $line, @titles);
# In case we would want to adjust column sizes
# $sheetBlast->set_column("A:A", 30);
# increase height, add format and freeze at header line
my $header = $workbook->add_format(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
$sheetBlast->set_row($line++, 50, $header);
$sheetBlast->freeze_panes($line);

my $positiveFormat = $workbook->add_format(bg_color => 'green');
my $borderlineFormat = $workbook->add_format(bg_color => 'yellow');

# write all data now
foreach my $acc (sort keys %proteins) {
	my %protein = %{$proteins{$acc}};
	foreach my $pep (keys %{$protein{"peptides"}}) {
		my %peptide = %{$protein{"peptides"}{$pep}};
		my $confidence = getPeptideConfidence($protein{"sorted_scores"}, \@scoringRow);
		my $ln = length($peptide{"subject"});
		my $commonAA = substr($peptide{"common"}, length($peptide{"common"}) - $ln);
		# count consecutive amino acids considering different rules
		my $nbConsecutives = getMaxLength(split(/\-+/, $commonAA));
		my $nbConsecutivesStrict = getMaxLength(split(/[\-\+]+/, $commonAA));
		# count with 1 [+-] and 1 [-]
		my $nbConsecutivesOneGap = getMaxLengthWithOneGap(split(/[\-\+]/, $commonAA, -1));
		my $nbConsecutivesStrictOneGap = getMaxLengthWithOneGap(split(/[\-]/, $commonAA, -1));
		my @cells = ($acc, $protein{"description"}, $protein{"score"}, $protein{"length"}, $confidence, $pep, $peptide{"query"},
			$peptide{"subject"}, $peptide{"score"}, $peptide{"start"}, $peptide{"end"}, $ln, $commonAA, $peptide{"identities"}, $peptide{"positives"}, 
			$nbConsecutives, $nbConsecutivesStrict, $nbConsecutivesOneGap, $nbConsecutivesStrictOneGap);
		$sheetBlast->write_row($line, 0, \@cells);
		# colorize the Confidence cells depending on their value (green, yellow, nothing)
		$sheetBlast->write($line, 4, $confidence, $positiveFormat) if($confidence eq "Positive hit");
		$sheetBlast->write($line, 4, $confidence, $borderlineFormat) if($confidence eq "Borderline hit");
		$line++;
	}
}

# add autofilter
$sheetBlast->autofilter($line - $nbPeptidesResults - 1, 0, $line-1, scalar(@titles) - 1);

$workbook->close();
print "Excel file is complete\n";

# clean temporary files
unlink($inputFile, glob("$fastaFile*"));
unlink($inputCopy) if(-f $inputCopy);

print("End of script\n");
exit;

sub run {
  my ($command) = @_;
  print "> $command\n";
  return `$command`;
}

# sub writeLine {
	# my ($line, @data) = @_;
	# $sheetBlast->write_row($line, 0, \@data);
# }

# Counts the longuest string in the list of arguments
# This is used to get the biggest number of consecutive similar amino acids between two sequences
sub getMaxLength {
  my $max = -1;
  for (@_) { $max = length if (length > $max); }
  return $max;
}

# Allows one gap and counts the largest sequence given
# The method couples the items and add a character
# Then it calls the method above and returns the result
sub getMaxLengthWithOneGap {
  my @array;
  for(my $i = 0; $i < scalar(@_) - 1; $i++) {
    push(@array, $_[$i]."?".$_[$i+1]);
  }
  push(@array, $_[$#_]);
  return getMaxLength(@array);
}


sub choomp {
	my ($string) = @_;
	$string =~ s/\r?\n//;
	return $string;
}


# The following methods have been copied and only slightly modified from the msparse.pl script with the following header:

# Script Author: Jeff Oegema, Scionics Computer GmbH, http://www.scionics.de
# Script Name: msparse.pl
# Script Creation Date: 13/5/2002
#
# Script Description:
# A PERL script to parse blase results and add
# color coding. Script is to be within the EMBL
# parsing system and is designed as such.
#
# Note: Script uses <font> tags which are currently
# discouraged by html standards but are simple in this
# case than divs and style sheets


sub getMsParseConf {
	my ($scoreTable, $nbPeptides) = @_;
	my $bordernumber = 4;
	my %table;
	
	my $pvalue;
	if($nbPeptides >=20 && $nbPeptides <=24) { $pvalue=20; }
	elsif ($nbPeptides >=25 && $nbPeptides <=34) { $pvalue=30; }
	elsif ($nbPeptides >=35 && $nbPeptides <=44) { $pvalue=40; }
	elsif ($nbPeptides >=45 && $nbPeptides <=50) { $pvalue=50; }
	else { $pvalue = $nbPeptides; }
	my $mykey = $pvalue."pep";
	
	
	open(my $fh, "<", "$dirname/msparse.conf") or stderr("Can't open msparse.conf file: $!");
	while (!eof($fh)){
		# Read a line off the file
		$_ = <$fh>;
		# We have gotten to the 99 scoring table, form the hash
		# Some assumptions here...8 HSP, two tables 99,100
		if(m/^99\{/) {
			$_ = <$fh>;
			while(! eof($fh) && ! /^}/) {
				/^(\d+)pep\((\S+)\)/;
				my $hashkey = $1 . "pep";
				my @fields = split ',', $2;
				$table{$hashkey} = [@fields] if($scoreTable == 99);
				$_ = <$fh>;
			}
		}

		# We have gotten to the 100 scoring table, form the hash
		if (m/^100\{/) {
			$_ = <$fh>;
			while(! eof($fh) && ! /^}/) {
				/^(\d+)pep\((\S+)\)/;
				my $hashkey = $1 . "pep";
				my @fields = split ',', $2;
				$table{$hashkey} = [@fields] if($scoreTable == 100);
				$_ = <$fh>;
			}
		}
		# Get the remaining informations
		if (/^bordernumber=(\w+)/) { $bordernumber=$1;}
	}
	close $fh;
	
	my @scoringRow = @{$table{$mykey}};
	return ($bordernumber, @scoringRow);
}


sub transformProteinScores {
	my (@scores) = @_;
	
	# transforms the score array to a new array of this kind : (total score, score1, score1+2, score 1+2+3, ..., total score)
	my @incScores = (" "); # reserve that item for total score
	my $temp = 0;
	foreach my $score (@scores) {
		$temp += $score;
		push(@incScores, $temp);
	}
	$incScores[0] = $temp;
	
	return @incScores;
}

sub getPeptideConfidence {
	my @scores = @{$_[0]};
	my @table = @{$_[1]};
	@scores = transformProteinScores(@scores);

	my $positive = 0;
	for(my $count = 1; $count < scalar(@scores) ; $count++) {
		if($scores[$count] >= $table[$count - 1]) {
			$positive = 3;
		} elsif($scores[$count] + $bordernumber >= $table[$count - 1]) {
			if($positive < 3) { $positive = 2; }
		}

		# Deal with the case where the result has more positive entries than 8, or more results than the table has and make positive
		if(scalar(@scores) > 9) {
			$positive = 3;
		} elsif(scalar(@scores) > scalar(@table) + 1) {
			$positive = 3;
		}
	}

	if ($positive==3) {
		return "Positive hit";
	} elsif ($positive==2){
		return "Borderline hit";
	} else {
		return "Negative result";
	}
}




