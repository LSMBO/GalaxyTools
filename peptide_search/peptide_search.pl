#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(extractListEntriesInArray getDate getVersion parameters booleanToString stderr);
use LsmboExcel qw(extractIds setColumnsWidth writeExcelLine writeExcelLineF);
use LsmboNcbi qw(getTaxonomyNamesAsString);
use LsmboUniprot qw(getFastaFromUniprot);

my ($paramFile, $outputFile, $fastaFileName) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
# make sure the boolean value are in text
$PARAMS{"B"} = booleanToString($PARAMS{"B"}) if exists($PARAMS{"B"});
$PARAMS{"J"} = booleanToString($PARAMS{"J"}) if exists($PARAMS{"J"});
$PARAMS{"R"} = booleanToString($PARAMS{"R"}) if exists($PARAMS{"R"});

# get the peptides
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

# create a hash with peptides as keys, and 0 as value (it will be used to retrieve the unseen peptides)
my %peptides;
foreach my $peptide (@peptides) {
  $peptides{$peptide} = 0;
}
print scalar(keys(%peptides))." distinct peptides to search\n";

# filter the peptides to retain only the valid ones
my @validPeptides;
if($PARAMS{"R"} eq "true") {
  foreach (keys(%peptides)) {
    # allow amino acids, dots, dashes, stars, interrogation marks and square brackets
    # maybe not necessary, but you can do so much with regex and i don't want to test everything
    # push(@validPeptides, $_) if(m/^\^?[A-Z\.\*\?\[\]\-]+\$?$/i);
    push(@validPeptides, $_);
  }
} else {
  foreach (keys(%peptides)) {
    push(@validPeptides, $_) if(m/^[A-Z]+$/i);
  }
}
print scalar(@validPeptides)." peptides are valid\n";

# get or generate the fasta file
my $fasta;
my $uniprotVersion = "";
if($PARAMS{"proteins"}{"source"} eq "fasta") {
  $fasta = $PARAMS{"proteins"}{"fastaFile"};
} else {
  # generate the fasta file if requested
  my $taxonomyIds = $PARAMS{"proteins"}{"taxo"};
  $taxonomyIds =~ s/ //g;
  ($fasta, $uniprotVersion) = getFastaFromUniprot($PARAMS{"proteins"}{"uniprot"}, "", "generate", split(",", $taxonomyIds));
}

# create an excel file
my $workbook = Excel::Writer::XLSX->new($outputFile);
# first sheet
my $sheet1 = $workbook->add_worksheet("Peptide Search");
my $line1 = 0;
writeExcelLine($sheet1, $line1++, "Tool version", getVersion());
writeExcelLine($sheet1, $line1++, "Search date", getDate("%d %B %Y %H:%M:%S (%Z)"));
writeExcelLine($sheet1, $line1++, "Settings: ", "");
if($PARAMS{"proteins"}{"source"} eq "fasta") {
  writeExcelLine($sheet1, $line1++, "- Fasta file", $fastaFileName);
} else {
  writeExcelLine($sheet1, $line1++, "- Taxonomies", getTaxonomyNamesAsString($PARAMS{"proteins"}{"taxo"}));
  if($PARAMS{"proteins"}{"uniprot"} eq 'SP') {
    writeExcelLine($sheet1, $line1++, "- Source", "UniProt Swiss-Prot");
  } elsif($PARAMS{"proteins"}{"uniprot"} eq 'TR') {
    writeExcelLine($sheet1, $line1++, "- Source", "UniProt TrEMBL");
  } else {
    writeExcelLine($sheet1, $line1++, "- Source", "UniProt Swiss-Prot and TrEMBL");
  }
}
writeExcelLine($sheet1, $line1++, "- Do not distinguish I and L", $PARAMS{"J"});
writeExcelLine($sheet1, $line1++, "- Do not distinguish D and N", $PARAMS{"B"});
writeExcelLine($sheet1, $line1++, "- Allow regular expressions in the peptides", $PARAMS{"R"});
setColumnsWidth($sheet1, 40, 40);

