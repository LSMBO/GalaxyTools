#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(stderr);

use File::Copy;

my ($outputFile, @inputFiles) = @ARGV;

print "Start MSMerge\n";
my $tempFile = "temp.mgf";

#print Dumper(\@inputFiles);

open(my $out, ">", "$tempFile") or stderr("Can't create file $tempFile: $!");
while(scalar(@inputFiles) > 0) {
    my $file = shift(@inputFiles); # this file is anonymized
    my $filename = shift(@inputFiles); # original file name
    $filename =~ s/.*\///; # remove eventual pathes in file name
    print "Reading file $filename\n";
    open(my $fh, "<", $file) or stderr("Can't open file $filename: $!");
    my $write = 0;
    my $nbSpectra = 0;
    while(<$fh>) {
      s/\r?\n$//;
      $write = 1 if(m/BEGIN IONS/);
      $_ .= ", original_file:$filename" if(m/TITLE=/);
      print $out "$_\n" if($write == 1);
      if(m/END IONS/) {
        $write = 0;
        $nbSpectra++;
        print $out "\n";
      }
    }
    close $fh;
    print "\t$nbSpectra spectra have been copied from file $filename\n";
}
close $out;

print "All files have been correctly merged\n";
move($tempFile, $outputFile);
print "Correct ending of the script\n";

exit;

