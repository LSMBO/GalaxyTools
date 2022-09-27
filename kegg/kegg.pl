#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use Image::Size;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(archive booleanToString getDate getVersion parameters stderr);
use LsmboExcel qw(addWorksheet getColumnId getColumnLetter getValue setColumnsWidth writeExcelLine writeExcelLineF);
use LsmboRest qw(downloadFile REST_GET);
use LsmboUniprot qw(getUniprotRelease idmapping REST_POST_Uniprot_tab_legacy UNIPROT_RELEASE);
use lib dirname(__FILE__);
use HtmlGenerator qw(createHtmlFile);

use File::Copy;
use List::Util qw(min);
use List::MoreUtils qw(uniq);
use Scalar::Util qw(looks_like_number);
use URL::Exists qw(url_exists);

my ($paramFile, $outputFile, $zipFile) = @ARGV;

# set global variables here
my %PARAMS = %{parameters($paramFile)};
my $IS_UNIPROT = $PARAMS{"idtype"} eq "uniprot" || $PARAMS{"idtype"} eq "uniprotcheck" ? 1 : 0;
# there are boolean options, make sure they are set before checking them
my $WITH_SITES = booleanToString($PARAMS{"type"}{"value"}) eq "true" ? 1 : 0;
my $WITH_CONDS = $PARAMS{"type"}{"statistics"}{"value"} eq "conditions" ? 1 : 0;
my $WITH_STATUS = $PARAMS{"type"}{"statistics"}{"value"} eq "none" ? 0 : 1;

# database directories
my $BINARIES_DIRECTORY = dirname(__FILE__);
my $DIR_CONF = "$BINARIES_DIRECTORY/conf";
my $DIR_INFO = "$BINARIES_DIRECTORY/info";
my $DIR_PNG = "$BINARIES_DIRECTORY/map";
my $DIR_HTML = "html";

# other data
my $DEFAULT_TAXONOMY = "map"; # only for compound entries
my $KEGG_URL = "https://rest.kegg.jp";
my $MAX_AGE_IN_DAYS_FOR_KEGG_FILES = 30 * 2; # 2 months max
my $FORCE_FILE_UPDATE = 0;
my %STATUS = ("KO" => {"id" => 1, "text" => "Non significant", "color" => "#ffe333", "symbol" => "\\2716", "html" => "&#10006;", "description" => "Does not satisfy statistical criteria"}, # yellow
              "OK" => {"id" => 2, "text" => "Significant", "color" => "#428fd3", "symbol" => "\\2714", "html" => "&#10004;", "description" => "Satisfies statistical criteria"}, # blue
              "UP" => {"id" => 3, "text" => "Upregulated", "color" => "#ff4c33", "symbol" => "\\2191", "html" => "&#8593;", "description" => "Satisfies statistical criteria, the protein is upregulated"}, # red
              "DO" => {"id" => 4, "text" => "Downregulated", "color" => "#53c326", "symbol" => "\\2193", "html" => "&#8595;", "description" => "Satisfies statistical criteria, the protein is downregulated"}); # green

# data
my %CONDITIONS; # $CONDITIONS{condition_id} = condition_name
my %NBSTATUS; # $NBSTATUS{userId_i}{site_j}{status_key} = nb
my %DATA; # $DATA{userId_i}{site_j}{condition_id} = status_key
my %USERID_PER_UNIPROT_ENTRY; # map between the user input ids and the corresponding Uniprot Entry
my %KEGG; # $KEGG{userId_i}{keggId} = array(pathway) # TO BE REPLACED WITH %PATHWAYS
my %PATHWAYS; # $PATHWAYS{userId_i}{keggId}{"pathways"} = array(pathway) ; $PATHWAYS{userId_i}{keggId}{"taxonomy"} = hsa
my %PATHWAY_INFO; # $PATHWAY_INFO{pathway}{"name"} = name, $PATHWAY_INFO{pathway}{"class"} = class
my %TAXONOMIES_PER_KEGGID; # $TAXONOMIES_PER_KEGGID{keggId} = tax_id
my %DUPLICATE_ENTRIES; # stores the ids (and sites if needed) that are more than once in the input file

start();
print "Correct ending of the script\n";

exit;

