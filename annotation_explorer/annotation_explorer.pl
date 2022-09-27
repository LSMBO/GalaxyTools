#!/usr/bin/perl
use strict;
use warnings;

use URI::Escape;

use Data::Dumper;
use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(extractListEntries getLinesPerIds parameters randomSubset stderr);
use LsmboExcel qw(extractIds getValue setColumnsWidth writeExcelLine writeExcelLineF);
# use LsmboRest qw(getQuickGOVersion REST_GET REST_POST_Uniprot_tab UNIPROT_RELEASE);
use LsmboRest qw(getQuickGOVersion REST_GET);
use LsmboUniprot qw(REST_POST_Uniprot_tab_legacy UNIPROT_RELEASE);

use File::Copy;
use JSON::XS qw(encode_json decode_json);
use Spreadsheet::Reader::ExcelXML;

my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS;
my %GO;
my %CATEGORIES;

my $defaultCategoryFile = dirname(__FILE__)."/GO_categories.xlsx";

# read parameters
%PARAMS = %{parameters($paramFile)};

# prepare categories
my $addCategories = loadCategories();

# prepare input file
my $inputCopy = "input.xlsx";
my $inputFile = prepareInputFile();

# extract ids and lines
my ($fullDataPerLinePtr, $linesPerIdPtr) = getLinesPerIds($inputFile);
my %fullDataPerLine = %{$fullDataPerLinePtr};
my %linesPerId = %{$linesPerIdPtr};

my $workbook = createExcelFile($outputFile);
if(looksLikeGOTerm($linesPerIdPtr) == 1) {
    print "Input ids look like GO terms\n";
    # just get the list of go terms
    my @goList = keys(%linesPerId);
    # send a request to fill the GO hashmap with all necessary information
    retrieveGoData(@goList);
    # write the excel file
    addGoTermSheet($workbook, "0", $addCategories);
} else {
    print "Input ids are considered to be protein accession numbers\n";
    # send the user file to uniprot and gather information we need
    my ($uniprotData, $goList, $version) = retrieveFromUniprot($inputFile, $PARAMS{"from"});
    # send another request to fill the GO hashmap with all necessary information
    retrieveGoData(@{$goList});
    # write the excel file
    addMainSheet($workbook, $version);
    addProteinSheet($workbook, $uniprotData, $addCategories);
    addGoTermSheet($workbook, "1", $addCategories);
}
$workbook->close();

# clean temp files
unlink($inputFile) if($PARAMS{"proteins"}{"source"} ne "file");
unlink($inputCopy) if(-f $inputCopy);

print "Correct ending of the script\n";

exit;

sub loadCategories {

    # prepare categories
    my $addCategories = 0;
    my $categoryFile = "";
    if($PARAMS{"categories"}{"choice"} eq "file") {
        print "Load user GO categories\n";
        $categoryFile = "UserCategories.xlsx";
        # make sure to copy the file if it comes from the user otherwise the parser may have trouble reading it
        copy($PARAMS{"categories"}{"excelFile"}, $categoryFile);
    } elsif($PARAMS{"categories"}{"choice"} eq "default") {
        print "Load default GO categories\n";
        $categoryFile = $defaultCategoryFile;
    }

    if(-f $categoryFile) {
        # read the category file
        my $parser   = Spreadsheet::Reader::ExcelXML->new();
        my $workbook = $parser->parse($categoryFile);
        stderr($parser->error()) if(!defined $workbook);
        my @worksheets = $workbook->worksheets;
        my $worksheet = $worksheets[0];
        my ($row_min, $row_max) = $worksheet->row_range();
        my $row_start = $row_min + 1; # ignore first line as it must be headers
        for my $row ($row_start .. $row_max) {
            my $name = getValue($worksheet, $row, 0);
            my $go = getValue($worksheet, $row, 1);
            next if($name eq "" || $go eq "");
            # directly put the go as keys and the categories as values
            push(@{$CATEGORIES{$go}}, $name);
        }
        $addCategories = 1;
    }

    return $addCategories;
}

sub prepareInputFile {
    my $inputFile = "lsmbo_entries.txt";
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
        #open(OUT, ">$inputFile") or stderr("Can't write to file '$inputFile'", 1);
        open(my $fh, ">", $inputFile) or stderr("Can't write to file '$inputFile': $!");
        my @ids = extractIds($inputCopy, $PARAMS{"proteins"}{"sheetNumber"}, $PARAMS{"proteins"}{"cellAddress"}, $inputFile);
        foreach my $id (@ids) {
            #print OUT "$id\n";
            print $fh "$id\n";
        }
        #close OUT;
    }
    return $inputFile;
}

