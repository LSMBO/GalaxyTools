#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(archive parameters stderr);
use LsmboExcel qw(addWorksheet getColumnId getValue writeExcelLine writeExcelLineF);
use LsmboMPI;
use Cwd 'abs_path';

my ($paramFile, $OUTPUT_FILE_XLSX, $OUTPUT_FILE_STRETCHER) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my %PROTEINS;
my %REFERENCES;
my $version = "fasta36-36.3.8h_04-May-2020";
my $FASTA36 = abs_path(dirname(__FILE__))."/$version/bin/fasta36";
stderr("$FASTA36 does not exist !") if(!-f $FASTA36);
# stretcher has to be installed and available !
# my $STRETCHER = abs_path(dirname(__FILE__))."/emboss/bin/stretcher";
# stderr("$STRETCHER does not exist !") if(!-f $STRETCHER);
# create directories
my $SOURCE_DIR = "asequence";
my $REF_DIR = "bsequence";
my $OUTPUT_DIR = "output";
makeDir($SOURCE_DIR, $REF_DIR, $OUTPUT_DIR);

# first, we need to extract the source ids and the target positions
readInputFileXlsx();
# parse the source fasta file to generate one file per protein of interest
parseSource();
# run a fasta36 for each source protein to determine what are the reference proteins
runFasta36();
# remove proteins that did not have any match after fasta36
cleanData();
# parse the reference fasta file to generate one file per protein of interest
parseRef();
# for each couple of source/ref protein, run stretcher and generate an output file
runStretcher();
# read the output files and generate a tsv file from them
generateXlsxOutput();
# create an archive with all the Stretcher output files
archive($OUTPUT_FILE_STRETCHER, glob("$OUTPUT_DIR/*"));

# delete directories
unlink(glob("$SOURCE_DIR/*"));
unlink(glob("$REF_DIR/*"));
unlink(glob("$OUTPUT_DIR/*"));

print "Correct ending of the script\n";

exit;

sub makeDir {
  foreach my $dirName (@_) {
    if(-d $dirName) {
      unlink(glob("$dirName/*"));
    } else {
      mkdir $dirName;
    }
  }
}

sub readInputFileXlsx {
  print "Reading Excel input file\n";
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($PARAMS{"inputFile"}{"excelFile"});
  stderr($parser->error()) if(!defined $workbook);
  # open first sheet
  my @worksheets = $workbook->worksheets();
  my $sheet = $worksheets[$PARAMS{"inputFile"}{"sheetNumber"} - 1];
  # read the content of the file and put it in the main hash
  my ($row_min, $row_max) = $sheet->row_range();
  my ($col_min, $col_max) = $sheet->col_range();
  # skip the first rows if they are empty (just checking the first column)
  while(getValue($sheet, $row_min, 1) eq "" && $row_min < $row_max) {
    $row_min++;
  }
  # now read the content of the table
  my ($colAccession, $colPosition) = getColumnId($PARAMS{"inputFile"}{"colAccession"}, $PARAMS{"inputFile"}{"colPosition"});
  for my $row ($row_min + 1 .. $row_max) {
    my $acc = getValue($sheet, $row, $colAccession);
    my $pos = getValue($sheet, $row, $colPosition);
    push(@{$PROTEINS{$acc}{"source"}{"positions"}}, $pos) if($acc ne "" && $pos ne "");
  }
  print scalar(keys(%PROTEINS))." proteins have been read in file '".$PARAMS{"inputFile"}{"excelFile"}."'\n";
}

