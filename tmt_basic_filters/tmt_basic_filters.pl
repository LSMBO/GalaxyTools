#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(booleanToString parameters stderr);
use LsmboExcel qw(addWorksheet getValue);

use List::MoreUtils qw(uniq);
use Statistics::Basic qw(median);

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my $CV_THRESHOLD = (exists($PARAMS{"cv"}) ? $PARAMS{"cv"} / 100 : 0.2);
my @CV_CATEGORIES = ();
if(exists($PARAMS{"cvcats"})) {
  foreach (split(" ", $PARAMS{"cvcats"})) {
    push(@CV_CATEGORIES, $_ / 100) unless($_ eq 0); # zero is implicit
  }
  @CV_CATEGORIES = sort(uniq(@CV_CATEGORIES));
} else {
  @CV_CATEGORIES = (0.05, 0.1, 0.15, 0.2, 0.4, 0.6);
}
my $PEP_THRESHOLD = (exists($PARAMS{"threshold"}) ? $PARAMS{"threshold"} : 0.95);
my $ADD_PERCENTAGES = (exists($PARAMS{"addPct"}) ? booleanToString($PARAMS{"addPct"}) : "false"); # this option is not in the xml file (and may never be)

my %DATA;
my @HEADERS;
my @VALID_LABELS;
my $DENOM_LABEL = "";
my $NB_LABELS;
my $NB_VALID_LABELS;
my $NB_PEPTIDES;
my $COL_QUANTINALL;
my $COL_CVCALC;
my $COL_FOUNDINALL;
my $H_QUANTINALL = "Quantified in all labels";
my $H_CVCALC = "CVs calculation";
my $H_FOUNDINALL = "Found in all labels";

# Excel formats
my %F_WARNING = (bold => 1, color => 'red');
my %F_BORDERS = (top => 1, bottom => 1, right => 1, left => 1);
my %F_BORDER_R = (right => 1);
my %F_BORDER_B = (bottom => 1);
my %F_HEADER = (bold => 1, valign => 'top', text_wrap => 1);
my %F_MERGE = (valign => 'vcenter', text_wrap => 1);
my %F_BLUE = (bg_color => '#a7cdf0');
my %F_YELLOW = (bg_color => '#ffe333');
my %F_RED = (bg_color => '#ed7d31');
my %F_ORANGE = (bg_color => '#ffbf00');
my %F_PCT = (num_format => '0.00%');
my %F_DEC = (num_format => '0.00');
my %F_ALIGNLEFT = (align => 'left');

my %SUMMARY;
my $CATEGORIES = { "O" => "Overall", "Q" => "Quantified in all labels", "I" => "Identified in all labels", "V" => "Validated (CV <= ".($CV_THRESHOLD*100)."%)", "QV" => "Quantified in all labels and validated (CV <= ".($CV_THRESHOLD*100)."%)" };
my $INFO = { "nbQ" => "Quantified peptides", "pctQ" => "% Quantified peptides against Overall quantified peptides", "pctQI" => "% Quantified peptides against Overall identified peptides", "nbI" => "Identified peptides", "pctI" => "% Identified peptides against Overall Identified peptides", "M" => "Median abundance", "R" => "Ratio Median / Median(_)" };
my $COLS = { "A" => "All labels", "1+" => "At least 1 label", "N" => "Not at all" };

main($PARAMS{"inputFile"}, $outputFile);
print "Correct ending of the script\n";

exit;

sub main {
  my ($inputFile, $outputFile) = @_;
  
  # read excel file and create a hash with 1 entry per line (key is line number)
  # and create an array to define the order of the columns at the moment of writing the output file
  readInputFile($inputFile);
  
  # determine the number of TMT label columns, and which columns to ignore (check the columns 'Found in Sample' where 'Not Found' is over 95% of the values, maybe use a user value instead of 95)
  determineValidTMTLabelColumns();
  
  # add columns 'Quantified in all' and 'CVs calculation' after the columns 'Abundance: '
  # add column 'Found in all' after the columns 'Found in Sample: '
  addNewColumns();
  
  # put the results in a Excel file
  my $workbook = createExcelFile($inputFile, $outputFile);
  addGlobalSheet($workbook);
  addCategorySheet($workbook);
  addSummarySheet($workbook);
  print "Closing output file\n";
  $workbook->close();
}

