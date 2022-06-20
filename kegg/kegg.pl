#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use Image::Size;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(archive booleanToString getDate getVersion parameters stderr);
use LsmboExcel qw(addWorksheet getValue setColumnsWidth writeExcelLine writeExcelLineF);
use LsmboRest qw(downloadFile REST_GET REST_POST_Uniprot_tab UNIPROT_RELEASE);
use lib dirname(__FILE__);
use HtmlGenerator qw(createHtmlFile);

use File::Copy;
use Scalar::Util qw(looks_like_number);
use URL::Exists qw(url_exists);

# $inputFile must contain protein accession numbers, p-value, fc, tukey
# $anova, $fc, $tukey are threshold values
my ($paramFile, $outputFile, $zipFile) = @ARGV;

# set global variables here
my %PARAMS = %{parameters($paramFile)};
my $IS_UNIPROT = $PARAMS{"type"} eq "uniprot" ? 1 : 0;
my $WITH_SITES = booleanToString($PARAMS{"withSites"}) eq "true" ? 1 : 0;

# database directories
my $BINARIES_DIRECTORY = dirname(__FILE__);
my $DIR_CONF = "$BINARIES_DIRECTORY/conf";
my $DIR_INFO = "$BINARIES_DIRECTORY/info";
my $DIR_PNG = "$BINARIES_DIRECTORY/map";
my $DIR_HTML = "html";

# other data
my $TAXONOMY = "map"; # default value
my $KEGG_URL = "https://rest.kegg.jp";
my $MAX_AGE_IN_DAYS_FOR_KEGG_FILES = 30 * 2; # 2 months max
my $FORCE_FILE_UPDATE = 0;
my %STATUS = ("KO" => {"id" => 1, "text" => "Does not satisfy p-value criteria", "color" => "#ffe333", "symbol" => "\\2716", "html" => "&#10006;"}, # yellow
              "OK" => {"id" => 2, "text" => "Satisfies p-value criteria", "color" => "#428fd3", "symbol" => "\\2714", "html" => "&#10004;"}, # blue
              "UP" => {"id" => 3, "text" => "Upregulated", "color" => "#ff4c33", "symbol" => "\\2191", "html" => "&#8593;"}, # red
              "DO" => {"id" => 4, "text" => "Downregulated", "color" => "#53c326", "symbol" => "\\2193", "html" => "&#8595;"}); # green

# data
my %DATA; # $DATA{userId_i}{site_j} = status_key
my %USERID_PER_UNIPROT_ENTRY; # map between the user input ids and the corresponding Uniprot Entry
my %KEGG; # $KEGG{userId_i}{keggId} = array(pathway)
my %PATHWAY_INFO; # $PATHWAY_INFO{pathway}{"name"} = name, $PATHWAY_INFO{pathway}{"class"} = class

start();
print "Correct ending of the script\n";

exit;

# extraction of the value, but there may not be any value in the file
sub getExcelValue {
  my ($worksheet, $row, $nbColumns, $column) = @_;
  $column += $WITH_SITES;
  my $value = $nbColumns >= $column ? getValue($worksheet, $row, $column) : "";
  return looks_like_number($value) ? $value : 1000000; # use a very large integer
}

sub getStatus {
  my ($worksheet, $row, $nbColumns) = @_;
  my $anova = getExcelValue($worksheet, $row, $nbColumns, 1);
  my $fc = getExcelValue($worksheet, $row, $nbColumns, 2);
  my $tukey = getExcelValue($worksheet, $row, $nbColumns, 3);
  
  if($PARAMS{"Statistics"}{"value"} eq "anova_only" && $anova < $PARAMS{"Statistics"}{"anova"}) {
    return "OK";
  } elsif($PARAMS{"Statistics"}{"value"} eq "anova_fc" && $anova < $PARAMS{"Statistics"}{"anova"}) {
    return "UP" if($fc > $PARAMS{"Statistics"}{"fc"});
    return "DO" if($fc < -$PARAMS{"Statistics"}{"fc"});
    return "OK";
  } elsif($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey" && $anova < $PARAMS{"Statistics"}{"anova"} && $tukey < $PARAMS{"Statistics"}{"tukey"}) {
    # TODO test with tukey
    return "UP" if($fc > $PARAMS{"Statistics"}{"fc"});
    return "DO" if($fc < -$PARAMS{"Statistics"}{"fc"});
    return "OK";
  }
  return "KO";
}

