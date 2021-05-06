#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/..";
use LsmboFunctions;
use Mail::Sendmail;

my $dlFile = "assembly_summary_refseq.txt";
my $tsvFile = "refseq_ref.txt";
my $xmlFile = "refseq_macro.xml";

my $log = "";

eval {
  $log += "Updating RefSeq assemblies\n";
  $log += "Date is: ".getDate("%d %B %Y %H:%M:%S (%Z)")."\n";
  # download file ftp://ftp.ncbi.nlm.nih.gov/genomes/refseq/assembly_summary_refseq.txt
  chdir(dirname(__FILE__));
  my $data = REST_GET("ftp://ftp.ncbi.nlm.nih.gov/genomes/refseq/$dlFile");
  my @rows = split("\n", $data);
  $log += "File assembly_summary_refseq.txt have been downloaded, parsing its ".scalar(@rows)." rows\n";

  # parse the file and store the keys in a hash to avoid duplicates (there should be none but still)
  # also write a tsv file to store the ftp link matching the keys (makes the xml file smaller and faster to load)
  $log += "Creating file refseq_ref.txt\n";
  open(my $fh, ">", "$tsvFile.tmp") or stderr("Can't open file '$tsvFile.tmp': $!", 1);
  my $nb = 0;
  my %names;
  foreach my $row (split("\n", $data)) {
    next if($row =~ m/^#/); # do not read comments
    my @items = split("\t", $row);
    next if(scalar(@items) < 20); # we need the 20th column

    my $id = $items[5];
    my $name = $items[7];
    my $strain = $items[8];
    my $link = $items[19];

    # create the full name
    my $key = $name;
    $key .= " $strain" if($strain ne "");
    $key .= " [#$id]";
    # make sure that there is no forbidden character
    $key =~ s/\&/ and /;
    # store the key
    $names{"$key"} = $nb;
    print $fh "$nb\t$link\n";
    $nb++;
  }
  close $fh;

  # now write the xml file that will be loaded in galaxy
  # we want it as light as possible to make the loading of the page faster
  # but there's a lot of taxonomies and it's xml !
  $log += "Creating file refseq_macro.xml\n";
  open($fh, ">", "$xmlFile.tmp") or stderr("Can't open file '$xmlFile.tmp': $!", 1);

  print $fh "<macros>\n";
  print $fh "    <xml name='refseq_assemblies'>\n";
  print $fh "        <param name=\"taxonomy\" type=\"select\" label=\"Select the genome assembly source for your fasta file\" help=\"It is strongly advised to exclude duplicate sequences when generating fasta files from RefSeq databases\">\n";

  foreach my $name (sort(keys(%names))) {
    my $nb = $names{$name};
    if($name =~ m/^Homo sapiens/) {
      print $fh "            <option value=\"$nb\" selected=\"true\">$name</option>\n";
    } else {
      print $fh "            <option value=\"$nb\">$name</option>\n";
    }
  }

  print $fh "        </param>\n";
  print $fh "    </xml>\n";
  print $fh "</macros>\n";
  close $fh;

  # cleaning and exiting
  unlink($dlFile);
  backup($tsvFile);
  backup($xmlFile);
  $log += "$nb RefSeq assemblies have been successfully managed\n";

};

if($@) {
  my %mail = ( To => 'a.burel@unistra.fr', From => 'iphc-galaxy@unistra.fr', Subject => '[IPHC-Galaxy] RefSeq Assemblies update failure', Message => $@);
  sendmail(%mail) or stderr($Mail::Sendmail::error, 1);
}

exit;

sub backup {
  my ($file) = @_;
  copy($file, "$file.sav");
  move("$file.tmp", $file);
}

