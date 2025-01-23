#!/usr/bin/perl
package LsmboUniprot;

use strict;
use warnings;

use Data::Dumper;
use List::MoreUtils qw(uniq);
use List::Util qw(min shuffle);
use LsmboFunctions;
use LWP::UserAgent;
use JSON::XS qw(encode_json decode_json);

# only export these methods so they can be used without specifying the namespace
use Exporter qw(import);
our @EXPORT = qw(getUniprotRelease getFastaFromTaxonomyIds getFastaFromProteinIdsWithoutIdMapping getFastaFromProteinIdsWithIdMapping getTabularFromProteinIdsWithIdMapping getTabularFromProteinIdsWithoutIdMapping searchEntries UNIPROT_RELEASE getFastaFromUniprot REST_POST_Uniprot_tab_legacy REST_POST_Uniprot_fasta_legacy idmapping);

my $DEFAULT_NB_IDS = 250;
my $DEFAULT_SLEEP = 2;
my $DEFAULT_MAX_WAIT_TIME = 120;
my $DEFAULT_TO = "UniProtKB";
my $LAST_UNIPROT_RELEASE = "";
my $REST_URL = "https://rest.uniprot.org";


#######################################
### public methods for legacy calls ###
#######################################

sub checkFastaCompleteness {
  my ($fasta, $expected) = @_;
  open(my $fh, "<", $fasta) or LsmboFunctions::stderr("Failed to open fasta file: $!");
  my $nb = 0;
  while(<$fh>) {
    $nb++ if(m/^>/);
  }
  close $fh;
  LsmboFunctions::stderr("The download of the fasta file has failed: $nb proteins have been retrieved instead of $expected. Probably a problem with UniProt servers, please try again later.") if($nb ne $expected);
  print(">> $nb proteins where returned by UniProt\n");
}

sub downloadFasta {
  my ($url) = @_;
  # my $nb = 0;
  my $total = -1;
  my $isInError = 0;
  my $tempFastaFile = "uniprot-request.fasta";
  open(my $fh, ">", $tempFastaFile) or LsmboFunctions::stderr("Failed to create output file: $!");
  while($isInError == 0 && $url ne "") {
    my $response = sendGetRequest($url);
    if($total eq -1) {
      $total = $response->header('X-Total-Results');
      LsmboFunctions::stderr("Request has failed") if(!$total);
      print(">> $total proteins are expected for the current request\n");
    }
    my $content = $response->decoded_content;
    $isInError++ if($content eq "");
    print $fh $content;
    $url = get_next_link($response);
  }
  close $fh;
  checkFastaCompleteness($tempFastaFile, $total);
  return $tempFastaFile;
}

sub getFastaFromUniprot {
  my ($source, $genopts, $action, @ids) = @_;
  
  # The following request returns a fasta file with all the proteins from taxonomy 9606 and 7215 (including sub taxonomies) in swissprot and with the isoforms https://rest.uniprot.org/uniprotkb/search?format=fasta&includeIsoform=true&query=(taxonomy_id:9606+OR+taxonomy_id:7215)+AND+(reviewed:true)
  # reviewed:yes means SwissProt only ; reviewed:no means TrEMBL only ; do not use Reviewed to have both !
  # include=yes means that we want to include the isoforms of the proteins, which increases the size of the fasta file
  # the filter for proteins belonging to any of the reference proteomes is no longer available
  
  print "Searching proteins matching the requested taxonomies\n";
  my $isoforms = $genopts =~ m/isoforms/ ? "&includeIsoform=true" : "";
  my $idTag = $action eq "proteome" ? "proteome" : "taxonomy_id";
  my $ids = join(" OR ", map { "($idTag:$_)" } @ids);
  my $reviewed = "";
  $reviewed = "reviewed:true" if(lc($source) eq "sp");
  $reviewed = "reviewed:false" if(lc($source) eq "tr");
  my $options = $reviewed ne "" ? " AND ($reviewed)" : "";
  # my $url = "$REST_URL/uniprotkb/stream?format=fasta$isoforms&query=($ids)$options";
  # stream the results instead, it allows to know in advance the total number of proteins to expect
  # but it seems that the chunk size cannot be anything else than 500
  my $url = "$REST_URL/uniprotkb/search?format=fasta$isoforms&query=($ids)$options&size=500";

  return (downloadFasta($url), $LAST_UNIPROT_RELEASE);
}