# read excel file and create a hash with 1 entry per line (key is line number)
sub readInputFile {
  my ($inputFile) = @_;
  print "Reading input file\n";
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($inputFile);
  stderr($parser->error()) if(!defined $workbook);
  # open first sheet
  my @worksheets = $workbook->worksheets();
  my $sheet = $worksheets[0];
  # read the content of the file and put it in the main hash
  my ($row_min, $row_max) = $sheet->row_range();
  my ($col_min, $col_max) = $sheet->col_range();
  for my $row ($row_min .. $row_max) {
    for my $col ($col_min .. $col_max) {
      if($row == 0) {
        # create an array to define the order of the columns at the moment of writing the output file
        push(@HEADERS, getValue($sheet, $row, $col));
      } else {
        $DATA{$row}{$HEADERS[$col]} = getValue($sheet, $row, $col);
      }
    }
  }
  $NB_PEPTIDES = scalar(keys(%DATA));
  print "$NB_PEPTIDES peptides have been read\n";
}

# determine the number of TMT label columns, and which columns to ignore (check the columns 'Found in Sample' where 'Not Found' is over 95% of the values, maybe use a user value instead of 95)
# Proteome Discoverer uses a default label name (apparently F1, F2, ...) if there is no user defined name.
sub determineValidTMTLabelColumns {
  # parse the data
  my %labelData;
  foreach my $row (keys(%DATA)) {
    foreach my $col (@HEADERS) {
      if($col =~ m/^Abundances \(Grouped\): /) {
        $labelData{$col}++ if($DATA{$row}{$col} eq "");
        $NB_LABELS++;
      } elsif($col =~ m/^Abundance Ratio: \(.*\) \/ \((.*)\)/) { # may not happen when only running Control
        $DENOM_LABEL = $1;
      }
    }
  }
  print scalar(@HEADERS)." columns have been read\n";
  # check the counts and determine the columns to keep
  foreach my $col (keys(%labelData)) {
    if($labelData{$col} / $NB_PEPTIDES < $PEP_THRESHOLD) {
      $col =~ s/Abundances \(Grouped\): //;
      push(@VALID_LABELS, $col);
    }
  }
  $NB_VALID_LABELS = scalar(@VALID_LABELS);
  @VALID_LABELS = sort(@VALID_LABELS);
  if($NB_VALID_LABELS == 0) {
    push(@VALID_LABELS, "n/a");
    $DENOM_LABEL = "n/a";
    $NB_VALID_LABELS++;
    print "No valid labels have been found, using 'n/a' instead...\n";
  } else {
    print "$NB_VALID_LABELS valid labels have been found: ".join(", ", @VALID_LABELS)."\n";
    if($DENOM_LABEL eq "") {
      $DENOM_LABEL = $VALID_LABELS[0];
      print "No denominator label could be found, default selection is the first in the list: '$DENOM_LABEL'\n";
    } else {
      print "The label used as the denominator for the ratios will be '$DENOM_LABEL'\n";
    }
  }
}

sub isQuantifiedColumn {
  my ($col, $label) = @_;
  $label = ".*" if(!$label || $label eq "");
  #return 1 if($col =~ m/^Abundance: .*: $label, Sample/); # this was the previous condition
  return 1 if($col =~ m/^Abundance: .*: $label, Sample.*/ || $col =~ m/^Abundance: .*: $label, Control.*/);
  # return 1 if($col =~ m/^Abundance: .*: n\/a, Sample.*/ || $col =~ m/^Abundance: .*: n\/a, Control.*/);
  return 1 if($col =~ m/^Abundance: $label: n\/a, Sample.*/ || $col =~ m/^Abundance: $label: n\/a, Control.*/);
  return 0;
}
sub isIdentifiedColumn {
  my ($col, $label) = @_;
  $label = ".*" if(!$label || $label eq "");
  #return 1 if($col =~ m/^Found in Sample: .*: $label, Sample/); # this was the previous condition
  return 1 if($col =~ m/^Found in Sample: .*: $label, Sample.*/ || $col =~ m/^Found in Sample: .*: $label, Control.*/);
  # return 1 if($col =~ m/^Found in Sample: .*: n\/a, Sample.*/ || $col =~ m/^Found in Sample: .*: n\/a, Control.*/);
  return 1 if($col =~ m/^Found in Sample: .* $label: n\/a, Sample.*/ || $col =~ m/^Found in Sample: .* $label: n\/a, Control.*/);
  return 0;
}

