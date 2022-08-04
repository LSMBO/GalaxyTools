#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(parameters stderr);
# use LsmboRest qw(getQuickGOVersion REST_GET REST_GET_Uniprot);
use LsmboRest qw(getQuickGOVersion REST_GET_Uniprot);
use LsmboUniprot qw(searchEntries);

use File::Path qw(make_path remove_tree);

# my ($taxonomyId, $source, $outputFile) = @ARGV;
my ($paramFile, $outputFile) = @ARGV;

# global variables
my %PARAMS = %{parameters($paramFile)};
my %DATA;
my %PROTEIN_NAME; # accession number => protein name
my %GO_NAMES; # GO id => GO name, ie. GO:0004198 => "calcium-dependent cysteine-type endopeptidase activity"
my %GO_TYPES; # GO id => category, ie. GO:0004198 => "BP"
my %KEGG_NAMES; # pathway id => pathway name, ie. hsa04610 => "Complement and coagulation cascades"
my %KEGG_LINKS; # Kegg id => array of pathway ids, ie. hsa71 => (hsa04015, hsa04145, hsa04210, hsa04390, ...)

# download data
my $taxonomyId = $PARAMS{"taxonomy"}{"taxo"};
$taxonomyId = $PARAMS{"taxonomy"}{"taxo_id"} if($taxonomyId eq "Other");
my ($taxonomyName, $taxonomyFullName, $uniprotVersion) = getUniprotTaxonomyNames($taxonomyId);
getUniprotData($taxonomyId, $PARAMS{"source"});
my @geneIds = sort { $a <=> $b } keys(%DATA);

# extract the kegg taxonomy from %DATA
my $keggTaxonomy = getKeggTaxonomy();
getKeggPathways($keggTaxonomy);
linkKeggPathways($keggTaxonomy);

# clean directory if any
remove_tree("./$taxonomyName");
unlink($outputFile) if(-f $outputFile);

# generate file EASE/Data/Gene Symbol.txt
my $out = createFile("./$taxonomyName/Ease/Data/Gene Symbol.txt");
foreach my $geneId (@geneIds) {
    print $out "$geneId\t".$DATA{$geneId}{"symbol"}."\n";
}
close($out);

# generate file EASE/Data/GOID.txt
$out = createFile("./$taxonomyName/Ease/Data/GOID.txt");
foreach my $geneId (@geneIds) {
    foreach my $go (sort(@{$DATA{$geneId}{"go"}})) {
        print $out "$geneId\t$go\n";
    }
}
close($out);

# generate file EASE/Data/Convert/SwissProt identifiers.txt
$out = createFile("./$taxonomyName/Ease/Data/Convert/SwissProt identifiers.txt");
foreach my $geneId (@geneIds) {
    print $out "$geneId\t".$PROTEIN_NAME{$DATA{$geneId}{"acc"}}."\n";
}
close($out);

# generate file EASE/Data/Convert/SwissProt accession.txt
$out = createFile("./$taxonomyName/Ease/Data/Convert/SwissProt accession.txt");
foreach my $geneId (@geneIds) {
    print $out "$geneId\t".$DATA{$geneId}{"acc"}."\n";
}
close($out);

# generate file EASE/Data/Class/GO Biological Process.txt
$out = createFile("./$taxonomyName/Ease/Data/Class/GO Biological Process.txt");
foreach my $geneId (@geneIds) {
    foreach my $go (@{$DATA{$geneId}{"go"}}) {
        print $out "$geneId\t".$GO_NAMES{$go}."\n" if($GO_TYPES{$go} eq "BP");
    }
}
close($out);

# generate file EASE/Data/Class/GO Cellular Component.txt
$out = createFile("./$taxonomyName/Ease/Data/Class/GO Cellular Component.txt");
foreach my $geneId (@geneIds) {
    foreach my $go (@{$DATA{$geneId}{"go"}}) {
        print $out "$geneId\t".$GO_NAMES{$go}."\n" if($GO_TYPES{$go} eq "CC");
    }
}
close($out);

# generate file EASE/Data/Class/GO Molecular Function.txt
$out = createFile("./$taxonomyName/Ease/Data/Class/GO Molecular Function.txt");
foreach my $geneId (@geneIds) {
    foreach my $go (@{$DATA{$geneId}{"go"}}) {
        print $out "$geneId\t".$GO_NAMES{$go}."\n" if($GO_TYPES{$go} eq "MF");
    }
}
close($out);

