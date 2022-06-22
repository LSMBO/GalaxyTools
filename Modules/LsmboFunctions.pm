#!/usr/bin/perl
package LsmboFunctions;

use strict;
use warnings;

#use Archive::Zip;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Archive::Zip::MemberRead;
# use Data::Dumper;
use File::Basename qw(basename dirname);
use File::Slurp qw(read_file write_file);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use JSON::XS qw(encode_json decode_json);
use List::MoreUtils qw(uniq);
use List::Util qw(shuffle);
# use Number::Bytes::Human qw(format_bytes);
use POSIX qw(strftime);

# only export these methods so they can be used without specifying the namespace
use Exporter qw(import);
our @EXPORT = qw(archive booleanToString checkUniprotFrom decompressGunzip decompressZip extractListEntries extractListEntriesInArray getContactMailAddress getDate getFileNameFromArchive getLinesPerIds getSetting getVersion parameters randomSubset stderr stdwarn);


###################
# GENERIC METHODS #
###################

my $GLOBAL = parameters(dirname(__FILE__)."/../settings.json");

# Dates
sub getDate {
  my ($format) = @_;
  # "%Y%m%d" => 20200127
  # "%m/%d/%Y" => 01/27/2020
  # "%d %B %Y %H:%M:%S (%Z)" => 27 January 2020 08:58:36 (CET)
  return strftime($format, localtime);
}

# usefull when contact for Galaxy is required
sub getContactMailAddress {
  return $GLOBAL->{"admin_email"};
}

sub getSetting {
  return $GLOBAL->{$_[0]};
}

##############
# INPUT DATA #
##############

# Read json parameters file
# Returns a pointer to a hash containing the content of the file
sub parameters {
  eval {
    return \%{decode_json(read_file($_[0], { binmode => ':raw' }))};
  } or stderr("Can't read parameter file: $!");
}

# Json parameters file sometimes uses true/false and sometimes 0/1
# This methods makes sure to have true/false only
sub booleanToString {
  my $value = "false";
  eval { $value = "true" if($_[0] eq "true");
  } or $value = "true" if($_[0] eq 1);
  return $value;
}

# Character '+' is not allowed in Galaxy parameters
sub checkUniprotFrom {
  my ($from) = @_;
  return "ACC,ID" if($from eq "ACC_ID");
  return $from;
}

# Galaxy lists are provided in a single string: spXP28076XPSB9_MOUSE__cn__spXO35522XPSB9_MUSMB__cn__spXQ2TPA8XHSDL2_MOUSE__cn__spXQ3T0K1XCALU_BOVIN__cn__spXQ80X76XSPA3F_MOUSE__cn__
# This method will split the string and write each in the given file
sub extractListEntries {
  my ($list, $file) = @_;
  open(my $fh, ">", $file) or stderr("Can't write to file '$file': $!");
  foreach my $entry (split("__cn__", $list)) {
    print $fh "$entry\n";
  }
}

sub extractListEntriesInArray {
  my ($list) = @_;
  return split("__cn__", $list);
}

# Strips a protein accession number to avoid pipes (pipes are not working with Uniprot REST API)
sub cleanProteinId {
  my ($entry) = @_;
  if(m/^..\|([^\|]+)\|[^ ]*/) {   # sp|P12345|PROTEIN_NAME => P12345
    return $1;
  } elsif(m/^..\|([^ ]+)/) {      # sp|P12345 => P12345
    return $1;
  } else {
    return $entry;
  }
}

# Checks input protein file
# Pipes are not working with Uniprot REST API, so ids are simplified
# Uniprot REST API may fail with requests of more than 5000 entries, so file is splitted
# Returns a list of files with correct ids and each have less than 5000 entries
sub checkUniprotInputFile {
  my ($file) = @_;
  
  my $limit = 2500;
  my $i = 1;
  my $tempFile = "LSMBO_input_proteins_$i.txt";
  my $nbProteins = 0;
  my $totalNbProteins = 0;
  my @files = ($tempFile);
  my $fh;
  open($fh, ">", $tempFile) or stderr("Can't create temporary protein input file: $!");
  open(my $in, "<", $file) or stderr("Can't open protein input file: $!");
  while(<$in>) {
    chomp;
    next if($_ eq "");
    print $fh cleanProteinId($_)."\n";
    $nbProteins++;
    $totalNbProteins++;
    if($nbProteins == $limit) {
      close $fh;
      $i++;
      $tempFile = "LSMBO_input_proteins_$i.txt";
      push(@files, $tempFile);
      open($fh, ">", $tempFile) or stderr("Can't create temporary protein input file: $!");
      $nbProteins = 0;
    }
  }

  # remove last file if it's empty
  pop(@files) if($nbProteins == 0);
  
  print "$totalNbProteins protein identifiers have been provided\n";
  print "Protein input file has been splitted in ".scalar(@files)." files\n" if(scalar(@files) > 1);
  return @files;
}

