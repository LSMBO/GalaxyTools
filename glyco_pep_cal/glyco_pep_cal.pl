#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(parameters stderr);
use LsmboExcel qw(setColumnsWidth writeExcelLine writeExcelLineF);

my %MW = ("A" => 71.0788,  "D" => 115.0886, "F" => 147.1766, "H" => 137.1412, "K" => 128.1742, "M" => 131.1986, "P" => 97.1167,  "R" => 156.1876, "T" => 101.1051, "W" => 186.2133, 
               "C" => 103.1448, "E" => 129.1155, "G" => 57.0520,  "I" => 113.1595, "L" => 113.1595, "N" => 114.1039, "Q" => 128.1308, "S" => 87.0782,  "V" => 99.1326,  "Y" => 163.1760);
my %MW_MONO = ("A" => 71.0371,  "D" => 115.0269, "F" => 147.0684, "H" => 137.0589, "K" => 128.0949, "M" => 131.0404, "P" => 97.0527,  "R" => 156.1011, "T" => 101.0476, "W" => 186.0793, 
          "C" => 103.0091, "E" => 129.0425, "G" => 57.0214,  "I" => 113.0840, "L" => 113.0840, "N" => 114.0429, "Q" => 128.0585, "S" => 87.0320,  "V" => 99.0684,  "Y" => 163.0633);
my %SUGARS = ("F" => 146.1414, "G" => 203.1928, "M" => 162.1409, "S" => 291.2550);
my %SUGARS_MONO = ("F" => 146.0579, "G" => 203.0794, "M" => 162.0528, "S" => 291.0954);
my %SUGAR_NAMES = ("F" => "Fucose", "G" => "GlcNac" , "M" => "Mannose/Galactose" , "S" => "Sialic acid");
my %SUGAR_NOM = ("F" => "Fuc", "G" => "HexNAc" , "M" => "Hex" , "S" => "NeuAc");

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my $PREFER_MONO = ($PARAMS{"mono"} eq "1" ? 1 : 0);

findCombinations($PARAMS{"sequence"}, $PARAMS{"mass"}, $PARAMS{"nb"}, $outputFile);

print "Correct ending of the script\n";

exit;