sub addNewColumns {
  # search for the column ids to add
  $COL_QUANTINALL = addNewColumn($H_QUANTINALL, "Quan Info");
  $COL_CVCALC = addNewColumn($H_CVCALC, "Quan Info");
  $COL_FOUNDINALL = addNewColumn($H_FOUNDINALL, "Confidence \(by Search Engine\)");
  
  my $nbGhostPeptides = 0;
  # now parse the data and compute the values for each peptide and each new column
  foreach my $row (keys(%DATA)) {
    $DATA{$row}{$H_QUANTINALL} = 0; # make sure there is a value here
    $DATA{$row}{$H_FOUNDINALL} = 0; # make sure there is a value here
    # looking for columns such as 'Abundance: F1: 127N, Sample' or 'Found in Sample: [S10] F1: 127N, Sample' (with 127N as a label)
    my @values;
    foreach my $col (@HEADERS) {
      foreach my $label (@VALID_LABELS) {
        # count the number of non quantified labels per peptide
        if(isQuantifiedColumn($col, $label) == 1) {
          $DATA{$row}{$H_QUANTINALL}++ if($DATA{$row}{$col} ne "" && $DATA{$row}{$col} ne "0");
          push(@values, $DATA{$row}{$col});
        } elsif(isIdentifiedColumn($col, $label) == 1) {
          $DATA{$row}{$H_FOUNDINALL}++ if($DATA{$row}{$col} eq "High");
        }
      }
    }
    # compute the CV
    my $cv = computeCV(@values);
    $DATA{$row}{$H_CVCALC} = $cv;
    # this is a ghost peptide if it has not been identified anywhere
    $nbGhostPeptides++ if(!exists($DATA{$row}{$H_FOUNDINALL}) || $DATA{$row}{$H_FOUNDINALL} eq 0);
  }
  
  $NB_PEPTIDES -= $nbGhostPeptides;
  print "$nbGhostPeptides peptides are never identified anywhere and will be removed from the total count of peptide\n";
  print "$NB_PEPTIDES peptides have been identified at least once\n";
}

sub getColumnIdBySearch {
  my ($columnName) = @_;
  my $i = 0;
  while(rindex($HEADERS[$i++], $columnName, 0) != 0 && $i < scalar(@HEADERS)) {}
  return $i;
}

sub addNewColumn {
  my ($newColumnName, $beforeColumn) = @_;
  my $id = getColumnIdBySearch($beforeColumn) - 1;
  splice(@HEADERS, $id, 0, $newColumnName);
  return $id;
}

sub avg {
  my @data = @_;
  return "n/a" if (scalar(@data) == 0);
  my $total = 0;
  foreach (@data) {
    $total += $_;
  }
  return $total / scalar(@data);
}

sub stdev {
  my @data = @_;
  return 0 if(scalar(@data) == 1);
  my $average = avg(@data);
  my $total = 0;
  foreach(@data) {
    $total += ($average - $_) ** 2;
  }
  my $std = ($total / (scalar(@data) - 1)) ** 0.5;
  return $std;
}

# the standard deviation matches the one from the STANDARD formula in Excel
sub computeCV {
  my @values = grep { $_ ne '' } @_;
  return "" if(scalar(@values) == 0);
  my $avg = avg(@values);
  return $avg if($avg eq "n/a" || $avg == 0);
  my $std = stdev(@values);
  return $std / $avg;
}

sub createExcelFile {
  my ($inputFile, $outputFile) = @_;
  print "Creating a new Excel file named '$outputFile' based on file '$inputFile'\n";
  my $workbook = Excel::Writer::XLSX->new($outputFile);
  return $workbook;
}

sub addPlusOneToSummary {
  my ($info, $label, $row) = @_;
  my $nbQuant = (exists($DATA{$row}{$H_QUANTINALL}) ? $DATA{$row}{$H_QUANTINALL} : 0);
  my $nbIdent = (exists($DATA{$row}{$H_FOUNDINALL}) ? $DATA{$row}{$H_FOUNDINALL} : 0);
  my $cv = (exists($DATA{$row}{$H_CVCALC}) && $DATA{$row}{$H_CVCALC} ne "" ? $DATA{$row}{$H_CVCALC} : 100);
  $SUMMARY{"O"}{$info}{$label}++;
  $SUMMARY{"Q"}{$info}{$label}++ if($nbQuant eq $NB_VALID_LABELS);
  $SUMMARY{"I"}{$info}{$label}++ if($nbIdent eq $NB_VALID_LABELS);
  $SUMMARY{"V"}{$info}{$label}++ if($cv <= $CV_THRESHOLD);
  $SUMMARY{"QV"}{$info}{$label}++ if($nbQuant eq $NB_VALID_LABELS && $cv <= $CV_THRESHOLD);
}

