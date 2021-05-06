#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/..";
use LsmboFunctions;

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};

# read the input file
my $inputFile = "lsmbo_entries.txt";
my $inputCopy = "input.xlsx";
if($PARAMS{"peptides"}{"source"} eq "list") {
    print "Writing the peptide list into a temporary file\n";
    # if it's a id list, put it in a file
    extractListEntries($PARAMS{"peptides"}{"peptideList"}, $inputFile);
} elsif($PARAMS{"peptides"}{"source"} eq "file") {
    print "Using the peptide file as input file\n";
    # if it's a text file, let it be
    $inputFile = $PARAMS{"peptides"}{"peptideFile"};
} elsif($PARAMS{"peptides"}{"source"} eq "xlsx") {
    print "Extracting the peptide list from the Excel file\n";
    # if it's an excel file, copy it locally and extract the ids to a local file
    # copy the excel file locally, otherwise it's not readable (i guess the library does not like files without the proper extension)
    copy($PARAMS{"peptides"}{"excelFile"}, $inputCopy);
    # open the output file
    open(my $fh, ">", "$inputFile") or stderr("Can't write to file '$inputFile': $!", 1);
    my @ids = extractIds($inputCopy, $PARAMS{"peptides"}{"sheetNumber"}, $PARAMS{"peptides"}{"cellAddress"});
    foreach my $id (@ids) {
        print $fh "$id\n";
    }
    close $fh;
}

# extract proteins from the fasta
my %sequences;
my %descriptions;
my $fastaFile = $PARAMS{"fasta"};
open(my $fh, "<", $fastaFile) or stderr("Can't read Fasta file $fastaFile: $!", 1);
my $accession = "";
while(<$fh>) {
    s/\r?\n$//;
    if(m/^>([^\s]+) (.*)/) {
        $accession = $1;
        $descriptions{$accession} = $2;
    } else {
        $sequences{$accession} .= $_;
        $sequences{$accession} .= $_;
    }
}
close $fh;

# writeExcelFile();
# if the input file is an excel file, add the output to the original data (how ??)
print "Writing final Excel file $outputFile\n";
my $workbook;
if($PARAMS{"peptides"}{"source"} ne "xlsx") {
    $workbook = Excel::Writer::XLSX->new($outputFile);
} else {
    # if the input file is an Excel file, use it as source
    (my $self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputCopy);
    $self->parse_template();
}
my $worksheet = $workbook->add_worksheet();

# display headers
my $format = $workbook->add_format();
$format->set_format_properties(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
writeExcelLineF($worksheet, 0, $format, "Peptides", "Nb protein matches", "Protein list");

# check each peptide
my $line = 1;
open($fh, "<", "$inputFile") or stderr("Can't read file '$inputFile': $!", 1);
while(<$fh>) {
    chomp;
    if($_ ne "") {
        foreach my $peptide (split(/[,;]/, $_)) {
            my @relatedProteins = getProteins($peptide);
            writeExcelLine($worksheet, $line++, $peptide, scalar(@relatedProteins), join(";", @relatedProteins));
        }
    }
}
close $fh;
$workbook->close();

print "Correct ending of the script\n";

exit;

sub getProteins {
    my ($peptide) = @_;
    my @proteins;
    foreach my $accession (keys(%sequences)) {
        if(index($sequences{$accession}, $peptide) != -1) {
            push(@proteins, $accession);
        }
    }
    return @proteins;
}

