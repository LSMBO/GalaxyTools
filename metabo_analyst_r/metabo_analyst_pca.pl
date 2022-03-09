#!/usr/bin/perl
use strict;
use warnings;

use File::Copy;
use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(archive booleanToString checkUniprotFrom decompressZip extractListEntries getFileNameFromArchive getLinesPerIds parameters stderr);
use LsmboExcel qw(extractIds getValue writeExcelLine writeExcelLineF);
use Spreadsheet::ParseExcel::Utility 'col2int';
use Text::CSV qw( csv );
use Data::Dumper;

my ($paramFile, $outputFile1, $outputFile2) = @ARGV;

my %PARAMS = %{parameters($paramFile)};
my $imgFormat = $PARAMS{"condFormat"}{"imgFormat"};
my $dpi = $PARAMS{"condFormat"}{"dpi"};

# create the input file
my $inputFile = createInputFile();

# set the library path
my $path = dirname(__FILE__);
my $libraryPath = "$path/libs";
my $pcaPath = "$path/pca.R";

# start R here, we assume there is no need for quotes in the paths
# print "Rscript $pcaPath $libraryPath $inputFile $imgFormat $dpi\n";
# exit;
system("Rscript $pcaPath $libraryPath $inputFile $imgFormat $dpi");
unlink(glob("*.qs"));
unlink(glob("pca_*.csv"));

# the output files are named based on specific tags but the names are not exactly what is provided
# so we have to look into the files in the current directory
# for instance, if the output file name is test.svg, the actual file will be called test.svgdpi75.svg
my $pairSummaryFile = searchFile("PairSummary", $imgFormat);
my $score2DFile = searchFile("2DScore", $imgFormat);

# if we get here, it means that we do have both files
# we can move them to their final destination
move($pairSummaryFile, $outputFile1);
move($score2DFile, $outputFile2);

print("Correct ending of the script\n");

exit;

sub searchFile {
  my ($tag, $format) = @_;
  #print("Searching for a file matching '.*$tag.*$format'...\n");
  my @file = glob("*$tag*$format");
  if(scalar(@file) > 0) {
    #print("Found file '".$file[0]."'\n");
    return $file[0]; # return the first matching file
  } else {
    die("Unable to find a $format file with '$tag' in its name!");
  }
}

sub createInputFile {
  # read the input file and put the data in a hash
  my $ptrData;
  my $samplesTag = "";
  my $inputFile = $PARAMS{"condInput"}{"inputFile"};
  if($PARAMS{"condInput"}{"inputFormat"} eq "maxquant_txt") {
    # this is a text file
    $samplesTag = "^LFQ intensity ";
#    my $inputFile = $PARAMS{"condInput"}{"mqtInputFile"};
    $ptrData = readTextFile($inputFile, "Protein IDs", $samplesTag);
  } else {
    # this is an excel file
    my $sheetNumber = $PARAMS{"condInput"}{"sheetNumber"} - 1;
    my $columnProteinId = 0;
    my $columnsSamplesStart = 1;
    my $columnsSamplesStop = 2;
    if($PARAMS{"condInput"}{"inputFormat"} eq "maxquant_xlsx") {
      $samplesTag = "^LFQ intensity ";
#      my $inputFile = $PARAMS{"condInput"}{"mqxInputFile"};
      $ptrData = readExcelFileWithTags($inputFile, $sheetNumber, "Protein IDs", $samplesTag);
    } elsif($PARAMS{"condInput"}{"inputFormat"} eq "proline") {
      $samplesTag = "^abundance_\\d+_";
      $samplesTag = "^raw_abundance_\\d+_" if(booleanToString($PARAMS{"condInput"}{"preferRawAbundance"}) eq "true");
#      my $inputFile = $PARAMS{"condInput"}{"proInputFile"};
      $ptrData = readExcelFileWithTags($inputFile, $sheetNumber, "accession", $samplesTag);
    } else {
      my $columnProteinId = col2int($PARAMS{"condInput"}{"columnProteinId"});
      my $columnsSamplesStart = col2int($PARAMS{"condInput"}{"columnsSamplesStart"});
      my $columnsSamplesStop = col2int($PARAMS{"condInput"}{"columnsSamplesStop"});
#      my $inputFile = $PARAMS{"condInput"}{"xlsxInputFile"};
      $ptrData = readExcelFile($inputFile, $sheetNumber, $columnProteinId, $columnsSamplesStart, $columnsSamplesStop);
    }
  }
  # finalize the data
  my @rows = @{$ptrData};
  my $namesPtr = shift(@rows);
  my @names = @{$namesPtr};
  $names[0] = "name";
  # TODO remove the $samplesTag directly here ?
  for(my $i = 1; $i < scalar(@names); $i++) {
    $names[$i] = remove_tag($names[$i], $samplesTag);
  }
  my $namesRow = join(";", @names);
  $namesRow =~ s/ /\-/g;
  # my @labels = defineLabels(\@names, $samplesTag);
  my @labels = defineLabels(@names);
  # print Dumper(\@names);
  # print Dumper(\@labels);
  my $labelsRow = join(";", @labels);
  $labelsRow =~ s/ /\-/g;
  # write the file manually
  my $file = "pca.csv";
  open(my $fh, ">", $file) or stderr("Can't create csv file for PCA: $!");
  print $fh "$namesRow\n";
  print $fh "$labelsRow\n";
  foreach my $row (@rows) {
    my @row = @{$row};
    my @cells;
    foreach my $cell (@row) {
      $cell =~ s/;.*//;
      $cell =~ s/ /-/g;
      $cell =~ s/,/\./g;
      push(@cells, $cell);
    }
    print $fh join(";", @cells)."\n";
  }
  close $fh;

  # return the path of the input file
  return $file;
}

