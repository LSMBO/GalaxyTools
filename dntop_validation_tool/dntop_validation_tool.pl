#!/usr/bin/perl
use strict;
use warnings;

use URI::Escape;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(booleanToString parameters stderr);
use LsmboExcel qw(addWorksheet getValue);

# dN-TOP Validation Tool is designed to extract peptide pairs with two different chemical derivatizations from
# an export coming from Proline Studio (http://proline.profiproteomics.fr/, ProFI, French Proteomics Infrastructure).
# It was developed to automate our light/heavy TMPP-based N-terminomics workflow, dN-TOP, and can also be used for 
# any other mass adducts or PTMs. A couple of light and heavy TMPP-derivatized peptides is validated only if the 
# identification of the light/heavy pair of the same peptide sequence, with identical modifications and close 
# elution time is made. N-termini positions are validated only if the spectra used for the identification provides 
# an unambiguous peptide sequence and, if any, the exact position of a modification. Validated couples of light and
# heavy TMPP-derivatized peptides are extracted and listed on a new sheet and the unicity of the peptide sequence 
# in the searched database is indicated.


my ($paramFile, $outputFile) = @ARGV;

# read parameters and add quick access to some parameters
my %PARAMS = %{parameters($paramFile)};
my $B = booleanToString($PARAMS{"jokers"}{"B"}) if exists($PARAMS{"jokers"}{"B"});
my $J = booleanToString($PARAMS{"jokers"}{"J"}) if exists($PARAMS{"jokers"}{"J"});
my $PTM1 = $PARAMS{"ptm1"};
my $PTM2 = $PARAMS{"ptm2"};
my $MODTAG1 = "-Mod1";
my $MODTAG2 = "-Mod2";

# quick access to columns
my $cPep = getColumnName("cPep");
my $cSeq = getColumnName("cSeq");
my $cMod = getColumnName("cMod");
my $cQid = getColumnName("cQid");
my $cDpm = getColumnName("cDpm");
my $cRT = $PARAMS{"columns"}{"cRT"};

# we will add the following columns to the hash (only the last one will be kept in the output file)
my $cSil = "modified sequence with I replaced by L"; # this is the peptide group identifier
my $cCM1 = "concatenation of cSil and mod1"; # identifies the peptides of a group that have the first PTM
my $cCM2 = "concatenation of cSil and mod2"; # identifies the peptides of a group that have the first PTM
my $cFinal = "Unicity"; # Shared or Unique (should be the only column left at the end)

# declare hashes that will be needed
my @HEADERS; # input table headers list
my %DATA;    # input table content, stored as $DATA{row_number}{header_name}
my %SPECTRA; # number of rows per query id
my %QSM;     # number of rows per peptide group
# read the excel file and store everything in those hashes
readInputFileXlsx();
print scalar(keys(%DATA))." rows have been read\n";

# first loop: delete the rows that do not fit in a peptide group
my %DB_MATCHES;
my %MOD_COUNTS;
foreach my $row (keys(%DATA)) {
  if((hasPtm1($row) eq 0 && hasPtm2($row) eq 0) || $SPECTRA{$DATA{$row}{$cQid}} ne $QSM{getFullPeptideGroupId($row)}) {
    # a peptide group must have peptides that have one of the PTMs
    # a peptide group must not match to a spectrum that belong to another group
    delete $DATA{$row};
  } else {
    # prepare next loop with those values
    # get the sum of databank_protein_matches per peptide sequence and spectrum
    $DB_MATCHES{$DATA{$row}{$cPep}}{$DATA{$row}{$cQid}} += $DATA{$row}{$cDpm};
    # count the number of peptides with each PTM per group
    $MOD_COUNTS{getPepIdPtm1($row)} = 0 if(!exists($MOD_COUNTS{getPepIdPtm1($row)}));
    $MOD_COUNTS{getPepIdPtm2($row)} = 0 if(!exists($MOD_COUNTS{getPepIdPtm2($row)}));
    $MOD_COUNTS{$DATA{$row}{$cCM1}}++;
    $MOD_COUNTS{$DATA{$row}{$cCM2}}++;
  }
}
print scalar(%DATA)." rows matching peptide groups\n";

# second loop: delete groups that do not have both PTMs
my %RT_SUM;
foreach my $row (keys(%DATA)) {
  if($MOD_COUNTS{getPepIdPtm1($row)} eq 0 || $MOD_COUNTS{getPepIdPtm2($row)} eq 0) {
    delete $DATA{$row};
  } else {
    # with the valid rows, sum the RT that belong to the same group and for each PTM
    $RT_SUM{$DATA{$row}{$cCM1}} += $DATA{$row}{$cRT};
    $RT_SUM{$DATA{$row}{$cCM2}} += $DATA{$row}{$cRT};
  }
}
print scalar(%DATA)." rows matching peptide groups with both PTMs\n";