sub extractData {
  # make a copy of the file, otherwise the XLSX parser may fail
  my $inputFile = "input.xlsx";
  copy($PARAMS{"inputFile"}, $inputFile);

  # open the excel file
  my $parser = Spreadsheet::ParseXLSX->new;
  my $workbook = $parser->parse($inputFile);
  stderr($parser->error()."\n") if(!defined $workbook);

  my @worksheets = $workbook->worksheets;
  my $worksheet = $worksheets[0];
  my ($row_min, $row_max) = $worksheet->row_range();
  my ($col_min, $col_max) = $worksheet->col_range();
  
  # skip header line
  my $nbRows = 0;
  for my $row ($row_min + 1 .. $row_max) {
    my $id = getValue($worksheet, $row, 0);
    my $site = $WITH_SITES eq 1 ? getValue($worksheet, $row, 1) : 1;
    next if($id eq "" || $site eq "");
    $DATA{$id}{$site} = getStatus($worksheet, $row, $col_max);
    $nbRows++;
  }

  print "$nbRows rows have been read\n";
}

sub getUniprotEntries {
  # put the ids in a text file
  my $tempFile = "uniprot_temp_ids.txt";
  open(my $tmp, '>', $tempFile) or stderr("Unable to create a temporary file for Uniprot conversion");
  foreach (keys(%DATA)) { print $tmp "$_\n"; }
  close $tmp;
  # ask uniprot for the corresponding Entry (id)
  my %output = %{REST_POST_Uniprot_tab($tempFile, "ACC+ID", "id")};
  # extract uniprot version
  my $version = delete($output{UNIPROT_RELEASE()});
  # replace the keys in %DATA
  foreach my $userEntry (keys(%DATA)) {
    my $uniprotEntry = ${$output{$userEntry}}[1];
    $USERID_PER_UNIPROT_ENTRY{$uniprotEntry} = $userEntry;
    if($uniprotEntry ne $userEntry) {
      $DATA{$uniprotEntry} = $DATA{$userEntry};
      delete($DATA{$userEntry});
    }
  }
  # delete the temp file
  unlink $tempFile;
}

sub detectTaxonomy {
  if($IS_UNIPROT eq 1) {
    # use the REST api with each protein until one protein matches a taxonomy (hopefully the first one!)
    foreach my $protein (keys(%DATA)) {
      my $output = REST_GET("$KEGG_URL/conv/genes/up:$protein");
      # expected result: up:O14683\thsa:9537
      if($output =~ m/.+\t(.+):.+$/) {
        $TAXONOMY = $1;
        print "Taxonomy is '$TAXONOMY'\n";
        return;
      }
    }
    stderr("Unable to determine taxonomy from the protein IDs");
  } else {
    print "No taxonomy required for compound entries\n";
  }
}

