#!/usr/bin/perl
use strict;
use warnings;

use Archive::Zip;
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Slurp qw(read_file write_file);
use JSON::XS qw(encode_json decode_json);
use List::MoreUtils qw(uniq);
use List::Util 'shuffle';
use LWP::Simple;
use LWP::UserAgent;
use Number::Bytes::Human qw(format_bytes);
use POSIX qw(strftime);
use Spreadsheet::ParseExcel::Utility 'sheetRef';
# use Spreadsheet::Reader::ExcelXML;
use Spreadsheet::ParseXLSX;
use Excel::Template::XLSX; # wraps Excel::Writer::XLSX and allows to create a new file with the data of an old one

###################
# GENERIC METHODS #
###################

my $GLOBAL = parameters(dirname(__FILE__)."/settings.json");

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
    } or stderr("Can't read parameter file: $!", 1);
}

# Json parameters file sometimes uses true/false and sometimes 0/1
# This methods makes sure to have true/false only
sub booleanToString {
    my $value = "false";
    eval { $value = "true" if($_[0] eq "true");
    } or $value = "true" if($_[0] == 1);
    return $value;
}

# Character '+' is not allowed in Galaxy parameters
sub checkUniprotFrom {
    my ($from) = @_;
    return "ACC+ID" if($from eq "ACC_ID");
    return $from;
}

# Galaxy lists are provided in a single string: spXP28076XPSB9_MOUSE__cn__spXO35522XPSB9_MUSMB__cn__spXQ2TPA8XHSDL2_MOUSE__cn__spXQ3T0K1XCALU_BOVIN__cn__spXQ80X76XSPA3F_MOUSE__cn__
# This method will split the string and write each in the given file
sub extractListEntries {
    my ($list, $file) = @_;
    open(my $fh, ">", $file) or stderr("Can't write to file '$file': $!", 1);
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
    } elsif(m/.^.\|([^ ]+)/) {      # sp|P12345 => P12345
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
    open($fh, ">", $tempFile) or stderr("Can't create temporary protein input file: $!", 1);
    open(my $in, "<", $file) or stderr("Can't open protein input file: $!", 1);
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
            open($fh, ">", $tempFile) or stderr("Can't create temporary protein input file: $!", 1);
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
    open(my $fh, "<", $inputFile) or stderr("Can't read file '$inputFile': $!", 1);
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

####################
# INTERNET METHODS #
####################

sub UNIPROT_RELEASE { return "UNIPROT RELEASE"; }

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
    print "REST GET url: $url\n";
    my $contact = getContactMailAddress();
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
        stderr("HTTP GET error code:".$response->code." with message: ".$response->message, 1);
    }
}

sub REST_POST_Uniprot_tab {
    my ($inputFile, $from, $columns, $taxo) = @_;
    print "Uniprot REST method for file '$inputFile', requesting tabular format for data of type '$from', requested columns are $columns\n";
    
    my $NBTRIESTOTAL = 10;
    my $uniprotURL = "https://www.uniprot.org/uploadlists/";
    my $contact = getContactMailAddress();
    my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");
    push @{$agent->requests_redirectable}, 'POST';
    my $params = ['format' => 'tab', 'from' => $from, 'to' => 'ACC', 'columns' => $columns];
    push(@$params, 'taxon' => $taxo) if(scalar(@_) == 6 && $taxo ne "");
    my $nbColumns = scalar(split(",", $columns));
    
    my %output;
    my @inputFiles = checkUniprotInputFile($inputFile);
    my $i = 1;
    foreach my $file (@inputFiles) {
        # update the parameters
        push(@$params, 'file' => [$file]);
        my $nbTries = 0;
        my $isSuccess = 0;
        while($isSuccess == 0) {
          my ($code, $message, $version) = REST_POST_Uniprot_single($agent, $uniprotURL, $params);
          if($code == 400 || $code == 500) {
            # these error codes do not mean the request was necessarily wrong, let's retry another time
            $nbTries++;
            stdwarn("HTTP GET error code:$code with message: $message (attempt $nbTries/$NBTRIESTOTAL)");
            sleep 2; # wait a bit before trying again
          } elsif($code > 0) {
            # any other error code should end the script (is it really necessary ?)
            stderr("HTTP GET error code:$code with message: $message");
          } else {
            $output{UNIPROT_RELEASE()} = $version;
            my @data = split(/\n/, $message);
            # remove header line
            my $headerLine = shift(@data);
            # add the lines to the complete output
            foreach my $line (@data) {
                my @items = split(/\t/, $line);
                # remove the isomap column if there is one
                pop(@items) if(scalar(@items) == $nbColumns + 2);
                # move the user entry from last to first
                my $userEntry = pop(@items);
                unshift(@items, $userEntry);
                $output{$userEntry} = \@items;
            }
            # exit the while loop once the request succeeds
            last;
          }
          stderr("Stopped trying to access Uniprot after $NBTRIESTOTAL attempts", 1) if($nbTries == $NBTRIESTOTAL);
        }
    }
    unlink(@inputFiles);
    print "Uniprot returned ".scalar(keys(%output))." results\n";
    return \%output;
}

