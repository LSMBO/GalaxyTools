#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(getDate parameters booleanToString stderr archive);
use LsmboMPI;
use LsmboRest qw(REST_GET_Uniprot);

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Archive::Zip::MemberRead;
use Number::Bytes::Human qw(format_bytes);

my ($paramFile, $outputFile, @mergingData) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
# make sure the boolean value are in textarea
$PARAMS{"decoy"} = booleanToString($PARAMS{"decoy"}) if exists($PARAMS{"decoy"});
$PARAMS{"options"}{"contaminants"} = booleanToString($PARAMS{"options"}{"contaminants"}) if exists($PARAMS{"options"}{"contaminants"});
# prepare a hash to store the match between the files to merge and their name
my %MERGE;

# define the name of the fasta file, based on user parameters
my $fastaFile = $PARAMS{"name"}."_";
$fastaFile .= "D" if($PARAMS{"decoy"} eq "true");
$fastaFile .= "C" if($PARAMS{"options"}{"contaminants"} eq "true");
if($PARAMS{"toolbox"}{"action"} eq "generate" || $PARAMS{"toolbox"}{"action"} eq "proteome") {
  $fastaFile .= "p".uc($PARAMS{"toolbox"}{"source"});
} else {
  $fastaFile .= "p";
}
$fastaFile .= "_".uc($PARAMS{"initials"}) if($PARAMS{"initials"} ne ""); # initials may be empty
$fastaFile .= "_".getDate("%Y%m%d").".fasta";

my @fastaFiles = ();

# add contaminants first (so if there are duplicate sequences, we would keep the proteins tagged as contaminant)
push(@fastaFiles, dirname(__FILE__)."/cRAP.fasta") if($PARAMS{"options"}{"contaminants"} eq "true");

# retrieve sequences from uniprot
my $uniprotFasta = "";
my $uniprotVersion = "";
if($PARAMS{"toolbox"}{"action"} eq "generate" || $PARAMS{"toolbox"}{"action"} eq "proteome") {
  my $taxonomyIds = $PARAMS{"toolbox"}{"taxo"};
  $taxonomyIds =~ s/ //g;
  # ($uniprotFasta, $uniprotVersion) = getFastaFromUniprot(split(",", $taxonomyIds));
  ($uniprotFasta, $uniprotVersion) = getFastaFromUniprotNew(split(",", $taxonomyIds));
  push(@fastaFiles, $uniprotFasta);
} elsif($PARAMS{"toolbox"}{"action"} eq "merge") {
  # add the other files to merge (Galaxy renames the files so they loose their .fasta extension)
  foreach my $fasta (@{$PARAMS{"toolbox"}{"input_fastas"}}) {
    push(@fastaFiles, $fasta);
  }
  # also use the information from ARGV (anonymized file path -> original file name)
  while(scalar(@mergingData) > 0) {
    my $file = shift(@mergingData); # this file is anonymized
    my $filename = shift(@mergingData); # original file name
    $filename =~ s/.*\///; # remove eventual pathes in file name
    $MERGE{$file} = $filename;
  }
}

die("Nothing to put in the fasta file !") if(scalar(@fastaFiles) == 0);

# merge all files and remove duplicate sequences if requested
my %proteins;
my %sequences;
my $nbTargetProteins = 0;
my @removedProteinsBecauseSameId;
my @removedProteinsBecauseSameSequence;
my @removedProteinsBecauseSubSequence;
foreach my $fasta (@fastaFiles) {
  next unless(-f $fasta);
  if(exists($MERGE{$fasta})) {
    print "Adding proteins from $fasta (real file name: ".$MERGE{$fasta}.")\n";
  } else {
    print "Adding proteins from $fasta\n";
  }
  my $accession = "";
  my $sequence = "";
  my $fh;
  if(-B $fasta) {
    # files may be zipped
    my $zip = Archive::Zip->new($fasta);
    $fh = Archive::Zip::MemberRead->new($zip, getFastaFileName($fasta));
  } else {
    open($fh, "<", $fasta) or stderr("File $fasta could not be opened: $!");
  }
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
}
# remove duplicates substring proteins
removeSubSequences() if($PARAMS{"options"}{"exclude"} =~ m/subSeq/);