# extraction of the value, but there may not be any value in the file
sub getExcelValue {
  my ($worksheet, $row, $nbColumns, $column) = @_;
  my $value = $nbColumns >= $column ? getValue($worksheet, $row, $column) : "";
  return looks_like_number($value) ? $value : 1000000; # use a very large integer
}

sub getCurrentStatus {
  my ($anova, $tukey, $fc) = @_;
  if($PARAMS{"type"}{"statistics"}{"value"} eq "pvalue" && $anova < $PARAMS{"thresholds"}{"pvalue"}) {
    return "OK";
  } elsif($PARAMS{"type"}{"statistics"}{"value"} eq "pvalue_fc" && $anova < $PARAMS{"thresholds"}{"pvalue"}) {
    return "UP" if($fc > $PARAMS{"thresholds"}{"fc"});
    return "DO" if($fc < -$PARAMS{"thresholds"}{"fc"});
    return "OK";
  } elsif($WITH_CONDS eq 1 && $anova < $PARAMS{"thresholds"}{"pvalue"} && $tukey < $PARAMS{"thresholds"}{"tukey"}) {
    return "UP" if($fc > $PARAMS{"thresholds"}{"fc"});
    return "DO" if($fc < -$PARAMS{"thresholds"}{"fc"});
    return "OK";
  }
  return "KO";
}

sub getValueIf {
  my ($worksheet, $row, $nbColumns, $key) = @_;
  if(exists($PARAMS{"type"}{"statistics"}{$key})) {
    return getExcelValue($worksheet, $row, $nbColumns, getColumnId($PARAMS{"type"}{"statistics"}{$key}));
  } else {
    return undef;
  }
}

sub getStatus {
  my ($worksheet, $row, $nbColumns) = @_;
  my %status;
  my $anova = getValueIf($worksheet, $row, $nbColumns, "col_pvalue");
  if($WITH_CONDS eq 1) {
    # get the first tukey column number
    my ($ctk, $cfc) = getColumnId($PARAMS{"type"}{"statistics"}{"col_tukey"}, $PARAMS{"type"}{"statistics"}{"col_fc"});
    # loop on each condition
    foreach my $i (0 .. scalar(%CONDITIONS) - 1) {
      my $tukey = getExcelValue($worksheet, $row, $nbColumns, $ctk + $i*2);
      my $fc = getExcelValue($worksheet, $row, $nbColumns, $cfc + $i*2);
      my $status = getCurrentStatus($anova, $tukey, $fc);
      # $status{$i} = $status if($status ne "KO"); # only store relevant information
      $status{$i} = $status;
    }
  } else {
    # use a default condition that will not be shown
    my $tukey = getValueIf($worksheet, $row, $nbColumns, "col_tukey");
    my $fc = getValueIf($worksheet, $row, $nbColumns, "col_fc");
    $status{0} = getCurrentStatus($anova, $tukey, $fc);
  }
  return \%status;
}

sub looksLikeUniProt {
  my ($id) = @_;
  # allow accession numbers as defined in https://www.uniprot.org/help/accession_numbers
  # examples: A2BC19, P12345, A0A023GPI8
  return 1 if($id =~ m/^[OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2}$/);
  # allow swissprot entry names, as defined in https://www.uniprot.org/help/entry_name
  # examples: INS_HUMAN, INS1_MOUSE, INS2_MOUSE
  return 1 if($id =~ m/^[A-Z0-9]{1,5}_[A-Z0-9]{1,5}$/);
  # allow trembl entry names, as defined in https://www.uniprot.org/help/entry_name
  # examples: A2BC19_HELPX, P12345_RABIT, A0A023GPI8_CANBL
  return 1 if($id =~ m/^[A-Z0-9]{1,5}_[A-Z0-9]{1,5}$/);
  return 0;
}