# Reads a file containing ids
# Returns a hash indicating the line for each id
# Also returns a hash indicating the content for each line
# This is useful to keep the order of the input file and to match the original ids to the simplified ones
# If the parameter allowMultipleIdsPerLine is unset (default behaviour), only the first id per line is kept (useful for xlsx)
# Otherwise, all ids are considered as a single line (it should be used for id lists and text files)
sub getLinesPerIds {
  my ($inputFile, $allowMultipleIdsPerLine) = @_;
  my %fullDataPerLine;
  my %linesPerId;
  my $i = 0;
  open(my $fh, "<", $inputFile) or stderr("Can't read file '$inputFile': $!");
  while(<$fh>) {
    chomp;
    if($allowMultipleIdsPerLine) {
      foreach my $entry (split(/[ ,;\-]/, $_)) {
        $fullDataPerLine{$i} = $entry;
        push(@{$linesPerId{cleanProteinId($entry)}}, $i);
        $i++;
      }
    } else {
      $fullDataPerLine{$i} = $_;
      if($_ ne "") {
        my @entries = split(/[ ,;\-]/, $_);
        push(@{$linesPerId{cleanProteinId($entries[0])}}, $i) if(scalar(@entries) > 0);
      }
      $i++;
    }
  }
  return (\%fullDataPerLine, \%linesPerId);
}

sub randomSubset {
  my ($nbItems, $arrayPtr) = @_;
  my @array = @{$arrayPtr};
  my @shuffled_indexes = shuffle(0..$#array);
  my @pick_indexes = @shuffled_indexes[ 0 .. $nbItems - 1 ];  
  return @array[ @pick_indexes ];
}


###################
# LOGGING METHODS #
###################

sub getVersion {
  my ($package, $filename, $line) = caller;
  $filename =~ s/\.pl$/.xml/;
  my $version = "";
  if(open(my $fh, "<", $filename)) {
    while(<$fh>) {
      chomp;
      if(m/<tool /) {
        my ($n) = m/name\s*=\s*"([^"]*)"/;
        my ($v) = m/version\s*=\s*"([^"]*)"/;
        $version = $n eq "" ? $v : "$n $v";
        last;
      }
    }
    close $fh;
  }
  return $version;
}

# Log messages with trace (set die = 1 to stop the process, default is 0)
# caller: Returns the context of the current pure perl subroutine call
sub stderr {
  # my ($message, $die) = @_;
  my ($message) = @_;
  $message = "Undefined error" if(scalar(@_) == 0);
  $message = "[".getDate("%Y-%m-%d %H:%M:%S")." - Error] ".$message."\n";
  my $i = 0; # value 0 will refer to the current function (stderr), value 1 will refer to its direct caller
  while ( (my @caller = (caller($i++))) ){
    $message .= "\t".$caller[1].":".$caller[2]." in function ".$caller[3]."\n";
  }
  die($message);
  # if($die) {
    # die($message);
  # } else {
    # print STDERR $message;
  # }
}

sub stdwarn {
  my ($message) = @_;
  $message = "[".getDate("%Y-%m-%d %H:%M:%S")." - Warning] ".$message."\n";
  print STDOUT $message;
  return 0;
}


###############
# COMPRESSION #
###############

# Create archive
sub archive {
  my ($zipFile, @files) = @_;
  my $zip = Archive::Zip->new();
  foreach my $file (@files) {
    if(-d $file) {
      $zip->addTree($file, basename($file)); # TODO make sure that the directory is stored at the root of the archive
    } elsif(-f $file) {
      $zip->addFile($file, basename($file));
    } else {
      stdwarn("Item '$file' is not a file or a directory and will not be added to archive '$zipFile'");
    }
  }
  $zip->writeToFileNamed($zipFile);
}

sub decompressGunzip {
  my ($gzipFile) = @_;
  my $file = $gzipFile;
  $file =~ s/.gz$//;
  gunzip $gzipFile => $file or stderr("gunzip failed: $GunzipError");
  return $file;
}

sub decompressZip {
  my ($zipFile, @fileNames) = @_;
  foreach(@fileNames) {
    unzip $zipFile => $_, Name => "$_" or stderr("unzip failed: $UnzipError");
  }
}

sub getFileNameFromArchive {
  my ($zipFile, $desiredExt) = @_;
  my $zip = Archive::Zip->new();
  stderr("read error") unless ( $zip->read($zipFile) == AZ_OK );
  foreach my $item($zip->members()) {
    my $file = $item->{"fileName"};
    return $file if($file =~ m/\.$desiredExt$/);
  }
  return "";
}

1;

