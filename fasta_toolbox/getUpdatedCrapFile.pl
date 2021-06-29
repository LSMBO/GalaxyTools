#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use File::Copy;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(getDate getSetting stderr);
use LsmboRest qw(REST_GET REST_POST_Uniprot_fasta);
use Mail::Sendmail;

my $crapFile = "cRAP.fasta";
my $crapIds = "crap.ids";
my $macroFile = "macroCrap.xml";

my $LOG = "";

eval {
  _log("Downloading cRAP current fasta file");
  _log("Date is: ".getDate("%d %B %Y %H:%M:%S (%Z)"));

  chdir(dirname(__FILE__));
  my $data = REST_GET("ftp://ftp.thegpm.org/fasta/cRAP/crap.fasta");
  # parse data to list all the protein ids
  my @rows = split("\n", $data);
  my $nbIds = 0;
  open(my $fh, ">", $crapIds) or stderr("Can't create file '$crapIds': $!");
  foreach my $row (@rows) {
    if($row =~ m/^>(.*)/) {
      my $id = $1;
      # clean the id if necessary (sp|P12345| must becore P12345)
      $id =~s/sp//;
      $id =~s/\|//g;
      # add the id to the file
      print $fh "$id\n";
      $nbIds++;
    }
  }
  _log(scalar($nbIds)." cRAP identifiers have been retrieved");
  close $fh;

  # download the updated sequences in fasta format
  _log("Downloading the sequences of the cRAP identifiers from Uniprot");
  my $release = REST_POST_Uniprot_fasta($crapIds, "ACC+ID", "$crapFile.tmp");
  unlink($crapIds);

  # adding CON tags to the identifiers
  open(my $out, ">", "$crapFile.con") or stderr("Can't create file '$crapFile.con': $!");
  open($fh, "<", "$crapFile.tmp") or stderr("Can't open file '$crapFile.tmp': $!");
  my $nbContaminants = 0;
  while(<$fh>) {
    if(m/^>(.*)/) {
      print $out ">CON_".$1;
      $nbContaminants++;
    } else {
      print $out $_;
    }
  }
  close $fh;
  close $out;
  unlink("$crapFile.tmp");

  _log("$nbContaminants are in the new cRAP file");
  stderr("No contaminants written in the end file") if($nbContaminants == 0);

  # write a macro xml file to add proper information on the galaxy xml file (date of the update, number of proteins)
  open($out, ">", "$macroFile.tmp") or stderr("Can't create file '$macroFile.tmp': $!");
  print $out "<macros>\n";
  print $out "    <xml name='crap'>\n";
  print $out "        <param name='contaminants' type='boolean' checked='yes' label='Include contaminant proteins' help='$nbContaminants contaminant proteins, updated on ".getDate("%B %d %Y")."' />\n";
  print $out "    </xml>\n";
  print $out "</macros>\n";
  close $out;
};

# if something went wrong
if($@ || !-f "$crapFile.con") {
  # send an email to warn that the update was impossible
  my $instance = getSetting("instance_name");
  my $email = getSetting("admin_email");
  my $message = "$LOG\n$@";
  my %mail = (To => $email, From => $email, Subject => "[$instance] Fasta Toolbox cRAP update failure", Message => $message);
  sendmail(%mail) or stderr($Mail::Sendmail::error);
  # keep using the previous file
} else {
  # otherwise, replace the file but keep the previous one
  copy($crapFile, "$crapFile.sav") if(-f $crapFile);
  move("$crapFile.con", $crapFile);
  # same for the macro file
  copy($macroFile, "$macroFile.sav");
  move("$macroFile.tmp", $macroFile);
}

exit;

sub _log {
  foreach my $log (@_) {
    print "$log\n";
    $LOG .= "$log\n";
  }
}
