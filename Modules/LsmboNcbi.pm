#!/usr/bin/perl
package LsmboNcbi;

use strict;
use warnings;

use LsmboFunctions;
use LWP::Simple;
use LWP::UserAgent;

# only export these methods so they can be used without specifying the namespace
use Exporter qw(import);
our @EXPORT = qw(entrezFetch getNcbiRelease);


sub entrezSearchAndFetch {
  my ($db, $query, $format, $mode, $outputFile) = @_;

  print "Entrez Search&Fetch on database $db\n";
  # prepare the variables
  my $SLEEPTIME = 1;
  my $start = 0;
  my $total = 0;
  my $max = 5000;
  my $base = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils';
  my $search = "$base/esearch.fcgi";
  my $fetch = "$base/efetch.fcgi";

  # prepare HTTP request
  my $ua = new LWP::UserAgent;
  $ua->agent("elink/1.0 ".$ua->agent);

  # open output file
  open(my $fh, ">", $outputFile) or LsmboFunctions::stderr("Failed to create Entrez output file '$outputFile': $!");

  # loop until done
  while($start < $total || $total == 0) {
    print "> Entrez Search $start/$total\n";
    my $search = "$search?db=$db&term=$query&usehistory=y&retstart=$start&retmax=$max";
    my $output = get($search);

    # get total count if it's the first loop
    $total = $1 if($total == 0 && $output =~ /<Count>(\S+)<\/Count>/);

    #parse IDs retrieved
    my $ids = "";
    while ($output =~ /<Id>(\d+?)<\/Id>/sg) {
      $ids .= "&id=$1";
    }

    # fetch the data
    my $params = "db=$db";
    $params .= "&rettype=$format" if($format ne "");
    $params .= "&retmode=$mode" if($mode ne "");
    $params .= "&id=$ids";
    my $req = new HTTP::Request POST => "$fetch";
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("$params");
    my $response = $ua->request($req);
    print $fh $response->content;

    # prepare next loop
    $start += $max;
    sleep($SLEEPTIME);
  }
}

sub entrezFetch {
  my ($db, $format, $mode, $outputFile, @ids) = @_;

  print "Entrez Search on database $db\n";
  # prepare data
  my $SLEEPTIME = 1;
  my $max = 5000;
  my $total = scalar(@ids);
  my $url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi";

  # prepare HTTP request
  my $ua = new LWP::UserAgent;
  $ua->agent("elink/1.0 ".$ua->agent);

  # open output file
  open(my $fh, ">", $outputFile) or LsmboFunctions::stderr("Failed to create Entrez output file '$outputFile': $!");

  # search in batches of 5000 max
  for(my $start = 0; $start < $total; $start += $max) {
    my $stop = $start + $max;
    $stop = $total - 1 if($stop >= $total);
    my @currentIds = @ids[$start .. $stop];
    print "> Entrez Fetch $start/$total\n";
    my $params = "db=$db&restart=$start&retmax=$max";
    $params .= "&rettype=$format" if($format ne "");
    $params .= "&retmode=$mode" if($mode ne "");
    $params .= "&id=".join("&id=", @currentIds);

    #create HTTP request object
    my $req = new HTTP::Request POST => "$url";
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("$params");

    #post the HTTP request
    my $response = $ua->request($req);
    print $fh $response->content;
    sleep($SLEEPTIME);
  }
}

# return NCBI release;
sub getNcbiRelease {
  my ($db) = @_;
  my $output = get("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/einfo.fcgi?db=$db");
  my $build = $1 if ($output =~ /<DbBuild>(\S+)<\/DbBuild>/);
  return $build;
}

1;

