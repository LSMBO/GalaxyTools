#!/usr/bin/perl
package LsmboRest;

use strict;
use warnings;

use File::Fetch;
use JSON::XS qw(encode_json decode_json);
use LsmboFunctions;
use LWP::Simple;
use LWP::UserAgent;

# only export these methods so they can be used without specifying the namespace
use Exporter qw(import);
# our @EXPORT = qw(downloadFile UNIPROT_RELEASE REST_GET REST_GET_Uniprot REST_POST_Uniprot_tab REST_POST_Uniprot_fasta getQuickGOVersion);
our @EXPORT = qw(downloadFile getQuickGOVersion REST_GET REST_GET_Uniprot);



sub downloadFile {
  my $url = shift;
  my $ff = File::Fetch->new(uri => $url);
  my $file = $ff->fetch() or stderr($ff->error);
  return $file;
}

sub UNIPROT_RELEASE { 
  return "UNIPROT RELEASE"; 
}

# REST GET method
sub REST_GET {
  my ($url) = @_;
  my ($response) = REST_GET_generic($url);
  return $response;
}

sub REST_GET_Uniprot {
  return REST_GET_generic($_[0], "X-UniProt-Release");
}

sub REST_GET_generic {
  my ($url, @requestedHeaders) = @_;
  # print "REST GET url: $url\n";
  my $contact = LsmboFunctions::getContactMailAddress();
  my $ua = LWP::UserAgent->new(agent => "libwww-perl $contact");
  my $request = HTTP::Request->new(GET => $url);
  $request->header('content-type' => 'application/json');
  $request->header('x-auth-token' => getRandomString());
  my $response = $ua->request($request);
  
  # return the output
  if ($response->is_success) {
    my @headers;
    foreach my $header (@requestedHeaders) {
      push(@headers, $response->header($header));
    }
    return ($response->decoded_content, @headers);
  } else {
    LsmboFunctions::stderr("HTTP GET error code:".$response->code." with message: ".$response->message."\nDownloaded URL was: $url\n");
  }
}

# sub REST_POST_Uniprot_tab {
  # my ($inputFile, $from, $columns, $taxo) = @_;
  # print "Uniprot REST method for file '$inputFile', requesting tabular format for data of type '$from', requested columns are $columns\n";
  
  # my $NBTRIESTOTAL = 10;
  # # my $uniprotURL = "https://www.uniprot.org/uploadlists/";
  # my $uniprotURL = "https://legacy.uniprot.org/uploadlists/";
  # my $contact = LsmboFunctions::getContactMailAddress();
  # my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");
  # push @{$agent->requests_redirectable}, 'POST';
  # my $params = ['format' => 'tab', 'from' => $from, 'to' => 'ACC', 'columns' => $columns];
  # push(@$params, 'taxon' => $taxo) if(scalar(@_) == 4 && $taxo ne "");
  # my $nbColumns = scalar(split(",", $columns));
  
  # my %output;
  # my @inputFiles = LsmboFunctions::checkUniprotInputFile($inputFile);
  # my $i = 1;
  # foreach my $file (@inputFiles) {
    # # update the parameters
    # my @batchParams = @$params;
    # push(@batchParams, 'file' => [$file]);
    # my $nbTries = 0;
    # my $isSuccess = 0;
    # while($isSuccess == 0) {
      # my ($code, $message, $version) = REST_POST_Uniprot_single($agent, $uniprotURL, \@batchParams);
      # if($code == 400 || $code == 500) {
        # # these error codes do not mean the request was necessarily wrong, let's retry another time
        # $nbTries++;
        # LsmboFunctions::stdwarn("HTTP GET error code:$code with message: $message (attempt $nbTries/$NBTRIESTOTAL)");
        # sleep 2; # wait a bit before trying again
      # } elsif($code > 0) {
        # # any other error code should end the script
        # # example of error: 405 Not Allowed (after an update on Uniprot API)
        # LsmboFunctions::stderr("HTTP GET error code:$code with message: $message");
      # } else {
        # $output{UNIPROT_RELEASE()} = $version;
        # my @data = split(/\n/, $message);
        # # remove header line
        # my $headerLine = shift(@data);
        # # add the lines to the complete output
        # foreach my $line (@data) {
          # my @items = split(/\t/, $line);
          # # remove the isomap column if there is one
          # pop(@items) if(scalar(@items) == $nbColumns + 2);
          # # move the user entry from last to first
          # my $userEntry = pop(@items);
          # unshift(@items, $userEntry);
          # $output{$userEntry} = \@items;
        # }
        # # exit the while loop once the request succeeds
        # last;
      # }
      # stderr("Stopped trying to access Uniprot after $NBTRIESTOTAL attempts") if($nbTries == $NBTRIESTOTAL);
    # }
  # }
  # unlink(@inputFiles);
  # print "Uniprot returned ".scalar(keys(%output))." results\n";
  # return \%output;