sub storeAbundanceToSummary {
  my ($abundance, $label, $row) = @_;
  my $info = "MED_$label";
  my $nbQuant = (exists($DATA{$row}{$H_QUANTINALL}) ? $DATA{$row}{$H_QUANTINALL} : 0);
  my $nbIdent = (exists($DATA{$row}{$H_FOUNDINALL}) ? $DATA{$row}{$H_FOUNDINALL} : 0);
  my $cv = (exists($DATA{$row}{$H_CVCALC}) && $DATA{$row}{$H_CVCALC} ne "" ? $DATA{$row}{$H_CVCALC} : 100);
  push(@{$SUMMARY{"O"}{$info}}, $abundance);
  push(@{$SUMMARY{"Q"}{$info}}, $abundance) if($nbQuant eq $NB_VALID_LABELS);
  push(@{$SUMMARY{"I"}{$info}}, $abundance) if($nbIdent eq $NB_VALID_LABELS);
  push(@{$SUMMARY{"V"}{$info}}, $abundance) if($cv <= $CV_THRESHOLD);
  push(@{$SUMMARY{"QV"}{$info}}, $abundance) if($nbQuant eq $NB_VALID_LABELS && $cv <= $CV_THRESHOLD);
}

sub addCVsToSummary {
  my ($row) = @_;
  my $nbQuant = (exists($DATA{$row}{$H_QUANTINALL}) ? $DATA{$row}{$H_QUANTINALL} : 0);
  my $nbIdent = (exists($DATA{$row}{$H_FOUNDINALL}) ? $DATA{$row}{$H_FOUNDINALL} : 0);
  my $cv = (exists($DATA{$row}{$H_CVCALC}) && $DATA{$row}{$H_CVCALC} ne "" ? $DATA{$row}{$H_CVCALC} : 100);
  my $last = 0;
  foreach my $cat (@CV_CATEGORIES) {
    if($cv >= $last && $cv < $cat) {
      my $info = "NBCVlt$cat";
      $SUMMARY{"O"}{$info}++;
      $SUMMARY{"Q"}{$info}++ if($nbQuant eq $NB_VALID_LABELS);
      $SUMMARY{"I"}{$info}++ if($nbIdent eq $NB_VALID_LABELS);
      $SUMMARY{"V"}{$info}++ if($cv <= $CV_THRESHOLD);
      $SUMMARY{"QV"}{$info}++ if($nbQuant eq $NB_VALID_LABELS && $cv <= $CV_THRESHOLD);
    }
    $last = $cat;
  }
  # also store if the cv exceeds 100%
  if($cv >= $CV_CATEGORIES[-1]) {
    my $info = "NBCVlt100+";
    $SUMMARY{"O"}{$info}++;
    $SUMMARY{"Q"}{$info}++ if($nbQuant eq $NB_VALID_LABELS);
    $SUMMARY{"I"}{$info}++ if($nbIdent eq $NB_VALID_LABELS);
    $SUMMARY{"V"}{$info}++ if($cv <= $CV_THRESHOLD);
    $SUMMARY{"QV"}{$info}++ if($nbQuant eq $NB_VALID_LABELS && $cv <= $CV_THRESHOLD);
  }
}