sub defineLabels {
  # my ($ptrRow, $samplesTag) = @_;
  my @names = @_;
  
  my @labels = ();
  # my @names = @{$ptrRow};
  if($PARAMS{"condList"}{"condType"} eq "pattern") {
    # use a predefined rule
    # my $fct = \&remove_tag;
    my $fct = \&do_nothing;
    $fct = \&remove_numbers_end if($PARAMS{"condList"}{"pattern"} eq "remove_numbers_end");
    $fct = \&remove_numbers_begin_end if($PARAMS{"condList"}{"pattern"} eq "remove_numbers_begin_end");
    $fct = \&remove_after_space if($PARAMS{"condList"}{"pattern"} eq "remove_after_space");
    foreach my $name (@names) {
      # my $tag = $fct->($name, $samplesTag);
      my $tag = $fct->($name);
      $name =~ m/$tag$/;
      push(@labels, $tag);
    }
  } elsif($PARAMS{"condList"}{"condType"} eq "conditions") {
    # get the conditions provided by the user
    my %conditions;
    foreach my $cond (@{$PARAMS{"condList"}{"conditions"}}) {
      $conditions{$cond->{"condition"}} = 1;
    }
    # search the conditions within the sample names
    foreach my $name (@names) {
      my $label = "Missing_condition";
      foreach my $condition (keys(%conditions)) {
        $label = $condition if($name =~ m/$condition/);
      }
      push(@labels, $label);
    }
  } elsif($PARAMS{"condList"}{"condType"} eq "samples") {
    # get the conditions for each sample, provided by the user
    my %samples;
    foreach my $sample (@{$PARAMS{"condList"}{"samples"}}) {
      $samples{$sample->{"sample"}} = $sample->{"condition"};
    }
    # just get the corresponding condition to that sample (use a default condition if the sample name is missing)
    foreach my $name (@names) {
      my $label = "Missing_condition";
      # $name = remove_tag($name, $samplesTag);
      $label = $samples{$name} if(exists($samples{$name}));
      push(@labels, $label);
    }
  }
  # return ("label", @labels);
  $labels[0] = "label";
  # for(my $i = 1; $i < scalar(@labels); $i++) {
    # my $sample = $names[$i];
    # my $label = $labels[$i];
    # print "Sample '$sample' => Label '$label'\n";
  # }
  return @labels;
}
sub do_nothing {
  return $_[0];
}
sub remove_tag {
  my ($value, $samplesTag) = @_;
  $value =~ s/$samplesTag//;
  return $value;
}
sub remove_numbers_end {
  # my ($value, $samplesTag) = @_;
  my ($value) = @_;
  # $value =~ s/$samplesTag//;
  $value =~ s/\d+$//;
  return $value;
}
sub remove_numbers_begin_end {
  # my ($value, $samplesTag) = @_;
  my ($value) = @_;
  # $value =~ s/$samplesTag//;
  $value =~ s/^\d+//;
  $value =~ s/\d+$//;
  return $value;
}
sub remove_after_space {
  # my ($value, $samplesTag) = @_;
  my ($value) = @_;
  # $value =~ s/$samplesTag//;
  my @items = split(" ", $value);
  return $items[0];
}