# }

# sub REST_POST_Uniprot_fasta {
  # my ($inputFile, $from, $fastaOutput) = @_;
  # print "Uniprot REST method for file '$inputFile', requesting fasta format for data of type '$from'\n";
  
  # my $NBTRIESTOTAL = 5;
  # my $contact = LsmboFunctions::getContactMailAddress();
  # # my $uniprotURL = "https://www.uniprot.org/uploadlists/";
  # my $uniprotURL = "https://legacy.uniprot.org/uploadlists/";
  # my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");
  # push @{$agent->requests_redirectable}, 'POST';
  # my $params = ['format' => 'fasta', 'from' => $from, 'to' => 'ACC'];
  
  # my $uniprotVersion;
  # my @inputFiles = LsmboFunctions::checkUniprotInputFile($inputFile);
  # my $i = 1;
  # foreach my $file (@inputFiles) {
    # # update the parameters
    # my @batchParams = @$params;
    # push(@batchParams, 'file' => [$file]);
    # my $nbTries = 0;
    # my $isSuccess = 0;
    # while($isSuccess == 0) {
      # my ($code, $message, $version) = REST_POST_Uniprot_single($agent, $uniprotURL, \@batchParams);
      # if($code == 0) {
        # $uniprotVersion = $version;
        # open(my $fh, ">>", $fastaOutput) or LsmboFunctions::stderr("Can't write fasta output file to append data: $!");
        # print $fh $message;
        # close $fh;
        # # exit the while loop once the request succeeds
        # last;
      # } elsif($code == 400 || $code == 500) {
        # # these error codes do not mean the request was necessarily wrong, let's retry another time
        # LsmboFunctions::stdwarn("HTTP POST error code:$code with message: $message (attempt $nbTries/$NBTRIESTOTAL)");
        # $nbTries++;
      # } else {
        # # any other error code should end the script (is it really necessary ?)
        # LsmboFunctions::stdwarn("HTTP POST error code:$code with message: $message");
      # }
      # LsmboFunctions::stderr("Stopped trying to access Uniprot after $NBTRIESTOTAL attempts") if($nbTries == $NBTRIESTOTAL);
    # }
  # }
  # unlink(@inputFiles);
  # print "Uniprot request was successful\n";
  # return $uniprotVersion;
# }

# sub REST_POST_Uniprot_single {
  # my ($agent, $uniprotURL, $params) = @_;
  # my $SLEEPTIME = 2;
  # # send to request to uniprot
  # my $response = $agent->post($uniprotURL, $params, 'Content_Type' => 'form-data');
  # while (my $wait = $response->header('Retry-After')) {
    # print STDERR "Waiting ($wait)...\n";
    # sleep $wait;
    # $response = $agent->get($response->base);
  # }
  
  # # prepare output
  # my $code = 0;
  # my $message = "";
  # my $version = "";
  
  # # return the output
  # if ($response->is_success) {
    # $version = $response->header('X-UniProt-Release');
    # $message = $response->decoded_content();
  # } else {
    # $code = $response->code;
    # $message = $response->message;
  # }
  # # wait a bit between two requests
  # sleep($SLEEPTIME);
  # # return exit code and message
  # return ($code, $message, $version);
# }

sub getRandomString {
  my @chars = ("A".."Z", "a".."z");
  my $string = "";
  $string .= $chars[rand @chars] for 1..16;
  return $string;
}

sub getQuickGOVersion {
  my %about = %{decode_json(REST_GET("https://www.ebi.ac.uk/QuickGO/services/ontology/go/about"))};
  return $about{"go"}{"timestamp"};
}

1;