sub findCombinations {
  my ($peptide, $measuredMass, $nbBestResults, $outputFile) = @_;
  
  # determine the peptide mass
  my $theoreticalMass = computeMass($peptide);
  # search for the combinations that fit the most
  my @combinations = computeBestCombinations($theoreticalMass, $measuredMass, $nbBestResults);
  if(scalar(@combinations) == 0) {
    print "Nothing has been found for peptide '$peptide'\n";
  } else {
    # create the excel file and write the header line
    my $workbook = Excel::Writer::XLSX->new($outputFile);
    my $worksheet = $workbook->add_worksheet($peptide);
    my $format = $workbook->add_format();
    $format->set_format_properties(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
    my $line = 0;
    writeExcelLineF($worksheet, $line++, $format, "Peptide", "Theoretical mass", "Measured mass", "Composition", $SUGAR_NAMES{"F"}, $SUGAR_NAMES{"G"}, $SUGAR_NAMES{"M"}, $SUGAR_NAMES{"S"}, "Composition mass", "Calculated mass", "Delta mass", "Error (ppm)");
    # loop the combinations and write them
    my $bestCombination = "";
    my $bestError = 0;
    foreach my $combination (@combinations) {
      my %combi = %{parseCombination($combination)};
      my ($full, $name) = combinationToString($combination, ",");
      my $mass = combinationToMass($combination);
      my $calculatedMass = $theoreticalMass + $mass;
      my $error = computeErrorPpm($calculatedMass, $measuredMass);
      writeExcelLine($worksheet, $line++, $peptide, $theoreticalMass, $measuredMass, $name, $combi{"F"}, $combi{"G"}, $combi{"M"}, $combi{"S"}, $mass, $calculatedMass, abs($measuredMass - $calculatedMass), $error);
      if($bestCombination eq "") {
        $bestCombination = $combination;
        $bestError = $error;
      }
    }
    # add autofilters
    $worksheet->autofilter(0, 0, $line -1, 11);
    # set column widths
    setColumnsWidth($worksheet, 25, 18, 17, 30, 10, 10, 21, 12, 19, 17, 13, 13);
    $workbook->close();
    # this will go to the standard output (to provide the main result even without downloading the output file)
    my ($full, $name) = combinationToString($bestCombination, "\n- ");
    print "\nThe best combination for '$peptide' is $name\n- $full\n-> Error is ".sprintf("%.2f", $bestError)."ppm\n\n";
  }
}

sub computeMass {
  my $sequence = uc($_[0]);
  my $mass = 1.00797 + 17.00738; # add H at N-terminus and OH at C-terminus
  foreach my $aa (split(//, $sequence)) {
    if(exists($MW{$aa})) {
      $mass += ($PREFER_MONO eq 0 ? $MW{$aa} : $MW_MONO{$aa});
    } else {
      stderr("Error: The amino acid '$aa' in the sequence '$sequence' is not recognized");
    }
  }
  return $mass;
}

sub computeBestCombinations {
  my ($theoreticalMass, $measuredMass, $nbBestResults) = @_;
  # call the recursive function to generate all combinations until the desired mass is achieved
  my %results;
  recursive("F0-G0-M0-S0", $theoreticalMass, $measuredMass, \%results);
  
  # now we must keep the N best combinations, those who are the closest to the desired mass (either under or above the desired mass)
  my @bestCombinations;
  foreach my $key (sort { abs($measuredMass - $theoreticalMass - combinationToMass($a)) <=> abs($measuredMass - $theoreticalMass - combinationToMass($b)) } keys %results) {
    # check if constraints are respected
    my %details = %{parseCombination($key)};
    next if($details{"F"} > 1); # at most 1 Fucose
    next if($details{"G"} < 2); # at least 2 GlcNac
    next if($details{"M"} < 3); # at least 3 Manose
    next if($details{"S"} > 4); # at most 4 Sialic acid
    # if ok then add it to the array
    push(@bestCombinations, $key);
    # stop once the maximum number of results is achieved
    last if(scalar(@bestCombinations) == $nbBestResults);
  }
  return @bestCombinations;
}

sub recursive {
  my ($currentCombination, $currentMass, $measuredMass, $results) = @_;
  # only proceed if the mass if the mass is less than the desired mass (if it's over it, then we have one value that is above and all others would not be better)
  if($currentMass <= $measuredMass) {
    # store this mass and call the recursive function with each mod
    my @keys = keys(%SUGARS);
    for(my $i = 0; $i < scalar(@keys); $i++) {
      my $mass = $currentMass + ($PREFER_MONO eq 0 ? $SUGARS{$keys[$i]} : $SUGARS_MONO{$keys[$i]});
      my $key = generateId($currentCombination, $keys[$i]);
      $results->{$key} = $mass;
      recursive($key, $mass, $measuredMass, $results);
    }
  }
}

sub generateId {
  my ($id, $key) = @_;
  my @newId;
  foreach my $item (split("-", $id)) {
    $item =~ m/([FGMS])(\d+)/;
    my $value = $2;
    $value ++ if($1 eq $key);
    push(@newId, "$1$value");
  }
  return join("-", @newId);
}

sub parseCombination {
  my ($combination) = @_;
  my %results;
  foreach (split("-", $combination)) {
    m/([FGMS])(\d+)/;
    $results{$1} = $2;
  }
  return \%results;
}

sub combinationToMass {
  my ($combination) = @_;
  my %results = %{parseCombination($combination)};
  my $calculatedMass = 0;
  foreach my $key (keys(%results)) {
    $calculatedMass += ($PREFER_MONO eq 0 ? $SUGARS{$key} : $SUGARS_MONO{$key}) * $results{$key};
  }
  return $calculatedMass;
}

sub computeErrorPpm {
  my ($calculatedMass, $measuredMass) = @_;
  return (abs($calculatedMass - $measuredMass) / $measuredMass) * 1000000;
}

sub combinationToString {
  my ($combination, $sep) = @_;
  $sep = ", " if(!$sep);
  my %results = %{parseCombination($combination)};
  my @text;
  foreach my $key (sort(keys(%results))) {
    push(@text, $results{$key}." ".$SUGAR_NAMES{$key});
  }
  # second version, more fit for publication
  my $name = $SUGAR_NOM{"G"}."(".$results{"G"}.")".$SUGAR_NOM{"M"}."(".$results{"M"}.")".$SUGAR_NOM{"F"}."(".$results{"F"}.")".$SUGAR_NOM{"S"}."(".$results{"S"}.")";
  return (join($sep, @text), $name);
}