sub REST_POST_Uniprot_tab_legacy {
  my ($inputFile, $from, $fieldsPtr, $taxonId) = @_;
  print "Uniprot REST method for file '$inputFile', requesting tabular format for data of type '$from', requested columns are ".join(", ", @{$fieldsPtr})."\n";
  # extract ids from $inputFile
  my @ids = extractIds($inputFile);
  # return the pointer of the output hash
  return getTabularFromProteinIdsWithIdMapping($fieldsPtr, \@ids, $from, $DEFAULT_TO, $taxonId);
}

sub REST_POST_Uniprot_fasta_legacy {
  my ($inputFile, $from, $fastaOutput) = @_;
  # extract ids from $inputFile
  my @ids = extractIds($inputFile);
  my $fasta = getFastaFromProteinIdsWithIdMapping($from, $DEFAULT_TO, undef, @ids);
  open(my $fh, ">>", $fastaOutput) or LsmboFunctions::stderr("Can't write fasta output file to append data: $!");
  print $fh $fasta;
  close $fh;
  return $LAST_UNIPROT_RELEASE;
}



######################
### public methods ###
######################

sub UNIPROT_RELEASE { 
  return "UNIPROT RELEASE"; 
}

sub getUniprotRelease {
  if($LAST_UNIPROT_RELEASE eq "") {
    my @ids = ("P12345");
    searchEntries("fasta", undef, \@ids);
  }
  return $LAST_UNIPROT_RELEASE;
}

# @ids: an array of ids
sub getFastaFromTaxonomyIds {
  my (@ids) = @_;
  return searchEntries("fasta", undef, \@ids);
}

# @ids: an array of ids
sub getFastaFromProteinIdsWithoutIdMapping {
  my (@ids) = @_;
  return searchEntries("fasta", undef, \@ids);
}

# $from: the database of the input ids
# $to: the database requested
# $taxonId: the taxonomy id if required (ie. for gene name) ; use undef if no taxonomy id is needed
# @ids: an array of ids
sub getFastaFromProteinIdsWithIdMapping {
  my ($from, $to, $taxonId, @ids) = @_;
  my @mappedIds = values(%{idmapping($from, $to, $taxonId, @ids)}); # run idmapping first
  return searchEntries("fasta", undef, \@mappedIds);
}

# $fieldsPtr: the address of the array containing the requested fields (list of available fields: https://www.uniprot.org/help/return_fields)
# $idsPtr: the address of the array containing the ids (ids can be accession, entry names or taxonomy ids)
sub getTabularFromProteinIdsWithoutIdMapping {
  my ($fieldsPtr, $idsPtr) = @_;
  my %mappedIds = map { $_ => $_ } @{$idsPtr};
  return getTabularFromProteinIds($fieldsPtr, \%mappedIds);
}

# $fieldsPtr: the address of the array containing the requested fields (list of available fields: https://www.uniprot.org/help/return_fields)
# $idsPtr: the address of the array containing the ids (ids can be accession, entry names or taxonomy ids)
# $from: the database of the input ids
# $to: the database requested
# $taxonId: the taxonomy id if required (ie. for gene name) ; use undef if no taxonomy id is needed
sub getTabularFromProteinIdsWithIdMapping {
  my ($fieldsPtr, $idsPtr, $from, $to, $taxonId) = @_;
  my $mappedIds = idmapping($from, $to, $taxonId, @{$idsPtr});
	# print Dumper($mappedIds);
  return getTabularFromProteinIds($fieldsPtr, $mappedIds);
}

# $format: fasta or tsv (more about formats here: https://www.uniprot.org/help/api_queries)
# $fieldsPtr: the address of the array containing the requested fields (list of available fields: https://www.uniprot.org/help/return_fields)
# $idsPtr: the address of the array containing the ids (ids can be accession, entry names or taxonomy ids)
sub searchEntries {
  my ($format, $fieldsPtr, $idsPtr) = @_;
  my $output = "";
  # prepare the url
  my $url = "$REST_URL/uniprotkb/stream?format=$format";
  # add fields if any
  $url .= "&fields=".join(",", @{$fieldsPtr}) if($fieldsPtr && scalar(@{$fieldsPtr}) > 0);
  # split the ids in groups of 500 then merge the fasta output in a single response
  my @ids = sort(@{$idsPtr});
  for(my $i = 0; $i < scalar(@ids); $i += $DEFAULT_NB_IDS) {
    my $stop = min($i + $DEFAULT_NB_IDS - 1, scalar(@ids) - 1);
    # run id mapping if requested
    my $ids = join("+OR+", map { setIdTag($_) } @ids[$i .. $stop]);
    # search the url
    $output .= sendGetRequest($url."&query=$ids")->decoded_content;
    sleep $DEFAULT_SLEEP;
  }
  return $output;
}

