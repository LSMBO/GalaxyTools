#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use File::Copy;

# write a perl script to launch the docker and deal with paths and volume mount
my ($inputFile, $imgFormat, $dpi, $outputFile1, $outputFile2) = @ARGV;

# set the library path
my $path = dirname(__FILE__);
my $libraryPath = "$path/libs";
my $pcaPath = "$path/pca.R";

# start R here, we assume there is no need for quotes in the paths
system("Rscript $pcaPath $libraryPath $inputFile $imgFormat $dpi");

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