sub REST_POST_Uniprot_fasta {
    my ($inputFile, $from, $fastaOutput) = @_;
    print "Uniprot REST method for file '$inputFile', requesting fasta format for data of type '$from'\n";
    
    my $NBTRIESTOTAL = 5;
    my $contact = getContactMailAddress();
    my $uniprotURL = "https://www.uniprot.org/uploadlists/";
    my $agent = LWP::UserAgent->new(agent => "libwww-perl $contact");
    push @{$agent->requests_redirectable}, 'POST';
    my $params = ['format' => 'fasta', 'from' => $from, 'to' => 'ACC'];
    
    my $uniprotVersion;
    my @inputFiles = checkUniprotInputFile($inputFile);
    my $i = 1;
    foreach my $file (@inputFiles) {
        # update the parameters
        push(@$params, 'file' => [$file]);
        my $nbTries = 0;
        my $isSuccess = 0;
        while($isSuccess == 0) {
            my ($code, $message, $version) = REST_POST_Uniprot_single($agent, $uniprotURL, $params);
            if($code == 0) {
                $uniprotVersion = $version;
                open(my $fh, ">>", $fastaOutput) or stderr("Can't write fasta output file to append data: $!", 1);
                print $fh $message;
                close $fh;
                # exit the while loop once the request succeeds
                last;
            } elsif($code == 400 || $code == 500) {
                # these error codes do not mean the request was necessarily wrong, let's retry another time
                stderr("HTTP GET error code:$code with message: $message (attempt $nbTries/$NBTRIESTOTAL)");
                $nbTries++;
            } else {
                # any other error code should end the script (is it really necessary ?)
                stderr("HTTP GET error code:$code with message: $message");
            }
            stderr("Stopped trying to access Uniprot after $NBTRIESTOTAL attempts", 1) if($nbTries == $NBTRIESTOTAL);
        }
    }
    unlink(@inputFiles);
    print "Uniprot request was successful\n";
    return $uniprotVersion;
}

sub REST_POST_Uniprot_single {
  my ($agent, $uniprotURL, $params) = @_;
  my $SLEEPTIME = 2;
  # send to request to uniprot
  my $response = $agent->post($uniprotURL, $params, 'Content_Type' => 'form-data');
  while (my $wait = $response->header('Retry-After')) {
    print STDERR "Waiting ($wait)...\n";
    sleep $wait;
    $response = $agent->get($response->base);
  }
  
  # prepare output
  my $code = 0;
  my $message = "";
  my $version = "";
  
  # return the output
  if ($response->is_success) {
      $version = $response->header('X-UniProt-Release');
      $message = $response->decoded_content();
  } else {
      $code = $response->code;
      $message = $response->message;
  }
  # wait a bit between two requests
  sleep($SLEEPTIME);
  # return exit code and message
  return ($code, $message, $version);
}

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


################
# NCBI METHODS #
################

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
  open(my $fh, ">", $outputFile) or stderr("Failed to create Entrez output file '$outputFile': $!", 1);

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
  open(my $fh, ">", $outputFile) or stderr("Failed to create Entrez output file '$outputFile': $!", 1);

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



###################
# LOGGING METHODS #
###################

# Log messages with trace (set die = 1 to stop the process, default is 0)
# TODO stderr should always die at the end
sub stderr {
    my ($message, $die) = @_;
    $message = "Undefined error" if(scalar(@_) == 0);
    $message = "[".getDate("%Y-%m-%d %H:%M:%S")." - Error] ".$message."\n";
    my $i = 0;
    while ( (my @call_details = (caller($i++))) ){
        $message .= "\t".$call_details[1].":".$call_details[2]." in function ".$call_details[3]."\n";
    }
    if($die) {
        die($message);
    } else {
        print STDERR $message;
    }
}

sub stdwarn {
  my ($message) = @_;
  $message = "[".getDate("%Y-%m-%d %H:%M:%S")." - Warning] ".$message."\n";
  print STDOUT $message;
  return 0;
}

#################
# EXCEL METHODS #
#################