sub extractData {
  # make a copy of the file, otherwise the XLSX parser may fail
  my $inputFile = "input.xlsx";
  copy($PARAMS{"inputFile"}, $inputFile);

  # open the excel file and the first sheet
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($inputFile);
  stderr($parser->error()."\n") if(!defined $workbook);
  my @worksheets = $workbook->worksheets;
  my $sheetNumber = $PARAMS{"sheetNumber"} - 1;
  my $worksheet = $worksheets[$sheetNumber];
  
  # get the boundaries of the table
  my $nbRows = $PARAMS{"headerLine"} - 1;
  my ($row_min, $row_max) = $worksheet->row_range();
  my ($col_min, $col_max) = $worksheet->col_range();
  $col_min++; # skip identifier column
  $col_min++ if($WITH_SITES eq 1); # skip site column

  # get the conditions on the first line
  if($WITH_CONDS eq 1) {
    # determine the number of conditions in the file
    my $estNbConds = ($col_max - $col_min) / 2;
    # set default conditions
    my $id = 0;
    %CONDITIONS = map { $id++ => "Condition $_" } (1 .. $estNbConds);
    # use the given conditions if their number fits the number of conditions
    my @conditions = uniq(split("__cn__", $PARAMS{"type"}{"statistics"}{"conditions"}));
    if(scalar(@conditions) ne $estNbConds) {
      # if the conditions are not provided or do not fit the actual number of conditions
      # then try to get the headers from the input file, but they have to be unique
      @conditions = ();
      my $start = min(getColumnId($PARAMS{"type"}{"statistics"}{"col_tukey"}, $PARAMS{"type"}{"statistics"}{"col_fc"}));
      for(my $i = $start; $i <= $col_max; $i += 2) {
        push(@conditions, getValue($worksheet, $row_min, $i));
      }
      @conditions = uniq(@conditions);
    }
    # only use the conditions if their number corresponds to the expected number
    if(scalar(@conditions) eq $estNbConds) {
      $id = 0;
      %CONDITIONS = map { $id++ => $_ } @conditions;
    }
  }
  
  my $nbNotLikeUniprot = 0;
  my $maxNotLikeUniprot = 10;
  # skip header line
  for my $row ($row_min + 1 .. $row_max) {
    my $id = getValue($worksheet, $row, getColumnId($PARAMS{"type"}{"statistics"}{"col_id"}));
    # stop if at least 10 identifiers do not look like uniprot entries or accession
    if($IS_UNIPROT eq 1) {
      $nbNotLikeUniprot++ if(looksLikeUniProt($id) eq 0);
      stderr("Too many protein identifiers are not UniProt identifiers, please only use Accession numbers or Entry names") if($nbNotLikeUniprot > $maxNotLikeUniprot);
    }
    my $site = $WITH_SITES eq 1 ? getValue($worksheet, $row, getColumnId($PARAMS{"type"}{"statistics"}{"col_site"})) : 1;
    next if($id eq "" || $site eq "");
    # store the duplicate entries, just to inform the user at the end
    if($WITH_SITES eq 1) {
      $DUPLICATE_ENTRIES{$id}{$site}++ if(exists($DATA{$id}{$site}));
    } else {
      $DUPLICATE_ENTRIES{$id}++ if(exists($DATA{$id}));
    }
    $DATA{$id}{$site} = getStatus($worksheet, $row, $col_max);
    $nbRows++;
  }
  
  # count how many status appear in all conditions for each entry and site
  my $nbConditions = scalar(%CONDITIONS);
  foreach my $userEntry (keys(%DATA)) {
    foreach my $site (keys(%{$DATA{$userEntry}})) {
      # initialize the count of status to zero, except for KO that will be decreased
      foreach (keys(%STATUS)) { $NBSTATUS{$userEntry}{$site}{$_} = 0; }
      $NBSTATUS{$userEntry}{$site}{"KO"} = $nbConditions;
      foreach my $status (values(%{$DATA{$userEntry}{$site}})) {
        $NBSTATUS{$userEntry}{$site}{$status}++;
        $NBSTATUS{$userEntry}{$site}{"KO"}--;
      }
    }
  }

  print "$nbRows rows have been read\n";
}

sub getUniprotEntries {
  my $from = "UniProtKB_AC-ID";
  my $to = "UniProtKB";
  %USERID_PER_UNIPROT_ENTRY = %{idmapping($from, $to, undef, keys(%DATA))};
  # replace the old entries with the new ones
  foreach my $userEntry (keys(%DATA)) {
    if(exists($USERID_PER_UNIPROT_ENTRY{$userEntry})) {
      my $uniprotEntry = $USERID_PER_UNIPROT_ENTRY{$userEntry};
      if($uniprotEntry ne $userEntry) {
        $DATA{$uniprotEntry} = $DATA{$userEntry};
        delete($DATA{$userEntry});
      }
    } else {
      print "User entry $userEntry was not found in UniProt\n";
    }
  }
}

