#!/usr/bin/perl
package LsmboExcel;

use strict;
use warnings;

use LsmboFunctions;
use Spreadsheet::ParseExcel::Utility 'sheetRef';
# use Spreadsheet::Reader::ExcelXML;
use Spreadsheet::ParseXLSX;
use Excel::Template::XLSX; # wraps Excel::Writer::XLSX and allows to create a new file with the data of an old one

# only export these methods so they can be used without specifying the namespace
use Exporter qw(import);
our @EXPORT = qw(addWorksheet getColumnId getValue extractIds writeExcelLine writeExcelLineF setColumnsWidth);


# Reads a cell from an Excel file
# $sheet must be a Spreadsheet::Reader::ExcelXML object
sub getValue {
  my ($sheet, $row, $col) = @_;
  my $cell = $sheet->get_cell($row, $col);
  # apparently this library provides different ways of handling cell values, i hope i covered everything !
  eval {
    return $cell->unformatted();
  } or do {
    eval {
      return $cell->value();
    } or do {
      # so far i've only seen this for zero values...
      # return 0 if($cell && $cell ne 'EOR'); # we are not expecting any 0 as a category or a GO
      return $cell->value() if($cell);
      return "";
    }
  };
}

# Reads an Excel file and extract values from a given column
sub extractIds {
  my ($xlsxFile, $sheetNumber, $cellAddress) = @_;
  # open excel file
  print "Opening file $xlsxFile at sheet #$sheetNumber, reading from cell $cellAddress\n";
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($xlsxFile);
  LsmboFunctions::stderr($parser->error()) if(!defined $workbook);
  my @worksheets = $workbook->worksheets();
  my $sheet = $worksheets[$sheetNumber-1];
  # get rows and columns
  my ($row, $col) = sheetRef($cellAddress);
  my ($row_min, $row_max) = $sheet->row_range();
  # open the output file
  my @ids;
  # read the columns and print each id to the file
  for my $i ($row .. $row_max) {
    push(@ids, getValue($sheet, $i, $col));
  }
  # returns all the ids
  return @ids;
}

# write an array of values without format
sub writeExcelLine {
  my ($sheet, $row, @cells) = @_;
  writeExcelLineF($sheet, $row, undef, @cells);
}

# write an array of values with given format
sub writeExcelLineF {
  my ($sheet, $row, $format, @cells) = @_;
  my $col = 0;
  foreach my $cell (@cells) {
    $sheet->write($row, $col++, $cell, $format);
  }
}

# sets width for multiple columns
# width in pixel here corresponds to 1/5 of the size in centimeter displayed in Excel
# so if you want a column with a size of 3cm, use the value 15 (3x5)
sub setColumnsWidth {
  my ($sheet, @widths) = @_;
  for(my $i = 0; $i < scalar(@widths); $i++) {
    $sheet->set_column($i, $i, $widths[$i]);
  }
}

# transforms a letter representing an Excel column into its number equivalent
sub getColumnId {
  my @ids = ();
  foreach my $column (@_) {
    # A = 65
    push(@ids, ord(uc($column)) - 65); # TODO check if first column is zero or one
  }
  return @ids;
}

# adds a worksheet with a unique and valid name
sub addWorksheet {
  my ($workbook) = @_;
  # easy case: no name given to the sheet
  return $workbook->add_worksheet() if(scalar(@_) == 1);
  # or a name is given but it is not valid
  return $workbook->add_worksheet() if(scalar(@_) > 1 && isSheetNameValid($_[1]) == 0);
  # when a name is provided we have to make sure it's unique
  my $i = 0;
  my $defaultSheetName = $_[1];
  my $sheetName = $defaultSheetName;
  my $worksheet;
  # avoid infinite loop
  while($i < 10) {
    eval {
      # try to create the sheet with the given name
      $worksheet = $workbook->add_worksheet($sheetName);
      # exit the loop after the first success (hopefully the first try !)
      $i = 10;
    } or $sheetName = $defaultSheetName." (".($i+2).")";
    $i++;
  }
  # return the created worksheet if it worked
  return $worksheet if($worksheet);
  # otherwise fall back on the default sheet name
  # it can happen if there are already 10 sheets with that name, or if the name with the number exceeds 32 characters
  return $workbook->add_worksheet();
}

# checks all restrictions
sub isSheetNameValid {
  my ($sheetName) = @_;
  # must not be "History" or "Historique"
  return LsmboFunctions::stdwarn("Excel sheet name '$sheetName' is not valid: names 'History' or 'Historique' are not allowed") if($sheetName eq "History" || $sheetName eq "Historique");
  # must be less than 32 characters
  return LsmboFunctions::stdwarn("Excel sheet name '$sheetName' is not valid: name length must be less than 32 characters") if(length($sheetName) > 32);
  # must not start or end with an apostrophe
  return LsmboFunctions::stdwarn("Excel sheet name '$sheetName' is not valid: name cannot start with an apostrophe") if($sheetName =~ m/^'/);
  return LsmboFunctions::stdwarn("Excel sheet name '$sheetName' is not valid: name cannot end with an apostrophe") if($sheetName =~ m/'$/);
  # must not contains []:*?/\
  return LsmboFunctions::stdwarn("Excel sheet name '$sheetName' is not valid: name cannot contain the characters [ ] : * ? \\ /") if($sheetName =~ m/[\[\]\:\*\?\/\\]/g);
  # the name seems ok, it just has to be unique but it's not checked here
  return 1;
}

1;