sub looksLikeGOTerm {
    my @ids = keys(%{$_[0]});
    # only check 10 random ids
    foreach my $id (randomSubset(10, \@ids)) {
        # print "ABU $id => ".($id !~ m/^GO:\d+$/ ? 0 : 1)."\n";
        return 0 if($id !~ m/^GO:\d+$/);
    }
    return 1;
}

sub retrieveFromUniprot {
    my ($file, $from) = @_;

    # print "Sending protein list $file to Uniprot, identifiers are $from\n";
    print "Sending protein list $file to Uniprot, identifiers are UniProtKB_AC-ID\n";
    my $columns = "id,entry name,protein names,genes(PREFERRED),genes(ALTERNATIVE),organism,go(biological process),go(cellular component),go(molecular function),go-id"; # TODO legacy fields, to be removed
    my @fields = ("accession", "id", "protein_name", "gene_primary", "gene_synonym", "organism_name", "go_p", "go_c", "go_f", "go_id"); # new fields

    my %fullGoList;
    # my %lines = %{REST_POST_Uniprot($file, "tab", $from, "ACC", $columns)};
    my %lines = %{REST_POST_Uniprot_tab_legacy($file, "UniProtKB_AC-ID", \@fields, undef)};
    # print Dumper(\%lines);
    # extract uniprot version
    my $version = delete($lines{UNIPROT_RELEASE()});
    
    # parse output
    foreach my $key (keys(%lines)) {
        my @items = @{$lines{$key}};
        foreach my $go (split("; ", $items[10])) {
            $fullGoList{$go} = 1;
        }
    }
    # foreach my $line (values(%lines)) {
        # my @items = split(/\t/, $line);
        # # items[0] corresponds to the user input
        # foreach my $go (split("; ", $items[8])) {
            # $fullGoList{$go} = 1;
        # }
    # }
    # my @lines = REST_POST_Uniprot($file, "tab", $from, "ACC", $columns);
    # for(my $i = 1; $i < scalar(@lines); $i++) { # skip first line (headers)
        # my @items = split(/\t/, $lines[$i]);
        # foreach my $go (split("; ", $items[8])) {
            # $fullGoList{$go} = 1;
        # }
    # }
    my @lines = values(%lines);
    # return a non-redondant list of GO
    my @goList = sort(keys(%fullGoList));
    # return (\@lines, \@goList, $version);
    return (\%lines, \@goList, $version);
}

sub retrieveGoData {
    my @goList = @_;

    my $nbGO = scalar(@goList);
    print "Sending requests to QuickGO for $nbGO GO\n";
    my $limit = 350;
    my $nbHits = 0;
    for(my $i = 0; $i < scalar(@goList); $i += $limit) {
        my $last = $i + $limit;
        $last = scalar(@goList)-1 if($last > scalar(@goList));
        my @subArray = @goList[$i .. $last];
        $nbHits += retrieveSomeGoData(@subArray);
        sleep(1);
    }
    print "QuickGO returned $nbHits results\n";
}

sub retrieveSomeGoData {
    my @goList = @_;

    my $nbHits = 0;
    if(scalar(@goList) > 0) {
        # send the list of GO to EBI
        my $ids = join("%2C", @goList);
        $ids =~ s/\:/%3A/g;
        my $url = "https://www.ebi.ac.uk/QuickGO/services/ontology/go/terms/$ids/ancestors?relations=is_a%2Cpart_of%2Coccurs_in%2Cregulates";
        my %quickGO = %{decode_json(REST_GET($url))};
        $nbHits = $quickGO{"numberOfHits"};
        foreach my $r (@{$quickGO{"results"}}) {
            my %result = %{$r};
            my $id = $result{"id"};
            $GO{$id}{"name"} = $result{"name"};
            $GO{$id}{"description"} = $result{"definition"}{"text"};
            $GO{$id}{"family"} = formatGoFamily($result{"aspect"});
            $GO{$id}{"ancestors"} = $result{"ancestors"};
        }
    } else {
        print "No GO to search\n";
    }
    return $nbHits;
}