sub parseSource {
  # read the fasta
  my $acc = "";
  my $description = "";
  my $protein = "";
  my $count = 0;
  my $dbSource = $PARAMS{"dbSource"};
  open(my $fh, "<", $dbSource) or stderr("Can't open source fasta file $dbSource: $!");
  while(<$fh>) {
    if(m/^>([^\s]*) (.*)/) {
      $count += storeSourceProtein($acc, $description, $protein) if($acc ne "" && exists($PROTEINS{$acc}));
      $acc = getAcc($1);
      $description = $2;
      $protein = "";
    }
    $protein .= $_ if($acc ne "" && exists($PROTEINS{$acc}));
  }
  $count += storeSourceProtein($acc, $description, $protein) if($acc ne "" && exists($PROTEINS{$acc}));
  $fh->close();
  print "$count proteins have been extracted from source fasta file '$dbSource'\n";
}

sub storeSourceProtein {
  my ($acc, $description, $content) = @_;
  my $file = getFile($acc, $SOURCE_DIR);
  $PROTEINS{$acc}{"source"}{"file"} = $file;
  $PROTEINS{$acc}{"source"}{"description"} = $description;
  $PROTEINS{$acc}{"source"}{"length"} = length($content);
  chomp $content;
  open(my $fh, ">", "$file") or printa("Error: Can't create file $file: $!");
  print $fh $content;
  $fh->close();
  return 1;
}

sub runFasta36 {
  my $ktup = 3;
  my $fastaLibrary = $PARAMS{"dbRef"};
  my @fastaFiles;
  foreach my $acc (keys(%PROTEINS)) {
    push(@fastaFiles, $PROTEINS{$acc}{"source"}{"file"});
  }
  print "Using Fasta36 to compare ".scalar(@fastaFiles)." proteins sequences to the library $fastaLibrary [KTUP=$ktup]\n";
  # prepare the commands to run
  my @commandList;
  foreach(@fastaFiles) {
      my $output = "$_.fasta36output";
      push(@commandList, "$FASTA36 -m \"F8 $output\" -T 1 -p $_ $fastaLibrary $ktup > $output.log");
  }
  # run the commands in parallel
  LsmboMPI::runCommandList(0.75, @commandList);
  # read the output files to extract the target reference protein and its score
  foreach my $acc (keys(%PROTEINS)) {
    my $output = $PROTEINS{$acc}{"source"}{"file"}.".fasta36output";
    my $log = $PROTEINS{$acc}{"source"}{"file"}.".fasta36output.log";
    my %results = %{extractFasta36($output)};
    foreach my $ref (sort {$results{$b} cmp $results{$a} } keys(%results)) {
      $PROTEINS{$acc}{"ref"}{$ref}{"fasta36"} = $results{$ref};
      push(@{$REFERENCES{$ref}}, $acc); # store the link to retrieve the source proteins from a reference protein
    }
    unlink($output, $log);
  }
}

sub extractFasta36 {
  my ($file) = @_;
  open(my $fh, "<", $file) or stderr("Can't read file $file: $!");
  # each lines look like this (separated by a tabulation):
  # XP_026334713.1 sp|Q5T5P2|SKT_HUMAN 85.18 1936 287 16 1 1945 1 1943 0 1111.3
  # we need acc='sp|Q5T5P2|SKT_HUMAN' and identity=85.18
  my %results;
  while(<$fh>) {
    my @items = split(/\t/);
    my $protein = getAcc($items[1]);
    my $identity = $items[2] / 100;
    last if($PARAMS{"fasta36"}{"strategy"} eq "identityThreshold" && $identity < $PARAMS{"fasta36"}{"identityThreshold"});
    $results{$protein} = $identity;
    last if($PARAMS{"fasta36"}{"strategy"} eq "bestMatches" && scalar(keys(%results)) eq $PARAMS{"fasta36"}{"bestMatches"});
  }
  $fh->close();
  return \%results;
}

sub extractFasta36FirstMatch {
  my ($file) = @_;
  open(my $fh, "<", $file) or stderr("Can't read file $file: $!");
  # each lines look like this (separated by a tabulation):
  # XP_026334713.1 sp|Q5T5P2|SKT_HUMAN 85.18 1936 287 16 1 1945 1 1943 0 1111.3
  # we need acc='sp|Q5T5P2|SKT_HUMAN' and bit_score=1111.3
  # eventually we will prefer another item to represent the quality of the match (or several items)
  my $line = <$fh>;
  my @items = split(/\s+/, $line);
  my $protein = $items[1];
  my $score = $items[2] / 100; # we use the identity percentage rather than the score
  $fh->close();
  return ($protein, $score);
}

