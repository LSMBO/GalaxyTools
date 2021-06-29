#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(booleanToString checkUniprotFrom decompressGunzip extractListEntries getLinesPerIds parameters stderr);
use LsmboExcel qw(extractIds setColumnsWidth writeExcelLine writeExcelLineF);
use LsmboNcbi qw(entrezFetch getNcbiRelease);
use LsmboRest qw(downloadFile REST_POST_Uniprot_tab UNIPROT_RELEASE);

use File::Copy;
use List::MoreUtils qw(uniq);

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my %MONTH = ( JAN => 1, FEB => 2, MAR => 3, APR => 4, MAY => 5, JUN => 6, JUL => 7, AUG => 8, SEP => 9, OCT => 10, NOV => 11, DEC => 12 );
my $addOrthoDb = "false";
$addOrthoDb = booleanToString($PARAMS{"identifierTypes"}{"addOrthoDb"}) if($PARAMS{"identifierTypes"}{"from"} ne "NCBI");
my $addInterPro = "false";
$addInterPro = booleanToString($PARAMS{"identifierTypes"}{"addInterPro"}) if($PARAMS{"identifierTypes"}{"from"} ne "NCBI");

# download and parse orthodb file if requested
my %orthodb;
if($addOrthoDb eq "true") {
  # eventually get the file name from https://v101.orthodb.org/download/README.txt in case it has changed
  my $file = "odb10v1_OGs.tab";
  print "Downloading OrthoDB file '$file'\n";
  # system("wget https://v101.orthodb.org/download/$file.gz");
  downloadFile("https://v101.orthodb.org/download/$file.gz");
  # system("gunzip $file.gz");
  decompressGunzip("$file.gz");
  open(my $fh, "<", "$file") or stderr("Can't open OrthoDB file '$file': $!");
  while(<$fh>) {
    chomp;
    my ($id, $level, $name) = split(/\t/);
    $orthodb{$id} = $name;
  }
  close $fh;
  unlink ($file);
  unlink ("$file.gz") if(-f "$file.gz");
}
# download and parse interpro file if requested
my %interpro;
if($addInterPro eq "true") {
  my $file = "entry.list";
  print "Downloading InterPro file '$file'\n";
  # system("wget ftp://ftp.ebi.ac.uk/pub/databases/interpro/$file");
  downloadFile("ftp://ftp.ebi.ac.uk/pub/databases/interpro/$file");
  open(my $fh, "<", "$file") or stderr("Can't open InterPro file '$file': $!");
  while(<$fh>) {
    chomp;
    my ($id, $type, $name) = split(/\t/);
    $interpro{$id} = $name;
  }
  close $fh;
  unlink($file);
}

# check input data
my $inputFile = "lsmbo_entries.txt";
my $inputCopy = "input.xlsx";
if($PARAMS{"proteins"}{"source"} eq "list") {
    # if it's a id list, put it in a file
    extractListEntries($PARAMS{"proteins"}{"proteinList"}, $inputFile);
} elsif($PARAMS{"proteins"}{"source"} eq "file") {
    # if it's a text file, let it be
    $inputFile = $PARAMS{"proteins"}{"proteinFile"};
} elsif($PARAMS{"proteins"}{"source"} eq "xlsx") {
    # if it's an excel file, copy it locally and extract the ids to a local file
    # copy the excel file locally, otherwise it's not readable (i guess the library does not like files without the proper extension)
    copy($PARAMS{"proteins"}{"excelFile"}, $inputCopy);
    # open the output file
    open(my $fh, ">", "$inputFile") or stderr("Can't write to file '$inputFile'");
    my @ids = extractIds($inputCopy, $PARAMS{"proteins"}{"sheetNumber"}, $PARAMS{"proteins"}{"cellAddress"}, $inputFile);
    foreach my $id (@ids) {
        print $fh "$id\n";
    }
    close $fh;
}

# extract ids and lines
my ($fullDataPerLinePtr, $linesPerIdPtr) = getLinesPerIds($inputFile, ($PARAMS{"proteins"}{"source"} ne "xlsx"));
my %fullDataPerLine = %{$fullDataPerLinePtr};
my %linesPerId = %{$linesPerIdPtr};