sub formatGoFamily {
    my ($value) = @_;
    return "Biological process" if($value eq "biological_process");
    return "Cellular component" if($value eq "cellular_component");
    return "Molecular function" if($value eq "molecular_function");
    return "";
}

sub getHeaderFormat {
    my ($workbook) = @_;
    my $format = $workbook->add_format();
    $format->set_format_properties(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
    return $format;
}

sub createExcelFile {
    my ($outputFile) = @_;

    print "Generation of the final Excel output file '$outputFile'\n";
    # my $workbook = Excel::Writer::XLSX->new($outputFile);
    my $workbook;
    if($PARAMS{"proteins"}{"source"} ne "xlsx") {
        $workbook = Excel::Writer::XLSX->new($outputFile);
    } else {
        # if the input file is an Excel file, use it as source
        (my $self, $workbook) = Excel::Template::XLSX->new($outputFile, $inputCopy);
        $self->parse_template();
    }
    return $workbook;
}

# sub getQuickGOVersion {
    # my %about = %{decode_json(REST_GET("https://www.ebi.ac.uk/QuickGO/services/ontology/go/about"))};
    # return $about{"go"}{"timestamp"};
# }

sub addMainSheet {
    my ($workbook, $uniprotVersion) = @_;
    my $rowNumber = 0;
    my $worksheet = $workbook->add_worksheet("Information");
    my $format = getHeaderFormat($workbook);
    
    writeExcelLineF($worksheet, $rowNumber++, $format, "Database release", "");
    writeExcelLine($worksheet, $rowNumber++, "Uniprot", $uniprotVersion);
    writeExcelLine($worksheet, $rowNumber++, "QuickGO", getQuickGOVersion());
    $rowNumber++;
    
    writeExcelLineF($worksheet, $rowNumber++, $format, "Links", "");
    writeLineL($worksheet, $rowNumber++, "Uniprot", "https://www.uniprot.org/");
    writeLineL($worksheet, $rowNumber++, "QuickGO", "https://www.ebi.ac.uk/QuickGO/");
    writeLineL($worksheet, $rowNumber++, "Gene Ontology relations", "http://www.geneontology.org/GO.ontology.relations.shtml");
    writeLineL($worksheet, $rowNumber++, "Gene Ontology structure", "http://www.geneontology.org/GO.ontology.structure.shtml");
    $rowNumber++;
    
    writeExcelLineF($worksheet, $rowNumber++, $format, "Column detail", "");
    writeExcelLine($worksheet, $rowNumber++, "Identifier used", "The identifier provided by the user, there can be more than one");
    writeExcelLine($worksheet, $rowNumber++, "Accession number", "The accession number used for this line");
    writeExcelLine($worksheet, $rowNumber++, "Protein name", "The corresponding protein name");
    writeExcelLine($worksheet, $rowNumber++, "Description", "The corresponding protein description");
    writeExcelLine($worksheet, $rowNumber++, "Gene names (primary)", "The recommended name is used to officially represent a gene. However, in many cases, more than one name have been assigned to a specific gene. We therefore make a distinction between the name which we believe should be used as the recommended gene name (official gene symbol) and the other names which we list in the 'Synonyms' subsection");
    writeExcelLine($worksheet, $rowNumber++, "Gene names (synonyms)", "");
    writeExcelLine($worksheet, $rowNumber++, "Organism", "The organism designation consists of the Latin scientific name, usually composed of the genus and species names (the binomial system developed by Linnaeus), followed optionally by the English common name and a synonym.");
    writeExcelLine($worksheet, $rowNumber++, "Categories", "");
    
    writeExcelLine($worksheet, $rowNumber++, "Cellular component ontology", "GO terms directly assigned to a given entry for the Cellular component ontology. It provides known subcellular locations for a given protein.");
    writeExcelLine($worksheet, $rowNumber++, "Cellular component ancestors", "All GO terms in the GO database that are related to the GO terms directly assigned to a given entry, but only considering ascending lineages.");
    writeExcelLine($worksheet, $rowNumber++, "Cellular component graphic tree view", "The URL that allows vizualisation of all GO terms listed in the \"Cellular component ancestors\" column, the GO terms in yellow correspond to the terms in the \"Cellular component ontology\" column. Excel may not make the long URL clickable so you have to copy and paste them in your Web browser.");
    
    writeExcelLine($worksheet, $rowNumber++, "Molecular function ontology", "GO terms directly assigned to a given entry for the Molecular function ontology. It provides known activities of given protein.");
    writeExcelLine($worksheet, $rowNumber++, "Molecular function ancestors", "All GO terms in the GO database that are related to the GO terms directly assigned to a given entry, but only considering ascending lineages.");
    writeExcelLine($worksheet, $rowNumber++, "Molecular function graphic tree view", "The URL that allows vizualisation of all GO terms listed in the \"Molecular function ancestors\" column, the GO terms in yellow correspond to the terms in the \"Molecular function ontology\" column. Excel may not make the long URL clickable so you have to copy and paste them in your Web browser.");
    
    writeExcelLine($worksheet, $rowNumber++, "Biological process ontology", "GO terms directly assigned to a given entry for the Biological process ontology. It provides series of molecular events in which a given protein is involved.");
    writeExcelLine($worksheet, $rowNumber++, "Biological process ancestors", "All GO terms in the GO database that are related to the GO terms directly assigned to a given entry, but only considering ascending lineages.");
    writeExcelLine($worksheet, $rowNumber++, "Biological process graphic tree view", "The URL that allows vizualisation of all GO terms listed in the \"Biological process ancestors\" column, the GO terms in yellow correspond to the terms in the \"Biological process ontology\" column. Excel may not make the long URL clickable so you have to copy and paste them in your Web browser.");
    
    setColumnsWidth($worksheet, 35, 100);
    
}

sub addProteinSheet {
    my ($workbook, $data, $addCategories) = @_;
    
    # my $rowNumber = 0;
    my $worksheet = $workbook->add_worksheet("Proteins");
    
    my @headers = ("Identifier used", "Accession number", "Protein name", "Description", "Gene names (primary)", "Gene names (synonyms)", "Organism");
    push(@headers, "Categories") if($addCategories eq "1");
    push(@headers, "Cellular component ontology", "Cellular component ancestors", "Cellular component graphic tree view",
                   "Molecular function ontology", "Molecular function ancestors", "Molecular function graphic tree view",
                   "Biological process ontology", "Biological process ancestors", "Biological process graphic tree view");
    # push(@headers, UNIPROT_RELEASE().": $uniprotVersion") if($uniprotVersion ne "");
    # my $goVersion = getQuickGOVersion();
    # push(@headers, "QuickGO version: $goVersion") if($version && $version ne "");
    # writeLineFL($worksheet, $rowNumber++, getHeaderFormat($workbook), @headers);
    writeLineFL($worksheet, 0, getHeaderFormat($workbook), @headers);
    
    # write the data
    my %output = %{$data};
    foreach my $key (keys(%output)) {
        next if($key eq UNIPROT_RELEASE());
        my ($user_entry, $entry, $entry_name, $prot_names, $gene_names, $synonyms, $organism, $go_bp, $go_cc, $go_mf, $go_ids) = @{$output{$key}};
        my @biologicalProcess = extractGos($go_bp);
        my @cellularComponent = extractGos($go_cc);
        my @molecularFunction = extractGos($go_mf);
        my @row = ($user_entry, $entry, $entry_name, $prot_names, $gene_names, $synonyms, $organism);
        # list all the categories related to this protein
        if($addCategories eq "1") {
            my %allCategories; # use a hash to avoid redondant categories
            foreach my $go (split("; ", $go_ids)) {
                foreach my $cat (@{$CATEGORIES{$go}}) {
                    $allCategories{$cat} = 1;
                }
                # store a non-redondant list of GO (and the matching proteins too)
                push(@{$GO{$go}{"proteins"}}, $entry);
            }
            push(@row, join("; ", sort(keys(%allCategories))));
        }
        push(@row, $go_cc, getAncestorsToString(@cellularComponent), convertToGraph(@cellularComponent),
                   $go_mf, getAncestorsToString(@molecularFunction), convertToGraph(@molecularFunction),
                   $go_bp, getAncestorsToString(@biologicalProcess), convertToGraph(@biologicalProcess));
        # writeLineL($worksheet, $rowNumber++, @row);
        # replace the user entry by the real one
        # foreach my $rowNumber (@{$linesPerId{$key}}) {
        foreach my $rowNumber (@{$linesPerId{$user_entry}}) {
            $row[0] = $fullDataPerLine{$rowNumber};
            writeLineL($worksheet, $rowNumber+1, @row);
        }
    }
    
    setColumnsWidth($worksheet, 25, 10, 18, 20, 20, 18, 18, 40, 18, 18, 18, 18, 18, 18, 18, 18, 18);
}

sub addGoTermSheet {
    my ($workbook, $addProteins, $addCategories) = @_;

    my $rowNumber = 0;
    my $worksheet = $workbook->add_worksheet("GO terms");
    
    # write the header line
    my @headers = ("GO term", "GO name", "Description", "GO family", "QuickGO link", "QuickGO chart");
    push(@headers, "Matching protein(s)") if($addProteins eq "1");
    push(@headers, "Categories") if($addCategories eq "1");
    writeLineFL($worksheet, $rowNumber++, getHeaderFormat($workbook), @headers);
    
    # print one line per GO
    foreach my $go (sort(keys(%GO))) {
        my $name = $GO{$go}{"name"};
        my $description = $GO{$go}{"description"};
        my $family = $GO{$go}{"family"};
        my $link = "https://www.ebi.ac.uk/QuickGO/term/$go";
        my $chart = "https://www.ebi.ac.uk/QuickGO/services/ontology/go/terms/{ids}/chart?ids=$go&base64=false&showKey=true&showIds=true&showSlimColours=false&showChildren=false";
        my @row = ($go, $name, $description, $family, $link, $chart);
        #push (@row, join(";", sort(@{$GO{$go}{"proteins"}}))) if($addProteins eq "1");
        if($addProteins eq "1") {
            if(exists($GO{$go}{"proteins"})) {
                push (@row, join(";", sort(@{$GO{$go}{"proteins"}})));
            } else {
                push (@row, "");
            }
        }
        if($addCategories eq "1") {
            my %categoriesForCurrentGo;
            foreach my $ancestor (@{$GO{$go}{"ancestors"}}) {
                foreach my $cat (@{$CATEGORIES{$ancestor}}) {
                    $categoriesForCurrentGo{$cat} = 1;
                }
            }
            push(@row, join(";", sort(keys(%categoriesForCurrentGo))));
        }
        writeLineL($worksheet, $rowNumber++, @row);
    }
    
    setColumnsWidth($worksheet, 12, 33, 20, 20, 50, 20, 50, 50);

}

sub writeLineFL {
    my ($sheet, $row, $format, @cells) = @_;
    for(my $i = 0; $i < scalar(@cells); $i++) {
        # $sheet->write($row, $i, $cells[$i], $format);
        my $cell = $cells[$i];
        # no empty cell should be added, filling the cell with a meaningless character (this avoids the left cell to be printed over this cell)
        $cell = "---" if(!$cell || $cell eq "");
        # if the cell is a link, write a regular string to avoid the creation of a hyperlink that may be truncated if the url is too long
        if($cell =~ m/^http:\/\/amigo/) {
            $sheet->write_string($row, $i, $cell, $format);
            #print STDERR "Warning: URL too long for IE at line $row\n" if(length($cell) > 2080);
        } elsif($cell =~ m/^http/) {
            $sheet->write_url($row, $i, $cell, $format);
        } else {
            $sheet->write($row, $i, $cell, $format);
        }
    }
}

sub writeLineL {
    my ($sheet, $row, @cells) = @_;
    writeLineFL($sheet, $row, undef, @cells);
}

sub extractGos {
    my @list = ();
    foreach my $go (split(/; /, $_[0])) {
        $go =~ s/.*\[(.*)\].*/$1/;
        push(@list, $go);
    }
    return @list;
}

sub getAncestorsToString {
    # get the ancestors of each go
    my %joinedAncestors;
    foreach my $go (@_) {
        # add all the ancestors for each GO in a single hash to avoid duplicates
        foreach my $ancestor (@{$GO{$go}{"ancestors"}}) {
            $joinedAncestors{$ancestor} = 1;
        }
    }
    # return a string representation of the ancestors
    return join(";", sort(keys(%joinedAncestors)));
}

sub convertToGraph {
    # get an array with only GOs with prefix and suffix
    my @goPreparedForURL;
    foreach my $go (@_) {
        push(@goPreparedForURL, uri_escape("\"$go\":{\"fill\":\"#ffe333\",\"font\":\"black\"}"));
    }
    if(scalar(@goPreparedForURL) > 0) {
        return "http://amigo.geneontology.org/visualize?term_data_type=json&mode=amigo&term_data={".join(",", @goPreparedForURL)."}&format=png&mode=basic&term_data_type=json";
    }
    # return an blank string if the go list is empty
    return "";
}