# $from: the database of the input ids
# $to: the database requested
# $taxonId: the taxonomy id if required (ie. for gene name) ; use undef if no taxonomy id is needed
# @ids: an array of ids
sub idmapping {
  my ($from, $to, $taxonId, @ids) = @_;
  my %mappedIds;
  # avoid the hard limitation of 100000 max ids per request
  my $maxNbIds = 85000;
  for(my $i = 0; $i < scalar(@ids); $i += $maxNbIds) {
    # run id mapping for this subset
    my $stop = min($i + $maxNbIds - 1, scalar(@ids) - 1);
    my %mapping = %{idmapping_unit($from, $to, $taxonId, @ids[$i .. $stop])};
    # add the results to the main output
    foreach my $key (keys(%mapping)) {
      $mappedIds{$key} = $mapping{$key};
    }
  }
	# print Dumper(\%mappedIds)."\n";
  return \%mappedIds;
}


#######################
### private methods ###
#######################

sub sendSimpleGetRequest {
  my ($url) = @_;
	# print "Send GET request to $url\n";
  my $contact = LsmboFunctions::getContactMailAddress();
  my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");
  my $request = HTTP::Request->new(GET => $url);
  $request->header('content-type' => 'application/json');
  return $agent->request($request);
}

sub sendGetRequest {
  my ($url) = @_;
	# print "sendGetRequest\n";
  # set a default timer of 60 seconds
  my $timer = 0;
  while($timer <= $DEFAULT_MAX_WAIT_TIME) {
    my $response = sendSimpleGetRequest($url);
    $LAST_UNIPROT_RELEASE = $response->header('X-UniProt-Release');
    if ($response->is_success) {
      return $response;
    } else {
      LsmboFunctions::stdwarn("The request failed with error ".$response->code." (".$response->message.") and will be run again in a few seconds") if($timer != 0);
      # die Dumper($response)."\n" if($response->code eq 429);
      $timer += 10;
      sleep 10;
    }
  }
  LsmboFunctions::stderr("The request has failed too many times and will not be tried anymore. The URL was: $url");
}

sub extractIds {
  my ($inputFile) = @_;
  my @ids;
  open(my $fh, "<", $inputFile) or LsmboFunctions::stderr("Can't open protein input file: $!");
  while(<$fh>) {
    chomp;
    next if($_ eq "");
    push(@ids, LsmboFunctions::cleanProteinId($_));
  }
  close $fh;
  return @ids;
}

sub getTabularFromProteinIds{
  my ($fieldsPtr, $mappedIdsPtr) = @_;
  
  # get the ids to search and the new ids as keys to the input ids
  my %mappedIds = %{$mappedIdsPtr}; # user entry => accession
  my @inputIds = sort(values(%mappedIds)); # list of accession numbers
	
	# reverse the mapping, will be used later
	my %reversedMappedIds;
  while(my ($key, $value) = each %mappedIds) {
    push(@{$reversedMappedIds{$value}}, $key);
  }
	
  # always search id and accession, even if they are already requested (this will help us tie together input and output)
  my @fields = @{$fieldsPtr};
  push(@fields, "id", "accession");
  
  # send the HTTP request
  my @data = split(/\n/, searchEntries("tsv", \@fields, \@inputIds));
	
  # prepare the output with the uniprot version added
  my %output;
  $output{UNIPROT_RELEASE()} = $LAST_UNIPROT_RELEASE;
  
  # transform the output to be like the legacy version
  my $headerLine = shift(@data);
  foreach my $line (@data) {
    my @items = split(/\t/, $line);
    # remove the two extra fields requested
    my $acc = pop(@items);
    my $id = pop(@items);
    # searches the original user entry in %mappedIds and either $acc or $id
    my $userEntry = "";
    # if(exists($mappedIds{$acc})) {
		if(grep(/$acc/, @inputIds)) {
      $userEntry = $acc;
		# } elsif(exists($mappedIds{$id})) {
		} elsif(grep(/$id/, @inputIds)) {
      $userEntry = $id;
		}
    # add the items to hash, with the user entry as the key
    foreach my $originalId (@{$reversedMappedIds{$userEntry}}) {
			my @allItems = ($originalId, @items); # put the original user entry at the beginning of the results
      $output{$userEntry} = \@allItems;
		}
  }
  return \%output;
}