sub fakeUniprotEntries {
  foreach my $userEntry (keys(%DATA)) { $USERID_PER_UNIPROT_ENTRY{$userEntry} = $userEntry; }
}

sub isEntryKeggWorthy {
  my ($entry) = @_;
  # return 1;
  return 1 if($WITH_CONDS eq 0);
  my $nbNotKo = 0;
  foreach my $site (keys(%{$DATA{$entry}})) {
    foreach my $key (keys(%STATUS)) {
      next if($key eq "KO");
      $nbNotKo++ if(exists($NBSTATUS{$entry}{$site}{$key}) && $NBSTATUS{$entry}{$site}{$key} > 0);
    }
  }
  # it is worthy if there is at least one non-KO condition
  return $nbNotKo > 0 ? 1 : 0;
}

sub callKeggConv {
  my @proteins = @_;
  # split the ids in groups of 100
  my $num = 0;
  my $nb = 100;
  # my $nb = 200;
  my $total = scalar(@proteins);
  for(my $i = 0; $i < $total; $i += $nb) {
    my $stop = min($i + $nb - 1, $total - 1);
    # store the kegg ids on the fly
    foreach (split("\n", REST_GET("$KEGG_URL/conv/genes/uniprot:".join("+uniprot:", @proteins[$i .. $stop])))) {
      # returns lines formatted as: "up:Q96QH8\thsa:729201"
      if(m/.+:(.+)\t(.+):(.+)$/) {
        my $acc = $1;
        my $taxo = $2;
        my $keggId = "$2:$3";
        $KEGG{$acc}{$keggId} = ();
        $TAXONOMIES_PER_KEGGID{$keggId} = $taxo;
      }
    }
    print "$i/$total entries have been sent to Kegg REST API...\n" if(($i + $nb) % $nb eq 0);
  }
}

sub callKeggLink {
  my %pathways;
  foreach my $taxonomy (uniq(values(%TAXONOMIES_PER_KEGGID))) {
    $taxonomy = "compound" if($taxonomy eq $DEFAULT_TAXONOMY);
    my @pathways = split(/\n/, REST_GET("$KEGG_URL/link/pathway/$taxonomy"));
    # returns lines formatted as: "hsa:6484\tpath:hsa01100" or "cpd:C00022\tpath:map00010"
    foreach my $line (@pathways) {
      my ($id, $pathway) = split(/\t/, $line);
      $id =~ s/^cpd://;
      $pathway =~ s/^path://;
      push(@{$pathways{$id}}, $pathway);
    }
  }
  return \%pathways;
}

sub getKeggPathways {
  # get the entries for which we want to get the pathways
  my @entries;
  foreach (keys(%DATA)) {
    push(@entries, $_) if(isEntryKeggWorthy($_) ne 0);
    # push(@entries, $_);
  }
  # search their ids
  if($IS_UNIPROT eq 1) {
    callKeggConv(@entries);
  } else {
    # special case for compounds, they replace the entries and the kegg ids
    foreach my $compoundId (@entries) {
      $KEGG{$compoundId}{$compoundId} = ();
      $TAXONOMIES_PER_KEGGID{$compoundId} = $DEFAULT_TAXONOMY;
    }
  }
  # get the linked pathways
  my $pathways = callKeggLink();
  # associate the pathways to the entries in %PATHWAYS
  foreach my $acc (keys(%KEGG)) {
    foreach my $keggId (keys(%{$KEGG{$acc}})) {
      if(exists($pathways->{$keggId})) { # it should always exist !!
        $KEGG{$acc}{$keggId} = $pathways->{$keggId};
      }
    }
  }
}

sub getConfFile { return "$DIR_CONF/".$_[0].".conf"; }
sub getPngFile { return "$DIR_PNG/".$_[0].".png"; }
sub getInfoFile { return "$DIR_INFO/".$_[0].".txt"; }
sub getHtmlFile { return "$DIR_HTML/".$_[0].".html"; }