sub readTextFile {
  my ($inputFile, $proteinIdTag, $samplesTag) = @_;
  print "Reading text input file\n";
  my $csv = Text::CSV->new ({ 
#    eol => "\r\n", # if not set it accepts \r, \n and \r\n
    binary => 1, 
    auto_diag => 2, 
    diag_verbose => 1, 
    sep_char => "\t", 
    escape_char => "\\", 
    always_quote => 1, 
  });

  open(my $fh, '<', $inputFile) or stderr("Can't open the input file: $!");
  # first step is to get the columns of interest
  my @data;
  my @row;
  my @columns;
  my $headers = $csv->getline($fh);
  for (my $i = 0; $i < scalar(@{$headers}); $i++) {
    my $header = $headers->[$i];
    if($header eq $proteinIdTag || $header =~ m/$samplesTag/) {
      push(@columns, $i);
      push(@row, $header);
    }
  }
  push(@data, \@row);
  
  # read the rest of the file
  while (my $row = $csv->getline ($fh)) {
    my @cells = @{$row};
    my @row;
    foreach my $col (@columns) {
      push(@row, $cells[$col]);
    }
    push(@data, \@row);
  }
  close $fh;
  
  return \@data;
}

sub readExcelFile {
  my ($inputFile, $sheetNumber, $columnProteinId, $columnsSamplesStart, $columnsSamplesStop) = @_;
  print "Reading text input file\n";
  
  # my %data;
  my @data;
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($inputFile);
  stderr($parser->error()) if(!defined $workbook);
  my @worksheets = $workbook->worksheets();
  my $sheet = $worksheets[$sheetNumber];
  my ($row_min, $row_max) = $sheet->row_range();
  for my $row ($row_min .. $row_max) {
    my @row;
    push(@row, getValue($sheet, $row, $columnProteinId));
    for (my $i = $columnsSamplesStart; $i <= $columnsSamplesStop; $i++) {
      push(@row, getValue($sheet, $row, $i));
    }
    push(@data, \@row);
  }
  return \@data;
}

sub readExcelFileWithTags {
  my ($inputFile, $sheetNumber, $proteinIdTag, $samplesTag) = @_;
  print "Reading text input file\n";
  
  my @data;
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($inputFile);
  stderr($parser->error()) if(!defined $workbook);
  my @worksheets = $workbook->worksheets();
  my $sheet = $worksheets[$sheetNumber];
  my ($row_min, $row_max) = $sheet->row_range();
  my ($col_min, $col_max) = $sheet->col_range();
  
  # determine column ids by searching headers
  my $columnProteinId = 0;
  my @samplesColumns;
  for my $col ($col_min .. $col_max) {
    my $header = getValue($sheet, $row_min, $col);
    $columnProteinId = $col if($header eq $proteinIdTag);
    push(@samplesColumns, $col) if($header =~ m/$samplesTag/);
  }
  
  # get the data matching these columns
  for my $row ($row_min .. $row_max) {
    my @row;
    push(@row, getValue($sheet, $row, $columnProteinId));
    foreach my $col (@samplesColumns) {
      push(@row, getValue($sheet, $row, $col));
    }
    push(@data, \@row);
  }
  return \@data;
}

