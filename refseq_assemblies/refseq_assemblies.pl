#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(decompressGunzip parameters stderr);
use LsmboMPI;
use LsmboRest qw(downloadFile);

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my $refFile = dirname(__FILE__)."/refseq_ref.txt";

# open ref file and extract the ftp link matching the id
my $refSeqLink = "";
open(my $fh, "<", $refFile) or stderr("Failed to open file '$refFile': $!");
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
stderr("No link found matching this id") if($refSeqLink eq "");

# finalize the link and download the file
# we need to extract the last item of the path, replicate it and add "_protein.faa.gz" to it
# example: 
# ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.39_GRCh38.p13
# becomes
# ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.39_GRCh38.p13/GCF_000001405.39_GRCh38.p13_protein.faa.gz
my @items = split("/", $refSeqLink);
my $file_gz = pop(@items)."_protein.faa.gz";
my $link = "$refSeqLink/$file_gz";
downloadFile($link);

# decompress the file
my $file = decompressGunzip($file_gz);
unlink($file_gz) if(-f $file_gz);

# remove duplicates if requested
my %proteins;
my %sequences;
my $accession = "";
my $sequence = "";
my $nbSameSeq = 0;
my $nbSubSeq = 0;
open($fh, $file) or stderr("File '$file' could not be opened: $!");
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
open($fh, ">", "$outputFile") or stderr("Failed to create file '$outputFile': $!");
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

sub removeSubSequences {
  my @sequences = keys(%sequences);
  my @subSequences = LsmboMPI::removeSubSequencesMT(\@sequences);
  # remove the sub-sequences from the full list
  foreach(@subSequences) {
    my $accession = $sequences{$_};
    $proteins{$accession} = 0;
    print STDOUT formatAccession($accession)." is a sub-sequence\n";
  }
  $nbSubSeq = scalar(@subSequences);
}