# write output file there
print "Writing target proteins in the output file\n";
open(my $fh, ">", $fastaFile) or stderr("Failed to create the fasta file: $!");
my $nbTarget = 0;
my $nbConta = 0;
foreach my $accession (sort(keys(%proteins))) {
  my $sequence = $proteins{$accession};
  if($sequence ne "") {
    print $fh "$accession\n";
    $sequence =~ s/(.{80})/$1\n/g;
    print $fh "$sequence\n";
    $nbTarget++;
    $nbConta++ if($accession =~ m/^>CON_/);
  }
}

# generate decoy entries if requested
my $nbDecoy = 0;
if($PARAMS{"decoy"} eq "true") {
  print "Generating decoy entries\n";
  foreach my $accession (sort(keys(%proteins))) {
    my $sequence = $proteins{$accession};
    if($sequence ne "") {
      # add the decoy tag to the accession
      $accession =~ s/^>([^\s]*)(.*)/>###REV###$1 Reverse sequence, was$2/;
      print $fh "$accession\n";
      # reverse the sequence
      chomp($sequence); # otherwise the final \n will be the first character
      $sequence = reverse($sequence);
      $sequence =~ s/(.{80})/$1\n/g;
      print $fh "$sequence\n";
      $nbDecoy++;
    }
  }
}
close $fh;

unlink($uniprotFasta) if(-f $uniprotFasta);

# create the metadata file at the end
my $metadataFile = createMetadataFile($fastaFile, $uniprotVersion, $nbConta, $nbTarget, $nbDecoy, \@removedProteinsBecauseSameId, \@removedProteinsBecauseSameSequence, \@removedProteinsBecauseSubSequence);

# compress the files and return a zip file
print "Compression of the fasta file\n";
archive($outputFile, $fastaFile, $metadataFile);
unlink($fastaFile, $metadataFile);

print "Correct ending of the script\n";

exit;

# sub getFastaFromUniprot {
    # my (@taxonomyIds) = @_;
    
    # # The following request returns a fasta file with all the proteins from taxonomy 9606 and 7215 (including sub taxonomies) in swissprot, but only the proteins in a reference proteome, and with the isoforms
    # # https://www.uniprot.org/uniprot/?query=*&include=yes&fil=proteome:*+AND+reviewed:yes+AND+(taxonomy:9606+OR+taxonomy:7215)&format=fasta
    # # reviewed:yes means SwissProt only ; reviewed:no means TrEMBL only ; do not use Reviewed to have both !
    # # include=yes means that we want to include the isoforms of the proteins, which increases the size of the fasta file
    # # proteome:* means that we only want the proteins present in a reference proteome
    # print "Searching proteins matching the requested taxonomies\n";
    # my $options = "";
    # $options .= addOption($options, "proteomes:*") if($PARAMS{"toolbox"}{"genopts"} =~ m/proteome/);
    # $options .= addOption($options, "reviewed:yes") if(lc($PARAMS{"toolbox"}{"source"}) eq "sp");
    # $options .= addOption($options, "reviewed:no") if(lc($PARAMS{"toolbox"}{"source"}) eq "tr");
    # my $taxonomies = "";
    # foreach my $id (@taxonomyIds) {
        # $taxonomies .= "+OR+" if($taxonomies ne "");
        # $taxonomies .= "taxonomy:$id";
    # }
    # $options .= addOption($options, "($taxonomies)");
    # my $url = "https://www.uniprot.org/uniprot/?query=*";
    # $url .= "&include=yes" if($PARAMS{"toolbox"}{"genopts"} =~ m/isoforms/);
    # $url .= "&fil=$options&format=fasta";
    
    # my ($message, $version) = REST_GET_Uniprot($url);
    # my $tempFastaFile = "uniprot-request.fasta";
    # open(my $fh, ">", $tempFastaFile) or stderr("Failed to create output file: $!");
    # print $fh  $message;
    # close $fh;
    # return ($tempFastaFile, $version);
