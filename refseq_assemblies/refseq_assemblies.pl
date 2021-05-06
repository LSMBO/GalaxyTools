#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/..";
use LsmboFunctions;

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my $refFile = dirname(__FILE__)."/refseq_ref.txt";

# open ref file and extract the ftp link matching the id
my $refSeqLink = "";
open(my $fh, "<", $refFile) or stderr("Failed to open file '$refFile': $!", 1);
while(<$fh>) {
  chomp;
  my ($id, $link) = split(/\t/);
  if($id eq $PARAMS{"taxonomy"}) {
    $refSeqLink = $link;
    last;
  }
}
close $fh;

# check that we do have found the id
stderr("No link found matching this id", 1) if($refSeqLink eq "");

# finalize the link and download the file
# we need to extract the last item of the path, replicate it and add "_protein.faa.gz" to it
# example: 
# ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.39_GRCh38.p13
# becomes
# ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.39_GRCh38.p13/GCF_000001405.39_GRCh38.p13_protein.faa.gz
my @items = split("/", $refSeqLink);
my $file_gz = pop(@items)."_protein.faa.gz";
my $link = "$refSeqLink/$file_gz";
system("wget $link");
stderr("Could not download file $file_gz", 1) if(!-f $file_gz);

# decompress the file
system("gunzip $file_gz");
my $file = $file_gz;
$file =~ s/.gz$//;
stderr("Could not decompress the file $file_gz", 1) if(!-f $file);
stderr("Decompressed file $file is empty", 1) if(-s $file == 0);

# remove duplicates if requested
my %proteins;
my %sequences;
my $accession = "";
my $sequence = "";
my $nbSameSeq = 0;
my $nbSubSeq = 0;
open($fh, $file) or stderr("File '$file' could not be opened: $!", 1);
while (defined(my $line = $fh->getline())) {
  chomp($line);
  if($line =~ m/^>/) {
    copyProtein($accession, $sequence) if($accession ne "");
    $accession = $line;
    $sequence = "";
  } else {
    $sequence .= $line;
  }
}
copyProtein($accession, $sequence) if($accession ne "");
$fh->close();
unlink($file);

removeSubSequences() if($PARAMS{"exclude"} =~ m/subSeq/);

# write output file there
print "Writing proteins in the output file\n";
open($fh, ">", "$outputFile") or stderr("Failed to create file '$outputFile': $!", 1);
my $nbTarget = 0;
foreach my $sequence (keys(%sequences)) {
  my $accession = $sequences{$sequence};
  if($proteins{$accession} == 1) {
    print $fh "$accession\n";
    $sequence =~ s/(.{80})/$1\n/g;
    print $fh "$sequence\n";
    $nbTarget++;
  }
}
close $fh;

print "$nbTarget proteins in the final fasta file\n";
print "$nbSameSeq proteins removed because their sequence equal to the sequence of another protein\n" if($PARAMS{"exclude"} =~ m/sameSeq/);
print "$nbSubSeq proteins removed because their sequence was contained in the sequence of another protein\n" if($PARAMS{"exclude"} =~ m/subSeq/);
print "Correct ending of the script\n";

exit;

sub copyProtein {
  my ($accession, $sequence) = @_;
  # do not copy the protein if the accession number has already been copied
  if(exists($proteins{$accession})) {
      print STDOUT "Duplicate protein id not copied: ".formatAccession($accession)."\n";
  } else {
    # do not copy the protein if the sequence has already been copied (unless you want to allow these)
    if($PARAMS{"exclude"} =~ m/sameSeq/ && exists($sequences{$sequence})) {
      #print STDOUT formatAccession($accession)." has the same sequence has ".formatAccession($sequences{$sequence})."\n" if(exists($sequences{$sequence}))."\n";
      $nbSameSeq++;
    } else {
      $proteins{$accession} = 1;
      $sequences{$sequence} = $accession;
    }
  }
}

sub formatAccession {
  my ($accession, $addQuotes) = @_;
  $addQuotes = 1 if(scalar(@_) == 1);
  my $ln = 30;
  chomp($accession);
  $accession =~ s/ .*//;
  $accession =~ s/^>//;
  return "$accession" if($addQuotes == 0);
  return "'$accession'";
}

# This algorithm orders the sequences by length and compares each sequence only with longer sequences.
# Comparing longer sequences to shorter ones would reduce the number of comparisons, but comparing more longer sequences would take more time.
# Tests have been made on 40492 protein sequences, this version takes about 32 minutes when the alternative takes more than 35.
sub removeSubSequences {
  my $nb = 0;
  # order sequences by length (smallest sequences first)
  my @sortedSequences = sort { length $a <=> length $b } keys(%sequences);
  my $total = scalar(@sortedSequences);
  # only compare sequences to larger sequences
  print "Searching for sub sequences\n";
  my $i = 0;
  foreach my $shorterSequence (@sortedSequences) {
    for(my $j = $i+1; $j < $total; $j++) {
      my $longerSequence = $sortedSequences[$j];
      # search if the shorter sequence is included in the longer sequence (-1 if it's not)
      #if(index($longerSequence, $shorterSequence) != -1) {
      if($longerSequence =~ m/$shorterSequence/) {
        # it is a subsequence, search for its accession number and set its value to 0
        my $accession = $sequences{$shorterSequence};
        $proteins{$accession} = 0;
        print STDOUT formatAccession($accession)." is a sub-sequence of ".formatAccession($sequences{$longerSequence})."\n";
        $nb++;
        last; # no need to compare this sequence to others
      }
    }
    $i++;
  }
  print "$nb sub sequences have been found in the $total protein sequences\n";
  $nbSubSeq = $nb;
}