# third loop: delete groups where the average RT for PTM1 is too far away from the average RT for PTM2
foreach my $row (keys(%DATA)) {
  if(getDeltaRT($row) > $PARAMS{"deltaRT"}) {
    delete $DATA{$row};
  } else {
    # the remaining rows are valid, we only need to tell which are unique and which are shared
    my $dbMatches = 0;
    foreach my $pep (keys(%DB_MATCHES)) {
      $dbMatches += $DB_MATCHES{$pep}{$DATA{$row}{$cQid}} if(exists($DB_MATCHES{$pep}{$DATA{$row}{$cQid}}));
    }
    # the peptide group is considered unique if the number of protein matches per spectrum is 1
    $DATA{$row}{$cFinal} = $dbMatches eq 1 ? "Unique" : "Shared";
  }
}
print scalar(%DATA)." rows matching peptide groups with a valid Delta RT\n";

# write the report
push(@HEADERS, $cFinal);
# writeTextOutput();
createExcelFile($outputFile);

print "Correct ending of the script\n";


exit;

sub getColumnName {
  my $column = $PARAMS{"columns"}{$_[0]};
  $column =~ s/__pd__/\#/;
  return $column;
}

sub readInputFileXlsx {
  # print STDERR "Reading Excel input file\n";
  print "Reading Excel input file\n";
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($PARAMS{"excelFile"});
  stderr($parser->error()) if(!defined $workbook);
  # open first sheet
  my @worksheets = $workbook->worksheets();
  my $sheet = $worksheets[$PARAMS{"sheetNumber"} - 1];
  # read the content of the file and put it in the main hash
  my ($row_min, $row_max) = $sheet->row_range();
  my ($col_min, $col_max) = $sheet->col_range();
  # get the headers first
  for my $col ($col_min .. $col_max) {
    # put the headers in an array to define the order of the columns at the moment of writing the output file
    push(@HEADERS, getValue($sheet, $row_min, $col));
  }
  # make sure we find the following columns: peptide_id, sequence, modifications, spectrum_title, #databank_protein_matches, rt
  foreach my $col ("cPep", "cSeq", "cMod", "cQid", "cDpm", "cRT") {
    my $columnName = getColumnName($col);
    stderr("'$columnName' column is not found") if(!grep { $_ eq $columnName} @HEADERS );
  }
  # now read the content of the table
  my $lastSpectrumId = 1;
  for my $row ($row_min +1 .. $row_max) {
    for my $col ($col_min .. $col_max) {
      # each cell is being identified by its row number and the column header name
      $DATA{$row}{$HEADERS[$col]} = getValue($sheet, $row, $col);
    }
    $DATA{$row}{$cSil} = getModifiedSequence($row);
    $DATA{$row}{$cCM1} = hasPtm1($row) ? getPepIdPtm1($row) : "";
    $DATA{$row}{$cCM2} = hasPtm2($row) ? getPepIdPtm2($row) : "";
    # count numbers of spectra
    $SPECTRA{$DATA{$row}{$cQid}}++;
    $QSM{getFullPeptideGroupId($row)}++;
  }
}

sub getModifiedSequence {
  my ($row) = @_;
  my $sequence = $DATA{$row}{$cSeq};
  # $sequence =~ s/I/L/g; # use this instead of the next two rows to get the results from the old macro
  $sequence =~ s/[IL]/J/g if($J eq "true");
  $sequence =~ s/[DN]/B/g if($B eq "true");
  my $mods = $DATA{$row}{$cMod};
  $mods =~ s/\Q${PTM1}/TMPP/g; # \Q avoids problems with special characters in $PTM1
  $mods =~ s/\Q${PTM2}/TMPP/g;
  $sequence .= $mods; # i do not understand why we add that with those substitutions
  return $sequence;
}

sub getPepIdPtm1 { return $DATA{$_[0]}{$cSil}.$MODTAG1; }
sub getPepIdPtm2 { return $DATA{$_[0]}{$cSil}.$MODTAG2; }
sub getFullPeptideGroupId { return $DATA{$_[0]}{$cQid}.$DATA{$_[0]}{$cSil}.$DATA{$_[0]}{$cMod}; }