sub addGlobalSheet {
  my ($workbook) = @_;
  print "Adding sheet 'All peptides'\n";
  my $worksheet = addWorksheet($workbook, "All peptides");
  # prepare formats
  my $formatH = $workbook->add_format(%F_HEADER, %F_BORDERS, %F_BLUE);
  my $formatHY = $workbook->add_format(%F_HEADER, %F_BORDERS, %F_YELLOW);
  my $formatHR = $workbook->add_format(%F_HEADER, %F_BORDERS, %F_RED);
  # write the first line with the headers
  my $colId = 0;
  foreach (@HEADERS) {
    my $format = $formatH;
    $format = $formatHY if(isQuantifiedColumn($_) == 1 || $_ eq $H_QUANTINALL || $_ eq $H_CVCALC);
    $format = $formatHR if(isIdentifiedColumn($_) == 1 || $_ eq $H_FOUNDINALL);
    $worksheet->write(0, $colId++, $_, $format);
  }
  # write the content of %DATA in the new sheet, and store/compute on the fly
  foreach my $row (keys(%DATA)) {
    $colId = 0;
    # store CV per category
    addCVsToSummary($row);
    foreach my $col (@HEADERS) {
      my $cell = $DATA{$row}{$col};
      # gather relevant information
      if($col eq $H_QUANTINALL) {
        if($cell == 0) {
          addPlusOneToSummary("nbQ", "N", $row);
        } else {
          addPlusOneToSummary("nbQ", "1+", $row);
          addPlusOneToSummary("nbQ", "A", $row) if($cell == $NB_VALID_LABELS);
        }
        addPlusOneToSummary("nbQ", $cell, $row);
      } elsif($col eq $H_FOUNDINALL) {
        if($cell == 0) {
          addPlusOneToSummary("nbI", "N", $row);
        } else {
          addPlusOneToSummary("nbI", "1+", $row);
          addPlusOneToSummary("nbI", "A", $row) if($cell == $NB_VALID_LABELS);
        }
        addPlusOneToSummary("nbI", $cell, $row);
      } else {
        foreach my $label (@VALID_LABELS) {
          if(isQuantifiedColumn($col, $label) == 1) {
            if($cell ne "") {
              addPlusOneToSummary("nbQ", $label, $row);
              storeAbundanceToSummary($cell, $label, $row);
            }
          } elsif(isIdentifiedColumn($col, $label) == 1) {
            addPlusOneToSummary("nbI", $label, $row) if($cell eq "High");
          }
        }
      }
      # write the line
      $worksheet->write($row, $colId++, $cell);
    }
  }
  
  # finalize the sheet
  $worksheet->freeze_panes(1);
  $worksheet->autofilter(0, 0, $NB_PEPTIDES, scalar(@HEADERS) - 1);
}