# }

sub getFastaFromUniprotNew {
  my (@ids) = @_;
  
  # The following request returns a fasta file with all the proteins from taxonomy 9606 and 7215 (including sub taxonomies) in swissprot and with the isoforms https://rest.uniprot.org/uniprotkb/search?format=fasta&includeIsoform=true&query=(taxonomy_id:9606+OR+taxonomy_id:7215)+AND+(reviewed:true)
  # reviewed:yes means SwissProt only ; reviewed:no means TrEMBL only ; do not use Reviewed to have both !
  # include=yes means that we want to include the isoforms of the proteins, which increases the size of the fasta file
  # the filter for proteins belonging to any of the reference proteomes is no longer available
  
  print "Searching proteins matching the requested taxonomies\n";
  my $isoforms = $PARAMS{"toolbox"}{"genopts"} =~ m/isoforms/ ? "&includeIsoform=true" : "";
  my $idTag = $PARAMS{"toolbox"}{"action"} eq "proteome" ? "proteome" : "taxonomy_id";
  my $ids = join(" OR ", map { "$idTag:$_" } @ids);
  my $reviewed = "";
  $reviewed = "reviewed:true" if(lc($PARAMS{"toolbox"}{"source"}) eq "sp");
  $reviewed = "reviewed:false" if(lc($PARAMS{"toolbox"}{"source"}) eq "tr");
  my $options = $reviewed ne "" ? " AND ($reviewed)" : "";
  my $url = "https://rest.uniprot.org/uniprotkb/stream?format=fasta$isoforms&query=($ids)$options";

  my ($message, $version) = REST_GET_Uniprot($url);
  my $tempFastaFile = "uniprot-request.fasta";
  open(my $fh, ">", $tempFastaFile) or stderr("Failed to create output file: $!");
  print $fh  $message;
  close $fh;
  return ($tempFastaFile, $version);
}

sub addOption {
  my ($options, $newOption) = @_;
  return ($options ne "" ? "+AND+".$newOption : $newOption);
}