sub isFileUpdadeRequired {
  my ($pathway) = @_;
  return 1 if($FORCE_FILE_UPDATE eq 1);
  my $confFile = getConfFile($pathway);
  return 1 if(!-f $confFile); # if the file is missing, the update is needed
  return 1 if(!-f getPngFile($pathway)); # if the file is missing, the update is needed
  return 1 if(!-f getInfoFile($pathway)); # if the file is missing, the update is needed
  my $mtime = (-C $confFile);
  return 1 if($mtime > $MAX_AGE_IN_DAYS_FOR_KEGG_FILES); # if the conf file is older than 2 months
  return 1 if(isPngValid(getPngFile($pathway)) eq 0); # if the png file cannot be read
  return 0; # in any other case, no need for an update
}

sub restGetToFile {
  my ($url, $toFile) = @_;
  my $file = downloadFile($url);
  move($file, $toFile);
}

sub downloadPathway {
  my ($pathway, $type, $outputFile) = @_;
  my $url = url_exists("$KEGG_URL/get/$pathway/$type") ? "$KEGG_URL/get/$pathway/$type" : "$KEGG_URL/get/map$pathway/$type";
  restGetToFile($url, $outputFile);
}

sub isPngValid {
  my ($pngFile) = @_;
  my ($width, $height) = imgsize($pngFile);
  return 0 if(!$width || !$height);
  return 1;
}

sub updateKeggFile {
  my ($pathway) = @_;
  print "Updating files related to pathway $pathway\n";
  # download all the required files for this pathway
  downloadPathway($pathway, "", getInfoFile($pathway));
  downloadPathway($pathway, "conf", getConfFile($pathway));
  my $pngFile = getPngFile($pathway);
  downloadPathway($pathway, "image", $pngFile);
  # check that the image has been correctly downloaded (limit to 5 tries to avoid infinite loops)
  my $i = 0;
  while(isPngValid($pngFile) ne 1 && $i++ < 5) {
    sleep 2;
    restGetToFile("$KEGG_URL/get/$pathway/image", $pngFile);
  }
}

sub extractInfo {
  my ($pathway) = @_;
  my $file = getInfoFile($pathway);
  open(my $fh, "<", $file) or stderr("Can't open file '$file': $!");
  my $tag = "";
  my %allowedTags = ("ENTRY" => 0, "NAME" => 0, "DESCRIPTION" => 0, "CLASS" => 0, "PATHWAY_MAP" => 0, "ORGANISM" => 0, "REL_PATHWAY" => 0, "KO_PATHWAY" => 0);
  while(<$fh>) {
    chomp;
    last if($_ eq "///"); # end of file
    # store the tag name if there is one (if not, use the previous one)
    $tag = $1 if(m/^([A-Z_]+)\s+/);
    # remove the tag if there is one, and the successive space characters
    s/^$tag//;
    next if(!exists($allowedTags{$tag}));
    s/^\s+//; # remove leading space characters
    s/^([^\s]+)\s\s+(.+)$/$1 [$2]/; # if there is a second column
    # store the values for each tag, consider there can be more than one
    push(@{$PATHWAY_INFO{$pathway}{$tag}}, $_);
  }
  close $fh;
}

sub downloadUpdateGenerate {
  my $i = 0;
  # calculate the total number to search
  my %entriesPerPathway;
  # foreach my $acc (keys(%DATA)) {
  foreach my $acc (keys(%KEGG)) {
    foreach my $keggId (keys(%{$KEGG{$acc}})) {
      foreach my $pathway (@{$KEGG{$acc}{$keggId}}) {
        # $entriesPerPathway{$pathway}{$acc} = 1;
        $entriesPerPathway{$pathway} = 1;
      }
    }
  }
  my $total = scalar(keys(%entriesPerPathway));
  # loop on each kegg entry
  foreach my $pathway (keys(%entriesPerPathway)) {
    # download the corresponding files if they are missing or too old
    updateKeggFile($pathway) if(isFileUpdadeRequired($pathway) eq 1);
    # extract information for this pathway
    extractInfo($pathway);
    # tag to exclude
    my $excludedTag = "";
    $excludedTag = "KO" if($WITH_CONDS eq 1);
    # generate the HTML file
    createHtmlFile(getConfFile($pathway), getPngFile($pathway), $PATHWAY_INFO{$pathway}, getHtmlFile($pathway), \%KEGG, \%DATA, \%STATUS, $WITH_SITES, \%CONDITIONS, $WITH_CONDS, $WITH_STATUS, $excludedTag);
    # keep the pathway in a hash to avoid checking it more than once
    $i++;
    print "$i/$total pathways have been treated\n" if($i % 50 == 0); # show progression
  }
}