sub addSummarySheet {
  my ($workbook) = @_;
  print "Adding sheet 'Summary'\n";
  my $worksheet = addWorksheet($workbook, "Summary");

  # prepare formats
  my $fNormal = $workbook->add_format();
  my $fWarning = $workbook->add_format(%F_WARNING);
  my $fHeader = $workbook->add_format(%F_HEADER, %F_BORDERS, %F_BLUE);
  my $fHeaderDenom = $workbook->add_format(%F_HEADER, %F_BORDERS, %F_YELLOW);
  my $fMerge = $workbook->add_format(%F_MERGE, %F_BORDERS);
  my $fBorderBottom = $workbook->add_format(%F_BORDER_B);
  my $fBorderRight = $workbook->add_format(%F_BORDER_R);
  my $fBorderBottomRight = $workbook->add_format(%F_BORDER_B, %F_BORDER_R);
  my $fNormalPct = $workbook->add_format(%F_PCT);
  my $fBorderRightPct = $workbook->add_format(%F_BORDER_R, %F_PCT);
  my $fBorderBottomDec = $workbook->add_format(%F_BORDER_B, %F_DEC);
  my $fBorderBottomRightDec = $workbook->add_format(%F_BORDER_B, %F_BORDER_R, %F_DEC);
  my $formatLeft = $workbook->add_format(%F_ALIGNLEFT);
  # Colors have been removed
  # my $fQuantNum = $workbook->add_format(%F_YELLOW);
  # my $fQuantNumLast = $workbook->add_format(%F_YELLOW, %F_BORDER_R);
  # my $fQuantPct = $workbook->add_format(%F_PCT, %F_YELLOW);
  # my $fQuantPctLast = $workbook->add_format(%F_PCT, %F_YELLOW, %F_BORDER_R);
  # my $fIdentNum = $workbook->add_format(%F_ORANGE);
  # my $fIdentNumLast = $workbook->add_format(%F_ORANGE, %F_BORDER_R);
  # my $fIdentPct = $workbook->add_format(%F_PCT, %F_ORANGE);
  # my $fIdentPctLast = $workbook->add_format(%F_PCT, %F_ORANGE, %F_BORDER_R);
  # my $fRatio = $workbook->add_format(%F_DEC, %F_BLUE, %F_BORDER_B);
  # my $fRatioLast = $workbook->add_format(%F_DEC, %F_BLUE, %F_BORDER_B, %F_BORDER_R);
  my $fQuantNum = $workbook->add_format();
  my $fQuantNumLast = $workbook->add_format(%F_BORDER_R);
  my $fQuantPct = $workbook->add_format(%F_PCT);
  my $fQuantPctLast = $workbook->add_format(%F_PCT, %F_BORDER_R);
  my $fIdentNum = $workbook->add_format();
  my $fIdentNumLast = $workbook->add_format(%F_BORDER_R);
  my $fIdentPct = $workbook->add_format(%F_PCT);
  my $fIdentPctLast = $workbook->add_format(%F_PCT, %F_BORDER_R);
  my $fRatio = $workbook->add_format(%F_DEC, %F_BORDER_B);
  my $fRatioLast = $workbook->add_format(%F_DEC, %F_BORDER_B, %F_BORDER_R);
  
  # prepare for the median denominator
  my $colDenom = 0;
  
  # write headers
  my @headers = ("Category", "Information", @VALID_LABELS);
  for (my $i = 1; $i < $NB_VALID_LABELS; $i++) {
    my $header = ($i > 1 ? "$i labels" : "$i label");
    push(@headers, $header);
  }
  push(@headers, $COLS->{"A"});
  push(@headers, $COLS->{"1+"});
  push(@headers, $COLS->{"N"});
  my $colId = 0;
  foreach (@headers) {
    $colDenom = $colId if($_ eq $DENOM_LABEL);
    $worksheet->write(0, $colId++, $_, $fHeader);
  }
  
  # prepare order of data
  my @categories = ("O", "Q", "I", "V", "QV");
  my $nbCats = scalar(@categories);
  my @info = ("nbQ", "nbI", "M", "R");
  # only add lines pctQ, pctQI and pctI if requested
  @info = ("nbQ", "pctQ", "pctQI", "nbI", "pctI", "M", "R") if($ADD_PERCENTAGES eq "true");
  my $nbInfo = scalar(@info);
  
  # prepare denominators addresses
  my $adrNbQuantified = getAddress(1, scalar(@headers) - 2);
  my $adrNbIdentified = getAddress(4, scalar(@headers) - 2);
  
  # write each category (Overall, etc)
  for (my $i = 0; $i < $nbCats; $i++) {
    my $row = $i * $nbInfo + 1;
    my $line = $row;
    my $cat = $categories[$i];
    $worksheet->merge_range($row, 0, $row + $nbInfo - 1, 0, $CATEGORIES->{$cat}, $fMerge);
    # Quantified and identified peptides
    $worksheet->write($line++, 1, $INFO->{"nbQ"}, $fBorderBottomRight);
    $worksheet->write($line++, 1, $INFO->{"pctQ"}, $fBorderBottomRight) if($ADD_PERCENTAGES eq "true");
    $worksheet->write($line++, 1, $INFO->{"pctQI"}, $fBorderBottomRight) if($ADD_PERCENTAGES eq "true");
    $worksheet->write($line++, 1, $INFO->{"nbI"}, $fBorderBottomRight);
    $worksheet->write($line++, 1, $INFO->{"pctI"}, $fBorderBottomRight) if($ADD_PERCENTAGES eq "true");
    $worksheet->write($line++, 1, $INFO->{"M"}, $fBorderBottomRight);
    # ratio header will be written later
    # prepare the median for the lowest value
    my $adrDenomMedian = getAddress($line++, $colDenom);
    # Results per label
    for (my $j = 0; $j < $NB_VALID_LABELS; $j++) {
      my $line = $row;
      my $label = $VALID_LABELS[$j];
      my $nbQ = (exists($SUMMARY{$cat}{"nbQ"}{$label}) ? $SUMMARY{$cat}{"nbQ"}{$label} : 0);
      my $nbI = (exists($SUMMARY{$cat}{"nbI"}{$label}) ? $SUMMARY{$cat}{"nbI"}{$label} : 0);
      my $format = ($j == $NB_VALID_LABELS - 1 ? $fBorderRight : $fNormal);
      $worksheet->write($line++, $j + 2, $nbQ, $format);
      $worksheet->write($line++, $j + 2, "", $format) if($ADD_PERCENTAGES eq "true");
      $worksheet->write($line++, $j + 2, "", $format) if($ADD_PERCENTAGES eq "true");
      $worksheet->write($line++, $j + 2, $nbI, $format);
      $worksheet->write($line++, $j + 2, "", $format) if($ADD_PERCENTAGES eq "true");
      # add median abundances
      my $median = calcMedian($cat, $label);
      $worksheet->write_number($line++, $j + 2, $median, $format);
      $format = ($j == $NB_VALID_LABELS - 1 ? $fRatioLast : $fRatio);
      # ratios will be written later
    }
    # Results per label category (percentages should be written as formula)
    $colId = $NB_VALID_LABELS + 1;
    foreach my $j (1 .. ($NB_VALID_LABELS - 1)) {
      my $line = $row;
      my $column = $colId + $j;
      my $nbQ = (exists($SUMMARY{$cat}{"nbQ"}{$j}) ? $SUMMARY{$cat}{"nbQ"}{$j} : 0);
      my $nbI = (exists($SUMMARY{$cat}{"nbI"}{$j}) ? $SUMMARY{$cat}{"nbI"}{$j} : 0);
      $worksheet->write($line++, $column, $nbQ, ($j == $NB_VALID_LABELS - 1 ? $fBorderRight : $fNormal));
      $worksheet->write_formula($line++, $column, "=".getAddress($row, $column)."/$adrNbQuantified", ($j == $NB_VALID_LABELS - 1 ? $fBorderRightPct : $fNormalPct)) if($ADD_PERCENTAGES eq "true");
      $worksheet->write_formula($line++, $column, "=".getAddress($row, $column)."/$adrNbIdentified", ($j == $NB_VALID_LABELS - 1 ? $fBorderRightPct : $fNormalPct)) if($ADD_PERCENTAGES eq "true");
      $worksheet->write($line++, $column, $nbI, ($j == $NB_VALID_LABELS - 1 ? $fBorderRight : $fNormal));
      $worksheet->write_formula($line++, $column, "=".getAddress($line - 2, $column)."/$adrNbIdentified", ($j == $NB_VALID_LABELS - 1 ? $fBorderRightPct : $fNormalPct)) if($ADD_PERCENTAGES eq "true");
      $worksheet->write($line++, $column, "", ($j == $NB_VALID_LABELS - 1 ? $fBorderRight : $fNormal));
      $worksheet->write($line++, $column, "", ($j == $NB_VALID_LABELS - 1 ? $fBorderBottomRight : $fBorderBottom));
    }
    $colId += $NB_VALID_LABELS;
    foreach my $j ("A", "1+", "N") {
      my $line = $row;
      my $nbQ = (exists($SUMMARY{$cat}{"nbQ"}{$j}) ? $SUMMARY{$cat}{"nbQ"}{$j} : 0);
      my $nbI = (exists($SUMMARY{$cat}{"nbI"}{$j}) ? $SUMMARY{$cat}{"nbI"}{$j} : 0);
      $worksheet->write($line++, $colId, $nbQ, ($j eq "N" ? $fQuantNumLast : $fQuantNum));
      $worksheet->write_formula($line++, $colId, "=".getAddress($row, $colId)."/$adrNbQuantified", ($j eq "N" ? $fQuantPctLast : $fQuantPct)) if($ADD_PERCENTAGES eq "true");
      $worksheet->write_formula($line++, $colId, "=".getAddress($row, $colId)."/$adrNbIdentified", ($j eq "N" ? $fQuantPctLast : $fQuantPct)) if($ADD_PERCENTAGES eq "true");
      $worksheet->write($line++, $colId, $nbI, ($j eq "N" ? $fIdentNumLast : $fIdentNum));
      $worksheet->write_formula($line++, $colId, "=".getAddress($line - 2, $colId)."/$adrNbIdentified", ($j eq "N" ? $fIdentPctLast : $fIdentPct)) if($ADD_PERCENTAGES eq "true");
      $worksheet->write($line++, $colId, "", ($j eq "N" ? $fBorderRight : $fNormal));
      $worksheet->write($line++, $colId++, "", ($j eq "N" ? $fBorderBottomRight : $fBorderBottom));
    }
  }
  
  # prepare next loop
  my $row = $nbCats * $nbInfo;
  # add a line at the end to warn that PD returns peptides identified in no labels at all and that these peptides are not considered here
  $worksheet->write($row + 2, 0, "Warning: Proteome Discoverer may return peptides although they are not identified in any label! Such peptides are not considered in the percentages displayed above.", $fWarning);
  # add denominator line
  $worksheet->write($row + 4, 0, "Label used as denominator:");
  $worksheet->write($row + 4, 1, $DENOM_LABEL, $formatLeft);
  my $denomAddress = getAddress($row + 4, 1);
  $INFO->{"R"} =~ s/_/"&$denomAddress&"/;
  $INFO->{"R"} = "=\"".$INFO->{"R"}."\"";
  my $lastRow = $row;
  my $lastCol = scalar(@headers) - 1;
  # next loop for adaptative ratios
  $worksheet->conditional_formatting("C1:".getColumnName($NB_VALID_LABELS+1)."1", { type => 'cell', criteria => '=', value => $denomAddress, format => $fHeaderDenom});
  for (my $i = 0; $i < $nbCats; $i++) {
    my $row = $i * $nbInfo + 1;
    my $cat = $categories[$i];
    $worksheet->write_formula($row + $nbInfo - 1, 1, $INFO->{"R"}, $fBorderBottomRight);
    for (my $j = 0; $j < $NB_VALID_LABELS; $j++) {
      my $format = ($j == $NB_VALID_LABELS - 1 ? $fRatioLast : $fRatio);
      my $adrDenomMedian = "INDEX(".getAddress(0, 0).":".getAddress($lastRow, $lastCol).", ROW(".getAddress($row + $nbInfo - 1, $j + 2).") - 1, MATCH($denomAddress,\$1:\$1,0))";
      $worksheet->write_formula($row + $nbInfo - 1, $j + 2, "=".getAddress($row + $nbInfo - 2, $j + 2)."/".$adrDenomMedian, $format);
    }
  }
  
  # set columns width: 25 55 12..12
  $worksheet->set_column(0, 0, 25);
  $worksheet->set_column(1, 1, 55);
  $worksheet->set_column(2, $lastCol, 12);

  # finalize the sheet
  $worksheet->freeze_panes(1);
  $worksheet->autofilter(0, 0, $lastRow, $lastCol);
}

