#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(archive booleanToString checkUniprotFrom decompressZip extractListEntries getFileNameFromArchive getLinesPerIds parameters stderr);
use LsmboExcel qw(extractIds writeExcelLine writeExcelLineF);
use LsmboRest qw(REST_POST_Uniprot_fasta);
use LsmboMPI;
use LsmboNcbi qw(entrezFetch getNcbiRelease);

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Archive::Zip::MemberRead;
use Cwd 'abs_path';
use File::Copy;
use List::MoreUtils qw(uniq);

my ($paramFile, $outputFile) = @ARGV;

my %PARAMS = %{parameters($paramFile)};
my $version = "fasta36-36.3.8h_04-May-2020";
my $fasta36 = abs_path(dirname(__FILE__))."/$version/bin/fasta36";
$fasta36 .= ".exe" if(!-f $fasta36 && -f "$fasta36.exe"); # windows only
stderr("$fasta36 does not exist !") if(!-f $fasta36);
my $inputCopy = "input.xlsx";
my $databaseVersion = "";

# get fasta version of each protein (use retrieveId service)
my @fastaFiles = convertFasta();
# print Dumper(\@fastaFiles);

# prepare the library in fasta format
my $fastaLibrary = $PARAMS{"fastaLibrary"};
if(-B $fastaLibrary) {
    # the library looks like a zipped file
    my $fastaLibraryName = getFileNameFromArchive($fastaLibrary, "fasta");
    decompressZip($fastaLibrary, $fastaLibraryName);
    $fastaLibrary = $fastaLibraryName;
}

# before running fasta36, read the library to store the protein descriptions
my %descriptions;
open(my $fh, "<", $fastaLibrary) or stderr("Can't read the fasta library: $!");
while(<$fh>) {
    if(m/^>([^\s]*) (.*)/) {
        $descriptions{$1} = $2;
    }
}
close $fh;
print scalar(keys(%descriptions))." proteins in the library\n";

# call in parallel fasta36 for each fa file and compare it to the library
runFasta36($fasta36, $fastaLibrary, @fastaFiles);

# write the output file
writeExcelFile($outputFile);

# archive and clean
if(booleanToString($PARAMS{"keepLogFiles"}) eq "true" && scalar(@ARGV) >= 3) {
    archive($ARGV[2], glob("*.log"));
}
unlink(glob("*.log"));
unlink($inputCopy) if($PARAMS{"proteins"}{"source"} eq "xlsx");
unlink($fastaLibrary) if(-B $PARAMS{"fastaLibrary"});
print "Correct ending of the script\n";

exit;

sub convertFasta {
    my @fastaFiles;
    # temporary files
    my $inputFile = "lsmbo_entries.txt";
    my $fastaInput = "lsmbo_entries.fasta";
    # if we already have a fasta file in input
    if($PARAMS{"proteins"}{"source"} eq "fasta") {
        push(@fastaFiles, $PARAMS{"proteins"}{"fastaFile"});
    } else {
        # otherwise export the list of protein ids into a text file or a string
        if($PARAMS{"proteins"}{"source"} eq "list") {
            extractListEntries($PARAMS{"proteins"}{"proteinList"}, $inputFile);
        } elsif($PARAMS{"proteins"}{"source"} eq "file") {
            $inputFile = $PARAMS{"proteins"}{"proteinFile"};
        } elsif($PARAMS{"proteins"}{"source"} eq "xlsx") {
            # if it's an excel file, copy it locally and extract the ids to a local file
            # copy the excel file locally, otherwise it's not readable (i guess the library does not like files without the proper extension)
            copy($PARAMS{"proteins"}{"excelFile"}, $inputCopy);
            # open the output file
            open(my $fh, ">", $inputFile) or stderr("Can't write to file '$inputFile': $!");
            my @ids = extractIds($inputCopy, $PARAMS{"proteins"}{"sheetNumber"}, $PARAMS{"proteins"}{"cellAddress"}, $inputFile);
            foreach my $id (@ids) {
                print $fh "$id\n";
            }
            close $fh;
        }
        if($PARAMS{"proteins"}{"from"} ne "NCBI") {
            # call uniprot -> fasta
            my $version = REST_POST_Uniprot_fasta($inputFile, checkUniprotFrom($PARAMS{"proteins"}{"from"}), $fastaInput);
            $databaseVersion = "Uniprot release: $version";
        } else {
            # extract the NCBI ids
            my ($ptrFullDataPerLine, $ptrLinesPerId) = getLinesPerIds($inputFile, 1);
            my %linesPerId = %{$ptrLinesPerId};
            my @ids = keys(%linesPerId);
            my @uniqIds = uniq(@ids);
            # call ncbi -> fasta
            entrezFetch("protein", "fasta", "", $fastaInput, @uniqIds);
            $databaseVersion = "NCBI protein database release: ".getNcbiRelease("protein");
        }
        push(@fastaFiles, $fastaInput);
    }
    
    # take all the fasta files and split them in .fa files
    my @faFiles;
    foreach my $fasta (@fastaFiles) {
        my $id = "";
        my $content = "";
        #open(my $fh, "<", $fasta) or stderr("Can't open fasta file $fasta: $!");
        my $fh;
        if(-B $fasta) {
            # file is binary, and the only binary file type we allow in the xml file is zip
            my $zip = Archive::Zip->new($fasta);
            $fh = Archive::Zip::MemberRead->new($zip, getFileNameFromArchive($fasta, "fasta"));
        } else {
            # file is ASCII
            open($fh, "<", $fasta) or stderr("Can't open fasta file $fasta: $!");
        }
        #while(<$fh>) {
        #    if(m/^>([^\s]*)/) {
        while (defined(my $line = $fh->getline())) {
            $line .= "\n" if($line !~ m/\n$/);
            if($line =~ m/^>([^\s]*)/) {
                my $nextId = $1;
                if($id ne "") {
                    push(@faFiles, createFa($id, $content));
                    $content = "";
                }
                $id = $nextId;
            }
            #$content .= $_;
            $content .= $line;
        }
        push(@faFiles, createFa($id, $content)) if($id ne "");
        #close $fh;
        $fh->close();
    }
    
    # remove temporary files
    unlink($inputFile, $fastaInput);
    # return the list of .fa files
    return @faFiles;
}