# Reads a cell from an Excel file
# $sheet must be a Spreadsheet::Reader::ExcelXML object
sub getValue {
    my ($sheet, $row, $col) = @_;
    my $cell = $sheet->get_cell($row, $col);
    # apparently this library provides different ways of handling cell values, i hope i covered everything !
    eval {
        return $cell->unformatted();
    } or do {
        eval {
            return $cell->value();
        } or do {
            # so far i've only seen this for zero values...
            # return 0 if($cell && $cell ne 'EOR'); # we are not expecting any 0 as a category or a GO
            return "";
        }
    };
}

# Reads an Excel file and extract values from a given column
sub extractIds {
    my ($xlsxFile, $sheetNumber, $cellAddress) = @_;
    # open excel file
    print "Opening file $xlsxFile at sheet #$sheetNumber, reading from cell $cellAddress\n";
    my $parser = Spreadsheet::ParseXLSX->new;
    my $workbook = $parser->parse($xlsxFile);
    stderr($parser->error(), 1) if(!defined $workbook);
    my @worksheets = $workbook->worksheets();
    my $sheet = $worksheets[$sheetNumber-1];
    # get rows and columns
    my ($row, $col) = sheetRef($cellAddress);
    my ($row_min, $row_max) = $sheet->row_range();
    # open the output file
    my @ids;
    # read the columns and print each id to the file
    for my $i ($row .. $row_max) {
        push(@ids, getValue($sheet, $i, $col));
    }
    # returns all the ids
    return @ids;
}

# write an array of values without format
sub writeExcelLine {
    my ($sheet, $row, @cells) = @_;
    writeExcelLineF($sheet, $row, undef, @cells);
}

# write an array of values with given format
sub writeExcelLineF {
    my ($sheet, $row, $format, @cells) = @_;
    my $col = 0;
    foreach my $cell (@cells) {
        $sheet->write($row, $col++, $cell, $format);
    }
}

# sets width for multiple columns
# width in pixel here corresponds to 1/5 of the size in centimeter displayed in Excel
# so if you want a column with a size of 3cm, use the value 15 (3x5)
sub setColumnsWidth {
    my ($sheet, @widths) = @_;
    for(my $i = 0; $i < scalar(@widths); $i++) {
        $sheet->set_column($i, $i, $widths[$i]);
    }
}

# transforms a letter representing an Excel column into its number equivalent
sub getColumnId {
  my @ids = ();
  foreach my $column (@_) {
    # A = 65
    push(@ids, ord(uc($column)) - 65); # TODO check if first column is zero or one
  }
  return @ids;
}

# adds a worksheet with a unique and valid name
sub addWorksheet {
    my ($workbook) = @_;
    # easy case: no name given to the sheet
    return $workbook->add_worksheet() if(scalar(@_) == 1);
    # or a name is given but it is not valid
    return $workbook->add_worksheet() if(scalar(@_) > 1 && isSheetNameValid($_[1]) == 0);
    # when a name is provided we have to make sure it's unique
    my $i = 0;
    my $defaultSheetName = $_[1];
    my $sheetName = $defaultSheetName;
    my $worksheet;
    # avoid infinite loop
    while($i < 10) {
        eval {
            # try to create the sheet with the given name
            $worksheet = $workbook->add_worksheet($sheetName);
            # exit the loop after the first success (hopefully the first try !)
            $i = 10;
        } or $sheetName = $defaultSheetName." (".($i+2).")";
        $i++;
    }
    # return the created worksheet if it worked
    return $worksheet if($worksheet);
    # otherwise fall back on the default sheet name
    # it can happen if there are already 10 sheets with that name, or if the name with the number exceeds 32 characters
    return $workbook->add_worksheet();
}

# checks all restrictions
sub isSheetNameValid {
    my ($sheetName) = @_;
    # must not be "History" or "Historique"
    return stdwarn("Excel sheet name '$sheetName' is not valid: names 'History' or 'Historique' are not allowed") if($sheetName eq "History" || $sheetName eq "Historique");
    # must be less than 32 characters
    return stdwarn("Excel sheet name '$sheetName' is not valid: name length must be less than 32 characters") if(length($sheetName) > 32);
    # must not start or end with an apostrophe
    return stdwarn("Excel sheet name '$sheetName' is not valid: name cannot start with an apostrophe") if($sheetName =~ m/^'/);
    return stdwarn("Excel sheet name '$sheetName' is not valid: name cannt end with and apostrophe") if($sheetName =~ m/'$/);
    # must not contains []:*?/\
    return stdwarn("Excel sheet name '$sheetName' is not valid: name cannot contain the characters [ ] : * ? \\ /") if($sheetName =~ m/[\[\]\:\*\?\/\\]/g);
    # the name seems ok, it just has to be unique but it's not checked here
    return 1;
}


###############
# OUTPUT DATA #
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

1;