sub calcMedian {
  my ($category, $label) = @_;
  return "" if(!exists($SUMMARY{$category}{"MED_$label"}));
  my @values = @{$SUMMARY{$category}{"MED_$label"}};
  # @values = grep { $_ ne '' } @values;
  return "" if(scalar(@values) == 0);
  return median(@values);
}

# sub ratio {
  # my ($num, $denom) = @_;
  # return "#n/a" if(!$num || $num eq "");
  # return "#div/0" if(!$denom || $denom eq "n/a" || $denom eq 0);
  # return 0 if($num eq 0);
  # return $num / $denom;
# }

# this method starts at 0 ! So the column A will match to value 0
sub getColumnName {
  my ($number) = (@_);
    # A = chr(65)
  return chr($number + 65) if($number < 26);
  return chr((int($number / 26) - 1) + 65) . chr(($number % 26) + 65) if($number < 676);
  return "Error: $number is too big";
}

sub getAddress() {
  my ($row, $column) = @_;
  return "\$".getColumnName($column)."\$".($row+1);
}

sub addCategorySheet {
  my ($workbook) = @_;
  print "Adding sheet 'CV categories'\n";
  my $worksheet = addWorksheet($workbook, "CV categories");
  
  # prepare formats
  my $fHeader = $workbook->add_format(%F_HEADER, %F_BORDERS, %F_BLUE);
  my $fBorderAll = $workbook->add_format(%F_BORDERS);
  
  # Add the CV categories after the main table
  my @categories = ("O", "Q", "I", "V", "QV");
  my $row = 0;
  my $colId = 0;
  my $last = 0;
  $worksheet->write($row, $colId++, "CV categories", $fHeader);
  foreach (@CV_CATEGORIES) {
    my $cat = $_ * 100;
    $worksheet->write($row, $colId++, "$last% until $cat%", $fHeader);
    $last = $cat;
  }
  $worksheet->write($row, $colId++, ($last eq 100 ? "Exactly $last%" : "$last% and over"), $fHeader);
  for (my $i = 0; $i < scalar(@categories); $i++) {
    $colId = 0;
    my $cat = $categories[$i];
    $worksheet->write(++$row, $colId++, $CATEGORIES->{$cat}, $fBorderAll);
    foreach (@CV_CATEGORIES) {
      my $nb = (exists($SUMMARY{$cat}{"NBCVlt$_"}) ? $SUMMARY{$cat}{"NBCVlt$_"} : 0);
      $worksheet->write($row, $colId++, $nb, $fBorderAll);
    }
    my $nb = (exists($SUMMARY{$cat}{"NBCVlt100+"}) ? $SUMMARY{$cat}{"NBCVlt100+"} : 0);
    $worksheet->write($row, $colId++, $nb, $fBorderAll);
  }
  
  $worksheet->autofilter(0, 0, $row - 1, scalar(@CV_CATEGORIES) + 1);
  $worksheet->set_column(0, 0, 45);
  $worksheet->set_column(1, scalar(@CV_CATEGORIES) + 1, 15);
}