sub createFa {
    my ($id, $content) = @_;
    $id =~ s/\|/_/g;
    open(my $fh, ">", "$id.fa") or stderr("Can't create file $id.fa: $!");
    print $fh $content;
    close $fh;
    return "$id.fa";
}

sub runFasta36 {
    my ($fasta36, $fastaLibrary, @fastaFiles) = @_;
    my $ktup = 3;
    print "Comparing ".scalar(@fastaFiles)." proteins sequences to the library $fastaLibrary [KTUP=$ktup]\n";
    # prepare the commands to run
    my @commandList;
    foreach(@fastaFiles) {
        my $output = $_;
        $output =~ s/\.fa$/.out/;
        push(@commandList, "$fasta36 -m \"F9 $output\" -T 1 -p $_ $fastaLibrary $ktup > $output.log");
    }
    # run the commands in parallel
    LsmboMPI::runCommandList(0.75, @commandList);
    # delete the .fa files
    unlink(@fastaFiles);
}

sub writeExcelFile {
    my ($outputFile) = @_;
    print "Generation of the final output file\n";

    my $out;
    my $nbResultsPerProtein = $PARAMS{"nb"};
    my $rowNumber = 0;
    my $workbook;
    my $worksheet;
    my @headers = ("Protein query", "Protein match", "Score", "E-value", "Identity", "Similary", "Description", "", $databaseVersion);
    if($PARAMS{"output"}{"format"} eq "xlsx") {
        if($PARAMS{"proteins"}{"source"} ne "xlsx") {
            $workbook = Excel::Writer::XLSX->new($outputFile);
        } else {
            # if the input file is an Excel file, use it as source
            (my $self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputCopy);
            $self->parse_template();
        }

        $worksheet = $workbook->add_worksheet();
        # prepare headers format
        my $formatForHeaders = $workbook->add_format();
        $formatForHeaders->set_format_properties(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
        writeExcelLineF($worksheet, $rowNumber++, $formatForHeaders, @headers);
        $worksheet->freeze_panes(1);
    } else {
        open($out, ">", $outputFile) or stderr("Can't open tsv output file in write mode: $!");
        print $out join("\t", @headers)."\n";
    }

    foreach my $file (glob("*.out")) {
        # get the query
        my $query = $file;
        $query =~ s/.out$//;
        $query =~ s/_/\|/g;
        # only extracts the top $nbResultsPerProtein results
        my $nb = 0;
        open(my $fh, "<", $file) or stderr("Can't read file $file: $!");
        my $skip = 1;
        while(<$fh>) {
            chomp;
            if(m/^The best scores are/) {
                $skip = 0;
                next;
            }
            next if($skip == 1);
            next if(m/^\+\-/);
            if(m/^[a-zA-Z]/ && $nb < $nbResultsPerProtein) {
                # CON_sp|P00760|TRY1_BOVIN Cationic trypsin OS=Bos tauru       ( 246) 1375 472.3 3.2e-136\t0.823 0.970 1375  231    1  231    1  231   16  246    1  246   0   0   0
                # id=TRY1_BOVIN, acc=P00760, score=1375, identity=0.823, similary=0.970, e-value=3.2e-136
                my @items = extractItems($_);
                my $acc = $items[0];
                my @cells = ($query, $acc, $items[2], $items[4], $items[5], $items[6], $descriptions{$acc});
                if($PARAMS{"output"}{"format"} eq "xlsx") {
                    writeExcelLine($worksheet, $rowNumber++, @cells);
                } else {
                    print $out join("\t", @cells)."\n";
                }
                $nb++;
            } else {
                last;
            }
        }
        close $fh;
        unlink($file);
    }

    if($PARAMS{"output"}{"format"} eq "xlsx") {
        $workbook->close();
    } else {
        close $out;
    }
    print "Output file is complete\n";
}

sub extractItems {
    my ($line) = @_;
    my @items;
    # extract protein id
    $line =~ m/^([^\s]*)/;
    push(@items, $1);
    # get and clean right part
    my $right_part = substr($line, 55);
    $right_part =~ s/^\s*\t*//;
    $right_part =~ s/\t/ /g;
    $right_part =~ s/\s+/ /g;
    $right_part =~ s/\(\s*/(/;
    push(@items, split(/[\t\s]/, $right_part));
    return @items;
}