sub prepareFormats {
  my ($workbook) = @_;
  # prepare formats
  my %formats;
  $formats{"H"} = $workbook->add_format(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
  $formats{"maps"} = $workbook->add_format(valign => 'top', text_wrap => 1);
  foreach my $status (keys(%STATUS)) {
    $formats{$status} = $workbook->add_format(valign => 'top', bg_color => $STATUS{$status}{"color"});
    $formats{$status."H"} = $workbook->add_format(valign => 'top', bg_color => $STATUS{$status}{"color"}, bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
  }
  return \%formats;
}

sub getKeggRelease {
  my $release = "";
  foreach (split("\n", REST_GET("$KEGG_URL/info/kegg"))) {
    if(m/^kegg\s+Release (.*)$/) {
      $release = $1;
      last;
    }
  }
  return $release;
}

sub addParameterSheet {
  my ($workbook, $formats) = @_;
  my $sheet = addWorksheet($workbook, "Information");
  my $rowNumber = 0;
  writeExcelLine($sheet, $rowNumber++, "Kegg tool version", getVersion());
  writeExcelLine($sheet, $rowNumber++, "Search date", getDate("%Y/%m/%d"));
  writeExcelLine($sheet, $rowNumber++, "Kegg release", getKeggRelease());
  writeExcelLine($sheet, $rowNumber++, "", "Kegg data is updated after $MAX_AGE_IN_DAYS_FOR_KEGG_FILES days, some data may belong to the previous version...");
  writeExcelLine($sheet, $rowNumber++, "UniProt release", getUniprotRelease()) if($IS_UNIPROT eq 1);
  if($PARAMS{"type"}{"statistics"}{"value"} eq "none") {
    writeExcelLine($sheet, $rowNumber++, "Statistical validation", "No statistics");
  } elsif($PARAMS{"type"}{"statistics"}{"value"} eq "pvalue") {
    writeExcelLine($sheet, $rowNumber++, "Statistical validation", "Anova p-values");
  } elsif($PARAMS{"type"}{"statistics"}{"value"} eq "pvalue_fc") {
    writeExcelLine($sheet, $rowNumber++, "Statistical validation", "Anova p-values and Fold Change");
  } elsif($PARAMS{"type"}{"statistics"}{"value"} eq "conditions") {
    writeExcelLine($sheet, $rowNumber++, "Statistical validation", "Anova p-values and multiple conditions each with a Tukey value and a Fold Change");
  }
  writeExcelLine($sheet, $rowNumber++, "Anova p-value threshold", $PARAMS{"thresholds"}{"pvalue"});
  writeExcelLine($sheet, $rowNumber++, "Tukey threshold", $PARAMS{"thresholds"}{"tukey"});
  writeExcelLine($sheet, $rowNumber++, "Fold Change threshold", $PARAMS{"thresholds"}{"fc"});
  if($WITH_STATUS eq 1) {
    writeExcelLine($sheet, $rowNumber++, "", "");
    writeExcelLine($sheet, $rowNumber++, "Status description", "The colors are identical in the HTML files");
    foreach my $status (sort(keys(%STATUS))) {
      $sheet->write($rowNumber, 0, $STATUS{$status}{"text"}, $formats->{$status});
      $sheet->write($rowNumber++, 1, $STATUS{$status}{"description"});
    }
  }
  if(scalar(keys(%DUPLICATE_ENTRIES)) > 0) {
    writeExcelLine($sheet, $rowNumber++, "", "");
    writeExcelLine($sheet, $rowNumber++, "Duplicate entries", "Only the last entry of each duplicate has been considered");
    if($WITH_SITES eq 1) {
      foreach my $id (sort(keys(%DUPLICATE_ENTRIES))) {
        foreach my $site (sort {$a <=> $b} keys(%{$DUPLICATE_ENTRIES{$id}})) {
          my $nb = $DUPLICATE_ENTRIES{$id}{$site} + 1;
          writeExcelLine($sheet, $rowNumber++, "$id at site $site", "x$nb");
        }
      }
    } else {
      foreach my $id (keys(%DUPLICATE_ENTRIES)) {
        my $nb = $DUPLICATE_ENTRIES{$id} + 1;
        writeExcelLine($sheet, $rowNumber++, $id, "x$nb");
      }
    }
  }
  setColumnsWidth($sheet, 25, 10);
  $sheet->activate(); # display this sheet directly when opening the file
}

sub addMapSheet {
  my ($workbook, $formats) = @_;
  my $sheet = addWorksheet($workbook, "Maps");
  
  # print headers
  # in the multi-condition mode: id / condition / status / nb maps / maps
  # default: id / status / nb maps / maps
  my $row = 0; my $col = 0;
  if($IS_UNIPROT eq 1) {
    $sheet->write($row, $col++, "User entry", $formats->{"H"});
    $sheet->write($row, $col++, "UniProt identifier", $formats->{"H"});
  } else {
    $sheet->write($row, $col++, "Identifier", $formats->{"H"});
  }
  $sheet->write($row, $col++, "Site", $formats->{"H"}) if($WITH_SITES eq 1);
  # when there are multiple conditions, add a column for the condition
  $sheet->write($row, $col++, "Condition", $formats->{"H"}) if($WITH_CONDS eq 1);
  $sheet->write($row, $col++, "Status", $formats->{"H"});
  $sheet->write($row, $col++, "# Maps", $formats->{"H"});
  $sheet->write($row++, $col++, "Pathway Map:level_1:level_2", $formats->{"H"});
  $sheet->freeze_panes($row);
  my $nbColumns = $col;
  
  # add the content
  my %entriesPerPathway; # store this relation on the fly, rather than searching in the database or in the files
  my $nbConditions = scalar(keys(%CONDITIONS));
  foreach my $userId (sort(keys(%DATA))) {
    # get pathways
    my @pathways;
    foreach my $keggId (keys(%{$KEGG{$userId}})) {
      foreach my $pathway (@{$KEGG{$userId}{$keggId}}) { # ("path:hsa01100", ...)
        my $name = exists($PATHWAY_INFO{$pathway}{"NAME"}) ? $PATHWAY_INFO{$pathway}{"NAME"}[0] : "";
        my $class = exists($PATHWAY_INFO{$pathway}{"CLASS"}) ? $PATHWAY_INFO{$pathway}{"CLASS"}[0] : "";
        my $map = length($class) == 0 ? "$pathway:$name" : "$pathway:$name:$class";
        push(@pathways, $map);
        $entriesPerPathway{$pathway}{$userId} = 1;
      }
    }
    # write one line per site and condition
    foreach my $site (sort {$a <=> $b} keys(%{$DATA{$userId}})) {
      # if multi-condition mode
        # if all conditions are KO, only print one line
        # else, only print the non-KO lines
      my $isOnlyKO = $WITH_CONDS eq 1 && $NBSTATUS{$userId}{$site}{"KO"} eq $nbConditions ? 1 : 0;
      foreach my $condition (sort(keys(%{$DATA{$userId}{$site}}))) {
        my $status = $DATA{$userId}{$site}{$condition};
        next if($WITH_CONDS && !$isOnlyKO && $status eq "KO"); # only print the non-KO conditions
        my $conditionName = $WITH_CONDS eq 1 && $status ne "KO" ? $CONDITIONS{$condition} : "";
        $col = 0;
        $sheet->write($row, $col++, $userId);
        $sheet->write($row, $col++, $USERID_PER_UNIPROT_ENTRY{$userId}) if($IS_UNIPROT eq 1);
        $sheet->write($row, $col++, $site) if($WITH_SITES eq 1);
        $sheet->write($row, $col++, $conditionName) if($WITH_CONDS eq 1);
        $sheet->write($row, $col++, $STATUS{$status}{"text"}, $formats->{$status});
        $sheet->write($row, $col++, scalar(@pathways));
        $sheet->write($row++, $col++, join("\n", @pathways));
        last if($isOnlyKO); # only print one KO condition
      }
    }
  }
  $sheet->autofilter(0, 0, $row - 1, $nbColumns - 1);
  my @colWidth = (25);
  push(@colWidth, 25) if($IS_UNIPROT eq 1);
  push(@colWidth, 10) if($WITH_SITES eq 1);
  push(@colWidth, 45) if($WITH_CONDS eq 1);
  push(@colWidth, 15, 15, 100);
  setColumnsWidth($sheet, @colWidth);
  return \%entriesPerPathway;
}

sub addPathwaySheet {
  my ($workbook, $entriesPerPathway, $formats) = @_;
  my $sheet = addWorksheet($workbook, "Pathways");
  my $rowNumber = 0;
  my @headers = ("Map", "Name", "Level 1", "Level 2", "Nb identifiers", "Identifiers");
  splice(@headers, 5, 0, "Nb sites") if($WITH_SITES eq 1);
  writeExcelLineF($sheet, $rowNumber++, $formats->{"H"}, @headers);
  $sheet->freeze_panes($rowNumber);
  foreach my $pathway (sort(keys(%$entriesPerPathway))) {
    my $name = exists($PATHWAY_INFO{$pathway}{"NAME"}) ? $PATHWAY_INFO{$pathway}{"NAME"}[0] : "";
    my $class = exists($PATHWAY_INFO{$pathway}{"CLASS"}) ? $PATHWAY_INFO{$pathway}{"CLASS"}[0] : "";
    my ($level1, $level2) = ("", "");
    ($level1, $level2) = split("; ", $class) if(length($class) != 0);
    my @entries = sort(keys(%{$entriesPerPathway->{$pathway}}));
    my $nbSites = 0;
    foreach my $userId (@entries) {
      $nbSites += scalar(keys(%{$DATA{$userId}}));
    }
    my @cells = ("$pathway", $name, $level1, $level2, scalar(@entries), join(", ", sort(@entries)));
    splice(@cells, 5, 0, $nbSites) if($WITH_SITES eq 1);
    writeExcelLine($sheet, $rowNumber++, @cells);
  }
  $sheet->autofilter(0, 0, $rowNumber - 1, $WITH_SITES eq 1 ? 6 : 5);
  if($WITH_SITES eq 1) {
    setColumnsWidth($sheet, 15, 50, 40, 40, 15, 15, 50);
  } else {
    setColumnsWidth($sheet, 15, 50, 40, 40, 15, 50);
  }
}

sub writeExcelOutput {
  my ($inputFile, $outputFile) = @_;
  
  # create file based on the original file (so we do not need to rewrite everything)
  my ($self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputFile);
  $self->parse_template();
  
  # prepare formats
  my $formats = prepareFormats($workbook);
  # add a first sheet with the parameters and global information
  addParameterSheet($workbook, $formats);
  # add a sheet with results per protein/compound
  my $entriesPerPathway = addMapSheet($workbook, $formats);
  # add a sheet with results per pathway
  addPathwaySheet($workbook, $entriesPerPathway, $formats);
  
  # close the workbook
  $workbook->close();
}

sub start {
  # clean stuff just in case
  mkdir($DIR_HTML) unless(-d $DIR_HTML);
  unlink(glob("$DIR_HTML/*"));

  # read the input file
  print "Extracting data from the input file\n";
  extractData();

  # make sure the uniprot identifiers are the good ones
  # what is expected is the Entry, and not the Entry name (ie. P0DPI2 instead of GAL3A_HUMAN)
  # if($IS_UNIPROT eq 1) {
  if($PARAMS{"idtype"} eq "uniprotcheck") {
    print "Retrieve UniProt up-to-date identifiers\n";
    getUniprotEntries();
  } elsif($IS_UNIPROT eq 1) {
    fakeUniprotEntries();
  }

  # prepare the main hashes
  print "Get the updated list of Kegg pathways\n";
  getKeggPathways();
  
  # update the kegg files older than 2 months
  print "Update the required Kegg files and generate the corresponding HTML files\n";
  downloadUpdateGenerate();
  
  # create excel output
  print "Writing final Excel file\n";
  writeExcelOutput($PARAMS{"inputFile"}, $outputFile);

  # compress the HTML folder at the end
  print "Creating zip file with all HTML files\n";
  archive($zipFile, $DIR_HTML);

  # clean stuff at the end
  # unlink(glob("$DIR_HTML/*"));
  # rmdir($DIR_HTML);
}