sub hasPtm1 { return hasPtm($_[0], $PTM1); }
sub hasPtm2 { return hasPtm($_[0], $PTM2); }
sub hasPtm { return index($DATA{$_[0]}{$cMod}, $_[1]) != -1 ? 1 : 0; }

sub getDeltaRT {
  my ($row) = @_;
  my $rt1 = getAverageRT($row, $MODTAG1);
  my $rt2 = getAverageRT($row, $MODTAG2);
  my $delta = abs($rt1 - $rt2);
  $delta *= 60 if($PARAMS{"columns"}{"rtUnit"} eq "min"); # transform into seconds
  return $delta;
}
sub getAverageRT {
  my ($row, $modTag) = @_;
  my $sum = exists($RT_SUM{$DATA{$row}{$cSil}.$modTag}) ? $RT_SUM{$DATA{$row}{$cSil}.$modTag} : 0;
  my $total = $MOD_COUNTS{$DATA{$row}{$cSil}.$modTag};
  return 0 if($total eq 0);
  return $sum / $total;
}

# sub writeTextOutput {
  ##print the results
  # my $nbLines = 0;
  # my $nbUnique = 0;
  # print STDOUT join("\t", @HEADERS)."\n";
  # foreach my $row (sort { $DATA{$a}{$cSeq} cmp $DATA{$b}{$cSeq} } keys %DATA) {
    # my @cells;
    # foreach my $header (@HEADERS) {
      # push(@cells, $DATA{$row}{$header});
    # }
    # print STDOUT join("\t", @cells)."\n";
    # $nbLines++;
    # $nbUnique++ if($DATA{$row}{$cFinal} eq "Unique");
  # }
  # print "$nbLines rows have been written to the output, including $nbUnique that belong to a unique peptide\n";
# }

sub createExcelFile {
  my ($outputFile) = @_;
  my $inputFile = $PARAMS{"excelFile"};
  print "Creating a new Excel file named '$outputFile' based on file '$inputFile'\n";
  my ($self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputFile);
  $self->parse_template();
  print "Adding sheet 'All peptides'\n";
  my $worksheet = addWorksheet($workbook, "dN-TOP");
  # prepare formats
  my $fHeader = $workbook->add_format(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
  my $fRow = $workbook->add_format();
  my $fRowBottom = $workbook->add_format(bottom => 1);
  my $fShared = $workbook->add_format(bg_color => '#EB7D4B');
  my $fSharedBottom = $workbook->add_format(bottom => 1, bg_color => '#EB7D4B');
  my $fUnique = $workbook->add_format(bg_color => '#8CD264');
  my $fUniqueBottom = $workbook->add_format(bottom => 1, bg_color => '#8CD264');
  # prepare counters
  my $rowNumber = 0;
  my $colId = 0;
  my $nbUnique = 0;
  # write the headers
  foreach (@HEADERS) {
    $worksheet->write($rowNumber, $colId++, $_, $fHeader);
  }
  # get the list of rows ordered to regroup the peptides together
  my @rows = sort { $DATA{$a}{$cSeq} cmp $DATA{$b}{$cSeq} } keys %DATA;
  # write the content of %DATA in the new sheet
  for (my $i = 0; $i < scalar(@rows); $i++) {
    my $row = $rows[$i];
    # isBottom is true when i = scalar(rows) or sequence(i) != sequence(i+1)
    my $isBottom = 0;
    $isBottom = 1 if($i == scalar(@rows) - 1 || $DATA{$row}{$cSeq} ne $DATA{$rows[$i + 1]}{$cSeq});
    $rowNumber++;
    $colId = 0;
    foreach my $header (@HEADERS) {
      my $value = $DATA{$row}{$header};
      my $format = $fRow;
      if($header eq $cFinal) {
        if($value eq "Shared") {
          $format = $isBottom == 1 ? $fSharedBottom : $fShared;
        } elsif($value eq "Unique") {
          $format = $isBottom == 1 ? $fUniqueBottom : $fUnique;
          $nbUnique++;
        }
      } elsif($isBottom == 1) {
        $format = $fRowBottom;
      }
      $worksheet->write($rowNumber, $colId++, $value, $format);
    }
  }
  # finalize the sheet
  $worksheet->freeze_panes(1); # freeze the first row
  $worksheet->autofilter(0, 0, $rowNumber, scalar(@HEADERS) - 1); # add autofilters
  $worksheet->activate(); # display this sheet directly when opening the file
  $workbook->close();
  print "$rowNumber rows have been written to the output, including $nbUnique that belong to a unique peptide\n";
}