my %output;
if($PARAMS{"identifierTypes"}{"from"} ne "NCBI") {
    # Retrieve protein information from Uniprot website
    my $columns = "id,entry name,reviewed,protein names,organism-id,genes(PREFERRED),ec";
    $columns .= ",database(GeneID),created,last-modified,sequence-modified";
    $columns .= ",database(OrthoDB)" if($addOrthoDb eq "true");
    $columns .= ",database(InterPro)" if($addInterPro eq "true");

    # add the organism id if provided
    my $taxo = "";
    $taxo = $PARAMS{"identifierTypes"}{"organism"} if(exists($PARAMS{"identifierTypes"}{"organism"}));
    %output = %{REST_POST_Uniprot_tab($inputFile, checkUniprotFrom($PARAMS{"identifierTypes"}{"from"}), $columns, $taxo)};
} else {
    # put the ids in an array
    my @ids = keys(%linesPerId);
    my @uniqIds = uniq(@ids);
    my $tempFile = "entrez.tmp";
    entrezFetch("protein", "gp", "xml", $tempFile, @uniqIds);
    open(my $fh, "<", $tempFile) or stderr("Can't open Entrez output: $!");
    my @items;
    my $i = 0;
    while(<$fh>) {
        if(m/^[\t\s]*<GBSeq>[\t\s]*$/) { @items = ();
        } elsif(m/<GBSeq_locus>(.*)<\/GBSeq_locus>/) { $items[1] = $1;
        } elsif(m/<GBSeq_accession-version>(.*)<\/GBSeq_accession-version>/) { $items[2] = $1;
        } elsif(m/<GBSeq_definition>(.*)<\/GBSeq_definition>/) { $items[3] = $1;
        } elsif(m/<GBSeq_create-date>(.*)<\/GBSeq_create-date>/) { $items[9] = formatNcbiDate($1);
        } elsif(m/<GBSeq_update-date>(.*)<\/GBSeq_update-date>/) { $items[10] = formatNcbiDate($1);
        } elsif(m/<GBSeq_comment>([^\.]*\.).*<\/GBSeq_comment>/) { $items[4] = $1;
        } elsif(m/<GBSeq_organism>(.*)<\/GBSeq_organism>/) { $items[5] = $1;
        } elsif(m/<GBQualifier_name>gene<\/GBQualifier_name>/) { $items[6] = "#####";
        } elsif(m/<GBQualifier_value>(.*)<\/GBQualifier_value>/ && $items[6] && $items[6] eq "#####") { $items[6] = $1;
        } elsif(m/<GBQualifier_value>GeneID:(.*)<\/GBQualifier_value>/) { $items[7] = $1;
        } elsif(m/<GBSeq_source-db>(.*)<\/GBSeq_source-db>/) { $items[8] = $1;
        } elsif(m/^[\t\s]*<\/GBSeq>[\t\s]*$/) {
            my @array = @items; # we make a copy of the array so that we store a different pointer each time
            $output{$ids[$i++]} = \@array; # ncbi output is in the same order as the input array @ids
        }
    }
    close $fh;
    unlink $tempFile;
}