sub cleanData {
  foreach my $acc (keys(%PROTEINS)) {
    if(!exists($PROTEINS{$acc}{"ref"})) {
      my $ref = $PROTEINS{$acc}{"ref"}{"acc"};
      print "Fasta36 could not match any protein for '$acc', this protein will be removed\n";
      delete $PROTEINS{$acc};
    }
  }
}

sub parseRef{
  # read the fasta
  my $acc = "";
  my $description = "";
  my $protein = "";
  my $count = 0;
  my $dbRef = $PARAMS{"dbRef"};
  open(my $fh, "<", $dbRef) or stderr("Can't open reference fasta file $dbRef: $!");
  while(<$fh>) {
    if(m/^>([^\s]*) (.*)/) {
      $count += storeRefProtein($acc, $description, $protein) if($acc ne "" && exists($REFERENCES{$acc}));
      $acc = getAcc($1);
      $description = $2;
      $protein = "";
    }
    $protein .= $_ if($acc ne "" && exists($REFERENCES{$acc}));
  }
  $count += storeRefProtein($acc, $description, $protein) if($acc ne "" && exists($REFERENCES{$acc}));
  $fh->close();
  print "$count proteins have been extracted from reference fasta file '$dbRef'\n";
}

sub getAcc {
  my ($acc) = @_;
  my @items = split(/\|/, $acc);
  return $items[-1];
}

sub storeRefProtein {
  my ($acc, $description, $content) = @_;
  my $file = getFile($acc, $REF_DIR);
  foreach my $id (@{$REFERENCES{$acc}}) {
    $PROTEINS{$id}{"ref"}{$acc}{"file"} = $file;
    $PROTEINS{$id}{"ref"}{$acc}{"description"} = $description;
    $PROTEINS{$id}{"ref"}{$acc}{"length"} = length($content);
  }
  chomp $content;
  open(my $fh, ">", "$file") or printa("Error: Can't create file $file: $!");
  print $fh $content;
  close $fh;
  return 1;
}

sub runStretcher {
  my @commandList;
  foreach my $acc (keys(%PROTEINS)) {
    my $aseq = $PROTEINS{$acc}{"source"}{"file"};
    my %refs = %{$PROTEINS{$acc}{"ref"}};
    foreach my $ref (keys(%refs)) {
      my $bseq = $PROTEINS{$acc}{"ref"}{$ref}{"file"};
      my $outputFile = getFile($acc."-".$ref, $OUTPUT_DIR);
      my $length = getLength($acc, $ref);
      push(@commandList, "stretcher -auto -outfile '$outputFile' -asequence '$aseq' -bsequence '$bseq' -datafile EBLOSUM62 -gapopen 1 -gapextend 1 -aformat3 pair -sprotein1 -sprotein2 -awidth3 $length");
      # print $commandList[-1]."\n";
    }
  }
  print "Using Stretcher to align ".scalar(@commandList)." proteins sequences together\n";
  LsmboMPI::runCommandList(0.75, @commandList);
}

sub getFile {
  my ($acc, $directory) = @_;
  my $file = "$directory/$acc.txt";
  $file =~ s/\|/_/g;
  return $file;
}

sub getLength {
  my ($acc, $ref) = @_;
  print "Error with protein $acc:\n".Dumper($PROTEINS{$acc}) if(!exists($PROTEINS{$acc}{"source"}{"length"}) || !exists($PROTEINS{$acc}{"ref"}{$ref}{"length"}));
  my $length1 = $PROTEINS{$acc}{"source"}{"length"};
  my $length2 = $PROTEINS{$acc}{"ref"}{$ref}{"length"};
  return $length1 if($length1 > $length2);
  return $length2;
}