my $sheet2 = $workbook->add_worksheet("Results");
my $line = 0;
my $header = $workbook->add_format(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
writeExcelLineF($sheet2, $line++, $header, "Input sequence", "Peptide", "Protein", "Description", "Start", "Stop", "Before", "After");
# read the fasta file, once
open(my $fh, "<", $fasta) or stderr("Can't open the fasta file: $!");
my $acc = ""; my $desc = ""; my $seq = "";
while(<$fh>) {
  chomp;
  if(m/^>([^ ]*) (.*)$/) {
    search($acc, $desc, $seq, \@validPeptides) if($acc ne "");
    $acc = $1;
    $desc = $2;
    $seq = "";
  } else {
    $seq .= $_;
  }
}
close $fh;

# add the missing peptides in the first sheet
my @missingPeptides;
foreach my $peptide (@peptides) {
  push(@missingPeptides, $peptide) if($peptides{$peptide} eq 0);
}
if(scalar(@missingPeptides) > 0) {
  my $first = shift(@missingPeptides);
  writeExcelLine($sheet1, $line1++, "Peptides not found: ", $first);
  foreach my $peptide (@missingPeptides) {
    writeExcelLine($sheet1, $line1++, "", $peptide);
  }
}

# finalize
$sheet2->freeze_panes(1);
$sheet2->autofilter(0, 0, $line - 1, 7);
setColumnsWidth($sheet2, 25, 25, 25, 25, 10, 10, 10, 10);
$workbook->close();
unlink($inputCopy) if(-f $inputCopy);
unlink($fasta) if($PARAMS{"proteins"}{"source"} ne "fasta");
print("End of script\n");

exit;

sub joker {
  my ($sequence) = @_;
  $sequence = uc($sequence);
  $sequence =~ s/[IL]/J/g if($PARAMS{"J"} eq "true");
  $sequence =~ s/[DN]/B/g if($PARAMS{"B"} eq "true");
  return $sequence;
}

sub searchMatches {
  my ($acc, $desc, $seq, $peptides, $originalPeptide) = @_;
  my $jseq = joker($seq);
  my $p = 0;
  foreach my $peptide (@$peptides) {
    my $i = index($jseq, $peptide, $p);
    if($i > -1) {
      my $start = $i + 1;
      my $stop = $start + length($peptide);
      my $before = ""; # before it was "^"
      $before = substr($seq, $i - 1, 1) unless($i == 0);
      my $after = ""; # before it was "\$"
      $after = substr($seq, $stop - 1, 1) if($stop <= length($seq));
      $peptide = substr($seq, $start - 1, $stop - 1);
      writeExcelLine($sheet2, $line++, $originalPeptide, $peptide, $acc, $desc, $start, $stop, $before, $after);
      $peptides{$originalPeptide}++;
      $p = $i + 1;
    }
  }
}

sub searchBasic {
  my ($acc, $desc, $seq, $peptides) = @_;
  my $jseq = joker($seq);
  foreach my $peptide (@$peptides) {
    my $jpep = joker($peptide);
    my @matches;
    # search for all occurrences of this peptide in this protein
    my $i = index($jseq, $jpep);
    while($i > -1) {
      push(@matches, $jpep);
      $i = index($jseq, $jpep, $i + 1);
    }
    searchMatches($acc, $desc, $seq, \@matches, $peptide);
  }
}

sub searchRegex {
  my ($acc, $desc, $seq, $peptides) = @_;
  my $jseq = joker($seq);
  foreach my $peptide (@$peptides) {
    my $jpep = joker($peptide);
    # this returns all the matches in the same sequences
    my @matches = $jseq =~ m/($jpep)/g;
    # we have to search the start that is after the previous stop
    searchMatches($acc, $desc, $seq, \@matches, $peptide);
  }
}

sub search {
  if($PARAMS{"R"} eq "true") {
    searchRegex(@_);
  } else {
    searchBasic(@_);
  }
}