print "Write Uniprot results into an Excel file\n";
# if the input file is an excel file, add the output to the original data (how ??)
my $workbook;
if($PARAMS{"proteins"}{"source"} ne "xlsx") {
    $workbook = Excel::Writer::XLSX->new($outputFile);
} else {
    # if the input file is an Excel file, use it as source
    (my $self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputCopy);
    $self->parse_template();
}
my $worksheet = $workbook->add_worksheet();
# prepare headers format
my $formatForHeaders = $workbook->add_format();
$formatForHeaders->set_format_properties(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
# print formated header line
my @headers;
# also prepare date format
my @dateCellIds;
my $formatForDates = $workbook->add_format( num_format => 'd mmmm yyyy' ); # 2 Feb 2002
if($PARAMS{"identifierTypes"}{"from"} ne "NCBI") {
    @headers = ("User entry", "Entry", "Entry name", "Reviewed", "Description", "Organism", "Gene name", "EC number");
    push(@headers, "GeneId", "Creation date", "Last update", "Last sequence update");
    push(@headers, "OrthoDB orthologous groups") if($addOrthoDb eq "true");
    push(@headers, "InterPro family identifiers", "InterPro family names") if($addInterPro eq "true");
    push(@headers, UNIPROT_RELEASE().": ".$output{UNIPROT_RELEASE()}) if(exists($output{UNIPROT_RELEASE()}));
    @dateCellIds = (9, 10, 11);
} else {
    @headers = ("User entry", "Locus", "Identifier", "Description", "Reviewed", "Organism", "Gene name", "GeneId", "Source", "Creation date", "Last update", "NCBI protein database release: ".getNcbiRelease("protein"));
    @dateCellIds = (9, 10);
}
writeExcelLineF($worksheet, 0, $formatForHeaders, @headers);

# parse lines
foreach my $key (keys(%output)) {
    next if($key eq UNIPROT_RELEASE());
    my @cells = @{$output{$key}};
    if($PARAMS{"identifierTypes"}{"from"} ne "NCBI") {
        # we need to adjust the dates for excel: 2021-04-07 -> 2021-04-07T
        $cells[9] .= "T";
        $cells[10] .= "T";
        $cells[11] .= "T";
    }
    # format orthoDB data if requested
    if($addOrthoDb eq "true") {
        my $orthoId = 12;
        if($cells[$orthoId] ne "") {
            my @orthoNames;
            foreach my $oid (split(";", $cells[$orthoId])) {
              push(@orthoNames, "$oid:".$orthodb{$oid}) if(exists($orthodb{$oid}));
            }
            $cells[$orthoId] = join("\n", @orthoNames);
        }
    }
    # format interpro data if requested
    if($addInterPro eq "true") {
        my $interId = ($addOrthoDb eq "true" ? 13 : 12);
        if($cells[$interId] ne "") {
            my @ids; my @names;
            foreach my $id (split(";", $cells[$interId])) {
                push(@ids, $id);
                push(@names, (exists($interpro{$id}) ? $interpro{$id} : ""));
            }
            $cells[$interId] = join(";", @ids);
            push(@cells, join(";", @names));
        }
    }
    # replace the user entry by the real one
    foreach my $rowNumber (@{$linesPerId{$key}}) {
        $cells[0] = $fullDataPerLine{$rowNumber};
        writeExcelLine($worksheet, $rowNumber+1, @cells);
        #writeExcelLineT($worksheet, $rowNumber+1, $types, @cells);
        # rewrite the date cells with a date format
        foreach my $col (@dateCellIds) {
            $worksheet->write_date_time($rowNumber+1, $col, $cells[$col], $formatForDates);
        }
    }
    delete($linesPerId{$key});
}

# add the remaining lines that should only correspond to the ids without any match
foreach my $key (keys(%linesPerId)) {
    foreach my $rowNumber (@{$linesPerId{$key}}) {
        my $cell = $fullDataPerLine{$rowNumber};
        writeExcelLine($worksheet, $rowNumber+1, $cell);
    }
}

# add column sizes
if($PARAMS{"identifierTypes"}{"from"} ne "NCBI") {
    setColumnsWidth($worksheet, 25, 15, 15, 10, 15, 10, 15, 10, 10, 20, 20, 20, 30, 30, 30, 30);
} else {
    setColumnsWidth($worksheet, 15, 15, 15, 15, 15, 15, 15, 10, 15, 20, 20, 50);
}
my $nbRows = scalar(keys(%fullDataPerLine));
print "$nbRows lines have been written to the Excel file\n";
$worksheet->autofilter(0, 0, $nbRows, scalar(@headers)-2);
$worksheet->freeze_panes(1);
$workbook->close();
print "Excel file is complete\n";
unlink($inputFile) if($PARAMS{"proteins"}{"source"} ne "file");
unlink($inputCopy) if($PARAMS{"proteins"}{"source"} eq "xlsx");

print "Correct ending of the script\n";

exit;

sub formatNcbiDate {
    my ($dateStr) = @_;
    # input format: 21-NOV-2020
    my @items = split("-", $dateStr);
    my $m = $MONTH{$items[1]};
    $m = "0$m" if($m < 10);
    # output format: 2020-11-21T
    return $items[2]."-$m-".$items[0]."T";
}