sub looksLikeTaxId {
  # a taxonomy id is like 9606
  return 1 if($_[0] =~m /^[0-9]+$/);
  return 0;
}

sub looksLikeAccession {
  # a Uniprot accession is like P12345
  # a Uniprot id is like AATM_RABIT
  return 0 if(uc($_[0]) =~m /^[A-Z,0-9]+_[A-Z,0-9]+$/);
  return 1;
}

sub setIdTag {
  my ($id) = @_;
  return "(taxonomy_id:$id)" if(looksLikeTaxId($id) eq 1);
  return "(accession:$id)" if(looksLikeAccession($id) eq 1);
  return "(id:$id)";
}

### the following methods for idmapping are translated from the uniprot python example ###

# runs a full idmapping on all the given ids
sub idmapping_unit {
  my ($from, $to, $taxonId, @ids) = @_;
  my $map;
  my $job_id = submit_id_mapping($from, $to, $taxonId, @ids);
  if(check_id_mapping_results_ready($job_id)) {
    my $link = get_id_mapping_results_link($job_id);
    $map = get_id_mapping_results_search($link);
  }
  return $map;
}

# sends the request for idmapping
sub submit_id_mapping {
  my ($from, $to, $taxonId, @ids) = @_;
  
  # prepare parameters for the POST request
  my $params = ['from' => $from, 'to' => $to, 'ids' => join(",", @ids)];
  push(@$params, 'taxon' => $taxonId) if($taxonId && $taxonId ne "");
  
  # send the request to uniprot
  my $contact = LsmboFunctions::getContactMailAddress();
  my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");
  push @{$agent->requests_redirectable}, 'POST';
  my $response = $agent->post("$REST_URL/idmapping/run", $params, 'Content_Type' => 'form-data');
  
  # return the jobId
  my $jobId = "";
  if ($response->is_success) {
    my $version = $response->header('X-UniProt-Release');
    $jobId = $response->decoded_content();
    $jobId =~ s/.*jobId":"//;
    $jobId =~ s/"}//;
    # print "ABU job ID: $jobId\n";
  } else {
    LsmboFunctions::stderr("UniProtKB HTTP request failed with error code:".$response->code." ; params where ".Dumper($params));
  }
  return $jobId;
}

# checks the status of the job
sub check_id_mapping_results_ready {
  my ($jobId) = @_;
  my $jobStatus = "";
  my $timer = 0;
  while($jobStatus ne "FINISHED" && $timer <= $DEFAULT_MAX_WAIT_TIME) {
    if($timer > 0) {
      # print "Retrying in $DEFAULT_SLEEP seconds\n";
      sleep $DEFAULT_SLEEP;
      $timer += $DEFAULT_SLEEP;
    }
    my $response = sendGetRequest("$REST_URL/idmapping/status/$jobId");
    my %json = %{decode_json($response->decoded_content())};
    if(exists($json{"jobStatus"})) {
      $jobStatus = $json{"jobStatus"};
    } else {
      $jobStatus = "FINISHED";
    }
  }
  return $jobStatus eq "FINISHED";
}

# get the link of the first page of the results
sub get_id_mapping_results_link {
  my ($jobId) = @_;
  my $response = sendGetRequest("$REST_URL/idmapping/details/$jobId");
  # TODO test if KO
  my $json = decode_json($response->decoded_content());
  return $json->{"redirectURL"};
}

# get the link of the next page of the results
sub get_next_link {
  my ($response) = @_;
  return $1 if($response->header("link") && $response->header("link") =~ m/<(.+)>; rel="next"/);
  return "";
}

# get all the results, page by page
sub get_id_mapping_results_search {
  my ($url) = @_;
  my %mappedIds;
  while($url ne "") {
    my $response = sendGetRequest($url);
    # TODO test if KO
    my $json = decode_json($response->decoded_content);
    foreach my $output (@{$json->{"results"}}) {
			# TODO idmapping can return multiple ids for one input id, currently we only return the last id
      # print $output->{"from"}." = ".$output->{"to"}{"primaryAccession"}."\n";
      $mappedIds{$output->{"from"}} = $output->{"to"}{"primaryAccession"};
    }
    $url = get_next_link($response);
  }
	# print Dumper(\%mappedIds)."\n";
  return \%mappedIds;
}

1;