sub copyProtein {
  my ($accession, $sequence) = @_;
  # do not copy the protein if it's a decoy
  if($accession =~ m/^>###REV###/ || $accession =~ m/REVERSE/) {
  # do not copy the protein if the accession number has already been copied
  } elsif(exists($proteins{$accession})) {
    print STDOUT "Duplicate protein id not copied: ".formatAccession($accession)."\n";
    push(@removedProteinsBecauseSameId, formatAccession($accession, 0));
  } else {
    # do not copy the protein if the sequence has already been copied (unless you want to allow these)
    if($PARAMS{"options"}{"exclude"} =~ m/sameSeq/ && exists($sequences{$sequence})) {
      print STDOUT formatAccession($accession)." has the same sequence has ".formatAccession($sequences{$sequence})."\n" if(exists($sequences{$sequence}))."\n";
      push(@removedProteinsBecauseSameSequence, formatAccession($accession, 0));
    } else {
      $proteins{$accession} = $sequence;
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
    $proteins{$accession} = "";
    print STDOUT formatAccession($accession)." is a sub-sequence\n";
    push(@removedProteinsBecauseSubSequence, formatAccession($accession, 0));
  }
}

sub getFastaFileName {
  my ($zipFile) = @_;
  my $zip = Archive::Zip->new();
  stderr("read error") unless ( $zip->read($zipFile) == AZ_OK );
  foreach my $item($zip->members()) {
    my $file = $item->{"fileName"};
    return $file if($file =~ m/\.fasta$/);
  }
}

sub createMetadataFile {
  my ($fastaFile, $uniprotVersion, $nbConta, $nbTarget, $nbDecoy, $ptrSameId, $ptrSameSeq, $ptrSubSeq) = @_;
  
  # open the metadata file and write the date and parameters
  my $metadataFile = $fastaFile;
  $metadataFile =~ s/\.fasta$/_metadata.txt/;
  my $n = "\r\n";
  
  open(my $fh, ">", $metadataFile) or stderr("Can't create the metadata file: $!");
  print $fh "Date of generation: ".getDate("%d %B %Y %H:%M:%S (%Z)")."$n";
  print $fh "Uniprot release: $uniprotVersion$n";
  print $fh "$n";
  print $fh "Parameters:$n";
  print $fh "- Fasta file: $fastaFile$n";
  if($PARAMS{"toolbox"}{"action"} eq "generate" || $PARAMS{"toolbox"}{"action"} eq "proteome") {
    if($PARAMS{"toolbox"}{"action"} eq "generate") {
      print $fh "- Taxonomies added: ".$PARAMS{"toolbox"}{"taxo"}."$n";
    } else {
      print $fh "- Reference proteomes added: ".$PARAMS{"toolbox"}{"taxo"}."$n";
    }
    if($PARAMS{"toolbox"}{"source"} eq 'SP') {
      print $fh "- Source: UniProt Swiss-Prot$n";
    } elsif($PARAMS{"toolbox"}{"source"} eq 'TR') {
      print $fh "- Source: UniProt TrEMBL$n";
    } else {
      print $fh "- Source: UniProt Swiss-Prot and TrEMBL$n";
    }
    # print $fh "- Restrict to reference proteomes: ".($PARAMS{"toolbox"}{"genopts"} =~ m/proteome/ ? "true" : "false")."$n";
    print $fh "- Include protein isoforms: ".($PARAMS{"toolbox"}{"genopts"} =~ m/isoforms/ ? "true" : "false")."$n";
  } elsif($PARAMS{"toolbox"}{"action"} eq "merge") {
    print $fh "- Merge the following fasta files:$n";
    foreach my $fasta (sort(values(%MERGE))) {
      print $fh "    $fasta$n";
    }
  }
  print $fh "- Contaminants: ".$PARAMS{"options"}{"contaminants"}."$n";
  print $fh "- Remove duplicate proteins with same sequences: ".($PARAMS{"options"}{"exclude"} =~ m/sameSeq/ ? "true" : "false")."$n";
  print $fh "- Remove duplicate proteins included in other proteins: ".($PARAMS{"options"}{"exclude"} =~ m/subSeq/ ? "true" : "false")."$n";
  print $fh "- Generate decoy proteins: ".$PARAMS{"decoy"}."$n";
  
  print $fh "$n";
  print $fh "Output file:$n";
  print $fh "- File size: ".format_bytes(-s $fastaFile)." (".(-s $fastaFile)." bytes)$n";
  print $fh "- Number of contaminant proteins (identified by the tag 'CON_'): $nbConta$n";
  print $fh "- Number of target proteins: $nbTarget$n";
  print $fh "- Number of decoy proteins (identified by the tag '###REV###_'): $nbDecoy$n";
  print $fh "- Total number of proteins: ".($nbTarget+$nbDecoy)."$n";
  
  print $fh "$n";
  print $fh "Duplicate proteins removed (before generating the decoy entries):$n";
  my @sameId = @{$ptrSameId};
  print $fh "- Same identifier: ".scalar(@sameId)."$n";
  print $fh "\t".join("$n\t", @sameId)."$n" if(scalar(@sameId) > 0);
  if($PARAMS{"options"}{"exclude"} =~ m/sameSeq/) {
    my @sameSeq = @{$ptrSameSeq};
    print $fh "- Same sequence: ".scalar(@sameSeq)."$n";
    print $fh "\t".join("$n\t", @sameSeq)."$n" if(scalar(@sameSeq) > 0);
  }
  if($PARAMS{"options"}{"exclude"} =~ m/subSeq/) {
    my @subSeq = @{$ptrSubSeq};
    print $fh "- Sequence contained in another protein: ".scalar(@subSeq)."$n";
    print $fh "\t".join("$n\t", @subSeq)."$n" if(scalar(@subSeq) > 0);
  }
  
  # Close the metadata file
  close $fh;

  return $metadataFile;
}