sub generateXlsxOutput {
  # creating the file
  my $inputFile = $PARAMS{"inputFile"}{"excelFile"};
  print "Creating a new Excel file named '$OUTPUT_FILE_XLSX' based on file '$inputFile'\n";
  my ($self, $workbook) = Excel::Template::XLSX->new($OUTPUT_FILE_XLSX, $inputFile);
  $self->parse_template();
  # adding the new sheet
  my $worksheet = addWorksheet($workbook, "SeqAlign");
  # prepare formats
  my $fHeader = $workbook->add_format(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
  my $fPercent = $workbook->add_format(num_format => '0.0%');
  # write the headers
  my $rowNumber = 0;
  my @headers = ("Source protein", "Reference protein", "Fasta36 identity (%)", "Source protein length", "Reference protein length", "Identity", "Identity (%)", "Similarity", "Similarity (%)", "Gaps", "Gaps (%)", "Max. consecutive gaps", "Stretcher score", "Source AA", "Source position", "Reference AA", "Reference position", "Source protein gene name", "Source protein description", "Reference protein gene name", "Reference protein description");
  writeExcelLineF($worksheet, $rowNumber++, $fHeader, @headers);
  # write the data
  foreach my $file (glob("$OUTPUT_DIR/*")) {
    my ($acc, $ref, $length, $id, $idPct, $sim, $simPct, $gaps, $gapsPct, $score, $sequence1, $sequence2, $diff) = parseFile($file);
    # write a line per position
    my @positions = (@{$PROTEINS{$acc}{"source"}{"positions"}});
    my %map = map { $_, 1 } @positions; # remove duplicate positions if any
    @positions = keys(%map);
    @positions = sort { $a <=> $b } @positions; # sort positions
    foreach my $position (@positions) {
      my ($sourceAA, $sourcePos, $refAA, $refPos, $diffChar) = searchPosition($sequence1, $sequence2, $diff, $position);
      my $colID = 0;
      $worksheet->write($rowNumber, $colID++, $acc);
      $worksheet->write($rowNumber, $colID++, $ref);
      $worksheet->write($rowNumber, $colID++, $PROTEINS{$acc}{"ref"}{$ref}{"fasta36"}, $fPercent);
      $worksheet->write($rowNumber, $colID++, $PROTEINS{$acc}{"source"}{"length"});
      $worksheet->write($rowNumber, $colID++, $PROTEINS{$acc}{"ref"}{$ref}{"length"});
      $worksheet->write($rowNumber, $colID++, $id);
      $worksheet->write($rowNumber, $colID++, $idPct, $fPercent);
      $worksheet->write($rowNumber, $colID++, $sim);
      $worksheet->write($rowNumber, $colID++, $simPct, $fPercent);
      $worksheet->write($rowNumber, $colID++, $gaps);
      $worksheet->write($rowNumber, $colID++, $gapsPct, $fPercent);
      $worksheet->write($rowNumber, $colID++, getMaxConsecutiveGaps($diff));
      $worksheet->write($rowNumber, $colID++, $score);
      $worksheet->write($rowNumber, $colID++, $sourceAA);
      $worksheet->write($rowNumber, $colID++, $sourcePos);
      $worksheet->write($rowNumber, $colID++, $refAA);
      $worksheet->write($rowNumber, $colID++, $refPos);
      $worksheet->write($rowNumber, $colID++, getGeneName($PROTEINS{$acc}{"source"}{"description"}));
      $worksheet->write($rowNumber, $colID++, $PROTEINS{$acc}{"source"}{"description"});
      $worksheet->write($rowNumber, $colID++, getGeneName($PROTEINS{$acc}{"ref"}{$ref}{"description"}));
      $worksheet->write($rowNumber++, $colID, $PROTEINS{$acc}{"ref"}{$ref}{"description"});
    }
  }
  # finalize the sheet
  $worksheet->freeze_panes(1); # freeze the first row
  $worksheet->autofilter(0, 0, $rowNumber, scalar(@headers) - 1); # add autofilters
  $worksheet->activate(); # display this sheet directly when opening the file
  $workbook->close();
  print "$rowNumber rows have been written to the output\n";
}

sub parseFile {
  my ($file) = @_;
  open(my $fh, "<", $file) or stderr("Can't open reference fasta file $file: $!");
  while(<$fh> !~ m/^# Aligned_sequences/) {}
  my $acc = extract($fh, "1");
  my $ref = extract($fh, "2");
  <$fh>; <$fh>; <$fh>; <$fh>;
  my $length = extract($fh, "Length");
  my ($id, $idPct) = extract($fh, "Identity");
  my ($sim, $simPct) = extract($fh, "Similarity");
  my ($gaps, $gapsPct) = extract($fh, "Gaps");
  my $score = extract($fh, "Score");
  <$fh>; <$fh>; <$fh>; <$fh>;
  my $sequence1 = ""; my $sequence2 = ""; my $diff = "";
  while(<$fh>) {
    chomp;
    next if(m/^$/); # do not care about empty lines
    last if(m/^\#--------/); # no need to read more once we see this line
    # this line has to belong to the source protein
    m/^[^\s]*\s*\d+ ([^\s]*)\s+\d+$/;
    $sequence1 .= $1;
    my $start = index($_, $1);
    my $stop = $start + length($1);
    # next line contains the difference between source and reference
    my $diffLine = <$fh>;
    chomp($diffLine);
    $diff .= substr($diffLine, $start, $stop);
    # next line belongs to the reference protein
    my $refLine = <$fh>;
    $refLine =~ m/^[^\s]*\s*\d+ ([^\s]*)\s+\d+$/;
    $sequence2 .= $1;
  }
  $fh->close();
  
  return ($acc, $ref, $length, $id, $idPct / 100, $sim, $simPct / 100, $gaps, $gapsPct / 100, $score, $sequence1, $sequence2, $diff);
}

sub extract {
  my ($fh, $tag) = @_;
  my $line = <$fh>;
  chomp($line);
  $line =~ s/^# $tag:\s*//;
  if($line =~ m/(\d+)\/\d+\s+\((.*)\%\)/) {
    return ($1, $2);
  } else {
    return $line;
  }
}

sub searchPosition {
  my ($source, $ref, $diff, $position) = @_;
  # read source and get the position in the string matching the position of the AA in the sequence (do not count '-')
  my $i = 0;
  my $n = 0;
  my @sourceAA = split(//, $source);
  for($i = 0; $i < scalar(@sourceAA); $i++) {
    $n++ if($sourceAA[$i] ne "-");
    last if($n eq $position);
  }
  my $generalPosition = $i;
  my $positionInSource = $n;
  # get the position of the matching AA in ref
  my @refAA = split(//, $ref);
  $n = 0;
  for($i = 0; $i <= $generalPosition; $i++) {
    $n++ if($refAA[$i] ne "-");
  }
  my $positionInRef = $n;
  # get the character representing the 
  my @diffAA = split(//, $diff);
  my $diffChar = $diffAA[$generalPosition];
  
  return ($sourceAA[$generalPosition], $positionInSource, $refAA[$generalPosition], $positionInRef, $diffChar);
}

sub getMaxConsecutiveGaps {
  my ($diff) = @_;
  my $count = 0;
  my $max = 0;
  foreach my $c (split(//, $diff)) {
      if($c eq " ") {
          $count++;
      } else {
          $max = $count if($count > $max);
          $count = 0;
      }
  }
  return $max;
}

sub getGeneName {
  my ($description) = @_;
  return $1 if($description && $description =~ m/.*GN=([^\s]+).*/);
  return "";
}