sub getKeggIdsAndPathways {
  # get the updated list of Kegg ids
  if($IS_UNIPROT eq 1) {
    # ${userId_i}{keggId} = array(pathway)
    my @keggIds = split(/\n/, REST_GET("$KEGG_URL/conv/$TAXONOMY/uniprot"));
    # returns lines formatted as: "up:Q96QH8\thsa:729201"
    foreach my $line (@keggIds) {
      my ($acc, $keggId) = split(/\t/, $line);
      $acc =~ s/up://;
      next if(!exists($DATA{$acc}));
      $KEGG{$acc}{$keggId} = ();
    }
  } else {
    # special case for compounds, they replace the entries and the kegg ids
    # $KEGG{userId_i}{keggId} = array()
    foreach my $compoundId (keys(%DATA)) {
      $KEGG{$compoundId}{$compoundId} = ();
    }
  }
  # get the updated list of Kegg pathways
  my $taxonomy = $IS_UNIPROT eq 1 ? $TAXONOMY : "compound";
  my @pathways = split(/\n/, REST_GET("$KEGG_URL/link/pathway/$taxonomy"));
  # returns lines formatted as: "hsa:6484\tpath:hsa01100" or "cpd:C00022\tpath:map00010"
  my %pathways;
  foreach my $line (@pathways) {
    my ($id, $pathway) = split(/\t/, $line);
    $id =~ s/^cpd://;
    push(@{$pathways{$id}}, $pathway);
  }
  # associate the pathways to the entries in %KEGG
  foreach my $acc (keys(%KEGG)) {
    foreach my $keggId (keys(%{$KEGG{$acc}})) {
      if(exists($pathways{$keggId})) { # it should always exist !!
        # $KEGG{$acc}{$keggId} = $pathways{$keggId};
        my $pathway = $pathways{$keggId};
        $KEGG{$acc}{$keggId} = $pathway;
        # prepare this hash for later
        $PATHWAY_INFO{$pathway}{"name"} = "";
        $PATHWAY_INFO{$pathway}{"class"} = "";
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
  my $url = url_exists("$KEGG_URL/get/$TAXONOMY$pathway/$type") ? "$KEGG_URL/get/$TAXONOMY$pathway/$type" : "$KEGG_URL/get/map$pathway/$type";
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
    restGetToFile("$KEGG_URL/get/$TAXONOMY$pathway/image", $pngFile);
  }
}

sub extractInfo {
  my ($pathway) = @_;
  my $file = getInfoFile($pathway);
  open(my $fh, "<", $file) or stderr("Can't open file '$file': $!");
  my $name = "";
  my $class = "";
  while(<$fh>) {
    chomp;
    $PATHWAY_INFO{$pathway}{"name"} = $1 if(m/^NAME\s+(.*)/);
    $PATHWAY_INFO{$pathway}{"class"} = $1 if(m/^CLASS\s+(.*)/);
    last if(exists($PATHWAY_INFO{$pathway}{"name"}) && exists($PATHWAY_INFO{$pathway}{"class"}));
  }
  close $fh;
}

sub downloadUpdateGenerate {
  my %pathways;
  my $i = 0;
  my $total = scalar(keys(%PATHWAY_INFO));
  foreach my $acc (keys(%KEGG)) {
    foreach my $keggId (keys(%{$KEGG{$acc}})) {
      foreach my $pathway (@{$KEGG{$acc}{$keggId}}) {
        $pathway =~ s/path:$TAXONOMY//;
        if(!exists($pathways{$pathway})) {
          # download the corresponding files if they are missing or too old
          updateKeggFile($pathway) if(isFileUpdadeRequired($pathway) eq 1);
          # extract information for this pathway
          extractInfo($pathway);
          # generate the HTML file
          createHtmlFile(getConfFile($pathway), getPngFile($pathway), $PATHWAY_INFO{$pathway}{"name"}, getHtmlFile($pathway), \%KEGG, \%DATA, \%STATUS, $WITH_SITES);
          # keep the pathway in a hash to avoid checking it more than once
          $pathways{$pathway} = 1;
          $i++;
          print "$i/$total pathways have been treated\n" if($i % 50 == 0); # show progression
        }
      }
    }
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
  }
  return \%formats;
}

sub addParameterSheet {
  my ($workbook) = @_;
  my $sheet = addWorksheet($workbook, "Parameters");
  my $rowNumber = 0;
  writeExcelLine($sheet, $rowNumber++, "Version", getVersion());
  writeExcelLine($sheet, $rowNumber++, "Date", getDate("%Y/%m/%d"));
  writeExcelLine($sheet, $rowNumber++, "P-value threshold", $PARAMS{"Statistics"}{"anova"}) unless($PARAMS{"Statistics"}{"value"} eq "none");
  writeExcelLine($sheet, $rowNumber++, "Fold Change threshold", $PARAMS{"Statistics"}{"fc"}) if($PARAMS{"Statistics"}{"value"} eq "anova_fc" || $PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
  writeExcelLine($sheet, $rowNumber++, "Tukey threshold", $PARAMS{"Statistics"}{"tukey"}) if($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
  setColumnsWidth($sheet, 25, 10);
  $sheet->activate(); # display this sheet directly when opening the file
}

sub addMapSheet {
  my ($workbook, $formats) = @_;
  my $sheet = addWorksheet($workbook, "Maps");
  my $rowNumber = 0;
  my @headers = $IS_UNIPROT eq 1 ? ("User entry", "UniProt identifier") : ("Identifier");
  push(@headers, "Site") if($WITH_SITES eq 1);
  push(@headers, ("Status", "# Maps", "Pathway Map:level_1:level_2"));
  writeExcelLineF($sheet, $rowNumber++, $formats->{"H"}, @headers);
  $sheet->freeze_panes($rowNumber);
  # loop on %DATA ($DATA{userId_i}{site} = status_key) and %KEGG ($KEGG{userId_i}{keggId} = array(pathway))
  my %entriesPerPathway; # store this relation on the fly, rather than searching in the database or in the files
  foreach my $userId (sort(keys(%DATA))) {
    # get pathways
    my @pathways;
    foreach my $keggId (keys(%{$KEGG{$userId}})) {
      foreach my $pathway (@{$KEGG{$userId}{$keggId}}) { # ("path:hsa01100", ...)
        my $name = exists($PATHWAY_INFO{$pathway}{"name"}) ? $PATHWAY_INFO{$pathway}{"name"} : "";
        my $class = exists($PATHWAY_INFO{$pathway}{"class"}) ? $PATHWAY_INFO{$pathway}{"class"} : "";
        my ($num) = $pathway =~ /(\d+)/;
        my $map = length($class) == 0 ? "map:$num:$name" : "map:$num:$name:$class";
        push(@pathways, $map);
        $entriesPerPathway{$pathway}{$userId} = 1;
      }
    }
    # write one line per site
    foreach my $site (keys(%{$DATA{$userId}})) {
      my $status = $DATA{$userId}{$site};
      my @cells = $IS_UNIPROT eq 1 ? ($userId, $USERID_PER_UNIPROT_ENTRY{$userId}) : ($userId);
      push(@cells, $site) if($WITH_SITES eq 1);
      push(@cells, "", scalar(@pathways), join("\n", @pathways));
      writeExcelLineF($sheet, $rowNumber, $formats->{"maps"}, @cells);
      $sheet->write($rowNumber++, $IS_UNIPROT eq 1 ? 3 : 2, $STATUS{$status}{"text"}, $formats->{$status});
    }
  }
  $sheet->autofilter(0, 0, $rowNumber - 1, scalar(@headers) - 1);
  my @colWidth = (25, 30, 15, 100);
  splice(@colWidth, 1, 0, 10) if($WITH_SITES eq 1); # add the value for the 'site' column if the column is present
  unshift(@colWidth, 25) if($IS_UNIPROT eq 1); # add the value at the beginning of the array
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
    my ($num) = $pathway =~ /(\d+)/;
    my $name = exists($PATHWAY_INFO{$pathway}{"name"}) ? $PATHWAY_INFO{$pathway}{"name"} : "";
    my $class = exists($PATHWAY_INFO{$pathway}{"class"}) ? $PATHWAY_INFO{$pathway}{"class"} : "";
    my ($level1, $level2) = ("", "");
    ($level1, $level2) = split("; ", $class) if(length($class) != 0);
    my @entries = sort(keys(%{$entriesPerPathway->{$pathway}}));
    my $nbSites = 0;
    foreach my $userId (@entries) {
      $nbSites += scalar(keys(%{$DATA{$userId}}));
    }
    my @cells = ("$TAXONOMY$num", $name, $level1, $level2, scalar(@entries), join(", ", sort(@entries)));
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
  getUniprotEntries() if($IS_UNIPROT eq 1);

  # detect the taxonomy based on the first protein ID
  print "Detecting the taxonomy...\n";
  detectTaxonomy();
  
  # prepare the main hashes
  print "Get the updated list of Kegg pathways\n";
  getKeggIdsAndPathways();
  
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
  unlink(glob("$DIR_HTML/*"));
  rmdir($DIR_HTML);
}
