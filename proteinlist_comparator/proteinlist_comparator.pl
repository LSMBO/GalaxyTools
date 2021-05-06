#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use lib dirname(__FILE__)."/..";
use LsmboFunctions;

# List comparator
# A: Protein column (one per line)
# B: Sample column (one new column for each)
# C: Conditions (for each condition, prints the number per B)

# Assumptions on the file:
# - Data is in the first sheet
# - No formulas left
# - Data starts at column A and line 1
# - First line is the header line, everything else is data

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my $columnSample = uc($PARAMS{"sample"});
my $columnProtein = uc($PARAMS{"protein"});
my $columnsCondition = uc($PARAMS{"conditions"});

# make a copy of the file, otherwise the XLSX parser may fail
my $inputCopy = "input.xlsx";
copy($PARAMS{"input"}, $inputCopy);

# clean the separators if need be
$columnsCondition =~ s/[ ;,]/,/g;
$columnsCondition =~ s/,,*/,/g;
# make sure inputs are valid (not really useful but it does not take long)
die("Sample column '$columnSample' is not valid") if(!isValidColumn($columnSample));
die("Protein column '$columnProtein' is not valid") if(!isValidColumn($columnProtein));
die("Condition columns '$columnsCondition' are not valid") if(!isValidColumn(split(",", $columnsCondition)));

# get column ids
my ($sampleColumnId) = getColumnId($columnSample);
my ($proteinColumnId) = getColumnId($columnProtein);
my @conditionColumnIds = getColumnId(split(",", $columnsCondition));

# open the input file
print "Reading Excel input file\n";
my $parser = Spreadsheet::ParseXLSX->new;
my $workbook = $parser->parse($inputCopy);
die $parser->error(), "\n" if(!defined $workbook);
my @worksheets = $workbook->worksheets;
my $worksheet = $worksheets[0];
my ($row_min, $row_max) = $worksheet->row_range();
my ($col_min, $col_max) = $worksheet->col_range();

# get header names
my @headers;
for my $col ($col_min .. $col_max) {
  push(@headers, getValue($worksheet, $row_min, $col));
}

# get unique samples and proteins
my %proteins;
my %samples;
my %data;

# read the whole file and count for each conditions
for my $row ($row_min+1 .. $row_max) {
  my %hash;
  foreach my $id (@conditionColumnIds) {
    $hash{$headers[$id]} = getValue($worksheet, $row, $id);
  }
  my $protein = getValue($worksheet, $row, $proteinColumnId);
  my $sample = getValue($worksheet, $row, $sampleColumnId);
  $data{$sample}{$protein} = \%hash;
  $proteins{$protein}++;
  $samples{$sample}++;
}

# get sorted proteins and samples
my @proteins = sort keys %proteins;
my @samples = sort keys %samples;

# write the output file
print "Creating file $outputFile\n";
(my $self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputCopy);
$self->parse_template();
$worksheet = $workbook->add_worksheet();

# write headers
$worksheet->write(1, 0, $headers[$proteinColumnId]);
my $col = 1;
foreach my $id (@conditionColumnIds) {
  $worksheet->write(0, $col, $headers[$id]);
  foreach my $sample (@samples) {
    $worksheet->write(1, $col++, $sample);
  }
}

# write data
# TODO make it pretty with nice formatting and borders
my $row = 2;
foreach my $protein (@proteins) {
  $col = 0;
  $worksheet->write($row, $col++, $protein);
  foreach my $id (@conditionColumnIds) {
    foreach my $sample (@samples) {
      $worksheet->write($row, $col++, $data{$sample}{$protein}->{$headers[$id]});
    }
  }
  $row++;
}

$workbook->close();

# clean and exit
unlink ($inputCopy);
print "Correct ending of the script\n";
exit;

sub isValidColumn {
  my @columns = @_;
  my $res = 1;
  foreach my $column (@columns) {
    $res = 0 unless($column =~ m/^[A-Z]+$/);
  }
  return $res;
}