# generate files EASE/Data/Class/URL data/Tags/GO Biological Process.txt & GO Cellular Component.txt & GO Molecular Function.txt
my $out_bp = createFile("./$taxonomyName/Ease/Data/Class/URL data/Tags/GO Biological Process.txt");
my $out_cc = createFile("./$taxonomyName/Ease/Data/Class/URL data/Tags/GO Cellular Component.txt");
my $out_mf = createFile("./$taxonomyName/Ease/Data/Class/URL data/Tags/GO Molecular Function.txt");
foreach my $go (sort(keys(%GO_NAMES))) {
    if($GO_TYPES{$go} eq "BP") {
        print $out_bp $GO_NAMES{$go}."\t$go\n";
    } elsif($GO_TYPES{$go} eq "CC") {
        print $out_cc $GO_NAMES{$go}."\t$go\n";
    } elsif($GO_TYPES{$go} eq "MF") {
        print $out_mf $GO_NAMES{$go}."\t$go\n";
    }
}
close($out_bp);
close($out_cc);
close($out_mf);

# generate file EASE/Data/Class/Kegg PathWay.txt
# FIXME the file is empty
$out = createFile("./$taxonomyName/EASE/Data/Class/Kegg PathWay.txt");
foreach my $geneId (@geneIds) {
    foreach my $kegg (@{$DATA{$geneId}{"kegg"}}) {
        foreach my $pathway (@{$KEGG_LINKS{$kegg}}) {
            print $out "$geneId\t".$KEGG_NAMES{$pathway}."\n";
        }
    }
}
close($out);

# generate file EASE/Data/Class/URL data/Tags/Kegg PathWay.txt
$out = createFile("./$taxonomyName/EASE/Data/Class/URL data/Tags/Kegg PathWay.txt");
foreach my $i (keys(%KEGG_NAMES)) {
    print $out $KEGG_NAMES{$i}."\t$i\n";
}
close($out);

# generate file EASE/List/Swissprot identifiers/Populations/All Homo sapiens.txt
$out = createFile("./$taxonomyName/Ease/List/Swissprot identifiers/Populations/All $taxonomyName.txt");
foreach my $acc (sort(keys(%PROTEIN_NAME))) {
    print $out $PROTEIN_NAME{$acc}."\n";
}
close($out);

# generate file EASE/List/Swissprot accession/Populations/All Homo sapiens.txt
$out = createFile("./$taxonomyName/Ease/List/Swissprot accession/Populations/All $taxonomyName.txt");
foreach my $acc (sort(keys(%PROTEIN_NAME))) {
    print $out "$acc\n";
}
close($out);

# generate a file to specify the versions of Uniprot and GO
$out = createFile("./$taxonomyName/Database release.txt");
print $out "Uniprot release: $uniprotVersion\r\n";
print $out "QuickGO version: ".getQuickGOVersion()."\r\n";
close($out);

# create the script too
$out = createFile("./$taxonomyName/setData.bat");
print $out "xcopy /Y /E /F Ease\\* ..\\..\\EASE\\\r\n";
close($out);

# compress the output folder
print "Creating zip file for EaseDB directory\n";
my $zip = Archive::Zip->new();
$zip->addTree($taxonomyName, "$taxonomyName");
$zip->writeToFileNamed($outputFile);

# clean stuff at the end
remove_tree("./$taxonomyName");

print "Correct ending of the script\n";

exit;

sub getUniprotTaxonomyNames {
    my ($taxonomyId) = @_;
    my $scientificName = "";
    my $commonName = "";
    
    # download https://www.uniprot.org/taxonomy/9606.rdf
    my $url = "https://www.uniprot.org/taxonomy/$taxonomyId.rdf";
    my ($message, $version) = REST_GET_Uniprot($url);
    
    # read the output
    foreach my $line (split(/\n/, $message)) {
        if($line =~ m/<scientificName>(.*)<\/scientificName>/) {
            $scientificName = $1;
        } elsif($line =~ m/<commonName>(.*)<\/commonName>/) {
            $commonName = $1;
        }
        # do not read further if we have all we need
        last if($scientificName ne "" && $commonName ne "");
    }
    
    my $fullName = "$scientificName ($commonName)";
    print "Taxonomy $taxonomyId stands for '$fullName'\n";
    return ($scientificName, $fullName, $version);
}

sub getUniprotData {
    my ($taxonomyId, $source) = @_;
    
    my @ids = ($taxonomyId);
    my @fields = ("accession", "id", "gene_primary", "xref_geneid", "xref_kegg", "go_p", "go_c", "go_f", "go_id");
    my $message = searchEntries("tsv", \@fields, \@ids);

    # print "Download protein data from Uniprot SwissProt".($source eq "un" ? " and TrEMBL" : "")." for taxonomy $taxonomyId\n";
    # # prepare the REST url
    # my $url = "https://www.uniprot.org/uniprot/?query=";
    # $url .= "reviewed:yes%20" if($source ne "un");
    # $url .= "taxonomy:$taxonomyId&format=tab&";
    # # $url .= "limit=10&"; # uncomment this line to test things
    # $url .= "columns=id,entry%20name,genes(PREFERRED),database(GeneID),database(KEGG),go(biological%20process),go(cellular%20component),go(molecular%20function),go-id";
    # # sample: https://www.uniprot.org/uniprot/?query=reviewed:yes%20taxonomy:9606&format=tab&limit=10&columns=id,entry%20name,protein%20names,genes,organism,go(biological%20process),go(cellular%20component),go(molecular%20function),go-id,genes(PREFERRED)

    # send the GET request
    # my $message = REST_GET($url);
    my $i = 1;
    foreach my $line (split(/\n/, $message)) {
        next if($line =~ m/^Entry/); # skip the header line
        my ($acc, $name, $symbol, $geneIds, $keggIds, $biologicalProcess, $cellularComponent, $molecularFunction, $goIds) = split(/\t/, $line);
        # split GO by category
        extractGO($biologicalProcess, "BP");
        extractGO($cellularComponent, "CC");
        extractGO($molecularFunction, "MF");
        # record the data in a hash
        $symbol =~ s/;.*//; # only keep the first symbol
        $PROTEIN_NAME{$acc} = $name;
        my @goList = split(/; /, $goIds);
        #$keggIds =~ s/\://g;
        my @keggList = split(/;/, $keggIds);
        foreach my $geneId (split(/;/, $geneIds)) {
            $DATA{$geneId}{"acc"} = $acc; # SwissProt accession.txt
            $DATA{$geneId}{"symbol"} = $symbol; # Gene Symbol.txt
            push(@{$DATA{$geneId}{"go"}}, @goList); # GOID.txt
            push(@{$DATA{$geneId}{"kegg"}}, @keggList); # Kegg Pathway.txt
        }
    }
}

sub extractGO {
    my ($goString, $category) = @_;
    # calcium-dependent cysteine-type endopeptidase activity [GO:0004198]; heme binding [GO:0020037]; oxygen binding [GO:0019825]
    foreach my $go (split(/;/, $goString)) {
        if($go =~ m/^\s*(.*) \[(GO:\d+)\]/) {
            $GO_NAMES{$2} = $1;
            $GO_TYPES{$2} = $category;
        }
    }
}

sub getKeggTaxonomy {
    
    my $name = "";
    foreach my $id (keys(%DATA)) {
        foreach my $keggId (@{$DATA{$id}{"kegg"}}) {
            $name = $keggId;
            $name =~ s/:.*//; # hsa:71 => hsa
            #$name =~ s/\d+$//; # hsa71 => hsa
        }
        last if($name ne ""); # stop after first match
    }
    print "Kegg taxonomy is $name\n";
    return $name;
}

sub getKeggPathways {
    my ($taxonomy) = @_;
    
    print "Download Kegg pathways for taxonomy $taxonomy\n";
    
    my $url = "http://rest.kegg.jp/list/pathway/$taxonomy";
    print "REST url: $url\n";
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(GET => $url);
    $request->header('content-type' => 'application/json');
    my @chars = ("A".."Z", "a".."z");
    my $string = "";
    $string .= $chars[rand @chars] for 1..16;
    $request->header('x-auth-token' => $string);
    my $response = $ua->request($request);
    
    # read the output
    if ($response->is_success) {
        foreach my $line (split(/\n/, $response->decoded_content)) {
            # path:hsa04610	Complement and coagulation cascades - Homo sapiens (human)
            # path:ath00010	Glycolysis / Gluconeogenesis - Arabidopsis thaliana (thale cress)
            # $line =~ m/path:($taxonomy\d*)\t(.*)/;
            $line =~ m/path:($taxonomy.*)\t(.*)/;
            $KEGG_NAMES{$1} = $2;
        }
    } else {
        stderr(__FILE__.":".__LINE__.": HTTP GET error code:".$response->code." with message: ".$response->message);
    }
}

sub linkKeggPathways {
    my ($taxonomy) = @_;
    
    print "Download Kegg pathways for taxonomy $taxonomy\n";
    
    my $url = "http://rest.kegg.jp/link/pathway/$taxonomy";
    print "REST url: $url\n";
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(GET => $url);
    $request->header('content-type' => 'application/json');
    my @chars = ("A".."Z", "a".."z");
    my $string = "";
    $string .= $chars[rand @chars] for 1..16;
    $request->header('x-auth-token' => $string);
    my $response = $ua->request($request);
    
    # read the output
    if ($response->is_success) {
        foreach my $line (split(/\n/, $response->decoded_content)) {
            # hsa:71	path:hsa04520
            # ath:AT1G01090	path:ath00010
            # $line =~ m/($taxonomy):(\d+)\tpath:($taxonomy\d+)/;
            $line =~ m/($taxonomy):(.+)\tpath:($taxonomy.+)/;
            push(@{$KEGG_LINKS{"$1$2"}}, $3);
        }
    } else {
        stderr(__FILE__.":".__LINE__.": HTTP GET error code:".$response->code." with message: ".$response->message);
    }
}

sub createFile {
    my ($filePath) = @_;
    print "Create file $filePath\n";
    make_path(dirname($filePath));
    open(my $out, ">$filePath") or stderr("Can't create file $filePath: $!");
    return $out;
}

