#!/usr/bin/perl
use strict;
use warnings;

use XML::Simple;

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions qw(archive getDate parameters stderr);
use LsmboExcel qw(getValue setColumnsWidth writeExcelLine writeExcelLineF);
use LsmboRest qw(REST_GET REST_POST_Uniprot_tab UNIPROT_RELEASE);

use DBI;
use File::Copy;
use Image::Size;
use List::MoreUtils qw(uniq);
use MIME::Base64 qw(encode_base64);
use Scalar::Util qw(looks_like_number);
use SVG;

# $inputFile must contain protein accession numbers, p-value, fc, tukey
# $anova, $fc, $tukey are threshold values
my ($paramFile, $outputFile, $zipFile) = @ARGV;

# set global variables here
my %PARAMS = %{parameters($paramFile)};
# database directories
my $dirname = dirname(__FILE__);
my $DIR_MAP = "$dirname/map";
my $DIR_INFO = "$dirname/info";
my $DIR_CONF = "$dirname/conf";
my $DIR_XML = "$dirname/kgml";
$DIR_XML = "$dirname/kgml_maps" if($PARAMS{"type"} ne "uniprot");
# local temporary directories
my $DIR_DRAW = "draw";
my $DIR_SVG = "svg";
# colors
my $BLACK = "#000000";
my %COLORCODES = ("Y" => "#ffe333", "B" => "#428fd3", "R" => "#ff4c33", "G" => "#53c326");
my %COLORMEANING = ("Y" => "Does not satisfy p-value criteria",
                    "B" => "Satisfies p-value criteria",
                    "R" => "Upregulated",
                    "G" => "Downregulated");
# input data
my %DATA;
my $SQLITEDB = "kegg.db";

# clean stuff just in case
mkdir($DIR_DRAW) unless(-d $DIR_DRAW);
mkdir($DIR_SVG) unless(-d $DIR_SVG);
unlink($SQLITEDB, glob("$DIR_DRAW/*"), glob("$DIR_SVG/*"));

# make a copy of the file, otherwise the XLSX parser may fail
my $inputCopy = "input.xlsx";
copy($PARAMS{"inputFile"}, $inputCopy);

# read the input file
my @headers = extractData($inputCopy);
print "".scalar(keys(%DATA))." entries have been stored\n";

# make sure the uniprot identifiers are the good ones
# what is expected is the Entry, and not the Entry name (ie. P0DPI2 instead of GAL3A_HUMAN)
if($PARAMS{"type"} eq "uniprot") {
  # put the ids in a text file
  my $tempFile = "uniprot_temp_ids.txt";
  open(my $tmp, '>', $tempFile) or stderr("Unable to create a temporary file for Uniprot conversion");
  foreach (keys(%DATA)) {
    print $tmp $DATA{$_}{"A"}."\n";
  }
  close $tmp;
  # ask uniprot for the corresponding Entry (id)
  my %output = %{REST_POST_Uniprot_tab($tempFile, "ACC+ID", "id")};
  # extract uniprot version
  my $version = delete($output{UNIPROT_RELEASE()});
  # replace the keys in %DATA
  foreach (keys(%DATA)) {
    my $userEntry = $DATA{$_}{"A"};
    my @items = @{$output{$userEntry}};
    my $entry = $items[1];
    # $DATA{$_}{"A"} = $entry;
    # $DATA{$_}{"UserEntry"} = $userEntry;
    $DATA{$_}{"Entry"} = $entry;
  }
  # delete the temp file
  unlink $tempFile;
}

my $taxonomy = "";
if($PARAMS{"type"} eq "uniprot") {
  # detect the taxonomy based on the first protein ID
  $taxonomy = detectTaxonomy();
  stderr("Unable to determine taxonomy from the protein IDs") if($taxonomy eq "");
  print "Taxonomy is '$taxonomy'\n";
  # create the database
  setupDatabase($taxonomy);
} else {
  setupDatabaseCpd();
}
# fill the database
importData();
my @maps = getMaps();


# update maps with REST API
if($PARAMS{"type"} eq "uniprot") {
  updateMaps($taxonomy, @maps);
} else {
  updateMapsCpd(@maps);
  $taxonomy = "map";
}
cleanMaps($taxonomy, @maps);

# create drawings
prepareDrawing($taxonomy);
createSvgFiles();

# create excel output
writeExcelOutput(\@headers, $taxonomy, $outputFile);

# compress the svg folder at the end
print "Creating zip file with all svg files\n";
archive($zipFile, $DIR_SVG);

# clean stuff at the end
unlink($SQLITEDB, glob("$DIR_DRAW/*"), glob("$DIR_SVG/*"), $inputCopy);
rmdir($DIR_DRAW);
rmdir($DIR_SVG);

print "Correct ending of the script\n";

exit;


sub extractData {
    my ($inputFile) = @_;
    
    print "Read input file $inputFile\n";
    my @headers;
    # open the excel file
    my $parser = Spreadsheet::ParseXLSX->new;
    my $workbook = $parser->parse($inputFile);
    stderr($parser->error()."\n") if(!defined $workbook);
    
    my @worksheets = $workbook->worksheets;
    my $worksheet = $worksheets[0];
    my ($row_min, $row_max) = $worksheet->row_range();
    my ($col_min, $col_max) = $worksheet->col_range();

    # get headers in first line
    for my $col ($col_min .. $col_max) {
        push(@headers, getValue($worksheet, $row_min, $col));
    }
    
    # skip header line
    my $id = 0;
    for my $row ($row_min+1 .. $row_max) {
        my $acc = getValue($worksheet, $row, 0);
        next if($acc eq "");
        $DATA{$id++} = {
            "A" => $acc, 
            "B" => $col_max > 0 ? getValue($worksheet, $row, 1) : "", 
            "C" => $col_max > 1 ? getValue($worksheet, $row, 2) : "", 
            "D" => $col_max > 2 ? getValue($worksheet, $row, 3) : "",
        };
    }
    
    return @headers;
}

sub detectTaxonomy {
    # use the REST api with each protein until one protein matches a taxonomy (hopefully the first one!)
    foreach my $i (keys(%DATA)) {
        # my $protein = $DATA{$i}{"A"};
        my $protein = (exists($DATA{$i}{"Entry"}) ? $DATA{$i}{"Entry"} : $DATA{$i}{"A"});
        my $output = REST_GET("http://rest.kegg.jp/conv/genes/up:$protein");
        # expected result: up:O14683\thsa:9537
        if($output =~ m/.+\t(.+):.+$/) {
            return $1;
        }
    }
    return "";
}

sub setupDatabase {
    my ($taxonomy) = @_;
    
    # prepare SQLite database
    print "Prepare SQLite database\n";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$SQLITEDB", "", "", {
        AutoCommit => 0 # disable auto-commit to improve the import
    }) or stderr($DBI::errstr);
    doAndCommit($dbh, qq(CREATE TABLE taxonomy (taxonomy TEXT NOT NULL);));
    doAndCommit($dbh, qq(CREATE TABLE uphsa (protein TEXT NOT NULL, hsa TEXT NOT NULL);));
    doAndCommit($dbh, qq(CREATE TABLE hsapath (hsa TEXT NOT NULL, path TEXT NOT NULL);));
    doAndCommit($dbh, "INSERT INTO taxonomy VALUES (\"$taxonomy\")");
    
    # basic use case
    my @keggIds = split(/\n/, REST_GET("http://rest.kegg.jp/conv/$taxonomy/uniprot"));
    my $sth = $dbh->prepare("INSERT INTO uphsa VALUES (?,?)");
    foreach my $keggId (@keggIds) {
        my ($prot, $id) = split(/\t/, $keggId);
        $prot =~ s/up://;
        $sth->execute($prot, $id);
    }
    $dbh->commit();

    # get pathways
    my @pathways = split(/\n/, REST_GET("http://rest.kegg.jp/link/pathway/$taxonomy"));
    $sth = $dbh->prepare("INSERT INTO hsapath VALUES (?,?)");
    foreach my $pathway (@pathways) {
        my ($kegg, $path) = split(/\t/, $pathway);
        $sth->execute ($kegg, $path);
    }
    $dbh->commit();
    
    # adding indices after uploading data (to make sure the indices are calculated only once)
    doAndCommit($dbh, qq(CREATE INDEX prot ON uphsa(protein)));
    doAndCommit($dbh, qq(CREATE INDEX kegg ON uphsa(hsa)));
    doAndCommit($dbh, qq(CREATE INDEX hsa ON hsapath(hsa)));
    doAndCommit($dbh, qq(CREATE INDEX path ON hsapath(path)));
    
    # disconnect from database
    $dbh->disconnect();
    
    print "Current SQLite database is $SQLITEDB\n";
}

sub setupDatabaseCpd {
    
    # prepare SQLite database
    print "Prepare SQLite database\n";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$SQLITEDB", "", "", {
        AutoCommit => 0 # disable auto-commit to improve the import
    }) or stderr($DBI::errstr);
    doAndCommit($dbh, qq(CREATE TABLE cpdpath (cpd TEXT NOT NULL, path TEXT NOT NULL);));
    
    # get pathways per compound
    my @pathways = split(/\n/, REST_GET("http://rest.kegg.jp/link/pathway/compound"));
    my $sth = $dbh->prepare("INSERT INTO cpdpath VALUES (?,?)");
    foreach my $item (@pathways) {
        my ($compound, $pathway) = split(/\t/, $item);
        $compound =~ s/^cpd://;
        $sth->execute($compound, $pathway);
    }
    $dbh->commit();
    
    # adding indices after uploading data (to make sure the indices are calculated only once)
    doAndCommit($dbh, qq(CREATE INDEX cpd ON cpdpath(cpd)));
    doAndCommit($dbh, qq(CREATE INDEX path ON cpdpath(path)));
    
    # disconnect from database
    $dbh->disconnect();
    
    print "Current SQLite database is $SQLITEDB\n";
}

sub doAndCommit {
    my ($dbh, $statement) = @_;
    $dbh->do($statement);
    $dbh->commit();
}

sub importData {
    # also use %DATA

    # connection
    my $dbh = DBI->connect("dbi:SQLite:dbname=$SQLITEDB", "", "", {
        AutoCommit => 0 # disable auto-commit to improve the import
    }) or stderr($DBI::errstr);
    if($PARAMS{"type"} eq "uniprot") {
      doAndCommit($dbh, qq(CREATE TABLE acc (protein TEXT PRIMARY KEY, color TEXT NOT NULL);));
    } else {
      doAndCommit($dbh, qq(CREATE TABLE acc (cpd TEXT PRIMARY KEY, color TEXT NOT NULL);));
    }
    my $sth = $dbh->prepare("INSERT INTO acc VALUES (?,?)");
    
    # parsing data
    print "Filling database with user data\n";
    for(my $i = 0; $i < scalar(keys(%DATA)); $i++) {
        my %row = %{$DATA{$i}};
        # my $acc = $row{"A"};
        my $acc = (exists($row{"Entry"}) ? $row{"Entry"} : $row{"A"});
        if($PARAMS{"Statistics"}{"value"} eq "none") {
            # no statistics
            $sth->execute($acc, "Y");
        } elsif($PARAMS{"Statistics"}{"value"} eq "anova_only") {
            # just anova
            my $anova = $PARAMS{"Statistics"}{"anova"};
            $sth->execute($acc, $row{"B"} < $anova ? "B" : "Y");
        } elsif($PARAMS{"Statistics"}{"value"} eq "anova_fc") {
            # anova + FC
            my $anova = $PARAMS{"Statistics"}{"anova"};
            my $fc = $PARAMS{"Statistics"}{"fc"};
            my $userAnova = $row{"B"};
            my $userFC = $row{"C"};
            if(looks_like_number($userAnova) && $userAnova < $anova) {
                if(!looks_like_number($userFC)) { $sth->execute($acc, "B"); # case if no FC value
                } elsif($userFC > $fc) { $sth->execute($acc, "R");
                } elsif($userFC < -$fc) { $sth->execute($acc, "G");
                } else { $sth->execute($acc, "B"); }
            } else {
                $sth->execute($acc, "Y");
            }
        # TODO test with tukey
        } elsif($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey") {
            # anova + Tukey + FC
            my $anova = $PARAMS{"Statistics"}{"anova"};
            my $fc = $PARAMS{"Statistics"}{"fc"};
            my $tukey = $PARAMS{"Statistics"}{"tukey"};
            my $userAnova = $row{"B"};
            my $userTukey = $row{"C"};
            my $userFC = $row{"D"};
            if($userAnova < $anova && $userTukey < $tukey) {
                if($userFC > $fc) { $sth->execute($acc, "R");
                # TODO check if it's correct, in Patrick's script it was $fc instead of -$fc
                } elsif($userFC < -$fc) { $sth->execute($acc, "G");
                } else { $sth->execute($acc, "B"); }
            } else {
                $sth->execute($acc, "Y");
            }
        }
    }
    $dbh->commit();
    
    # disconnect from database
    $dbh->disconnect();
}

sub getMaps {
    # also use %DATA

    # connection
    my $dbh = DBI->connect("dbi:SQLite:dbname=$SQLITEDB", "", "", {
        AutoCommit => 0 # disable auto-commit to improve the import
    }) or stderr($DBI::errstr);
    
    my @maps;
    if($PARAMS{"type"} eq "uniprot") {
      doAndCommit($dbh, qq(CREATE TABLE map (protein TEXT NOT NULL, color  TEXT NOT NULL, keggid TEXT NOT NULL, path TEXT NOT NULL);));
      # fill the map table
      my $sth_1 = $dbh->prepare("INSERT INTO map VALUES (?,?,?,?)");
      my $sth = $dbh->prepare("SELECT a.protein, a.color, u.hsa, h.path FROM uphsa u INNER JOIN hsapath h ON h.hsa=u.hsa INNER JOIN acc a ON a.protein=u.protein ORDER BY h.path");
      $sth->execute();
      while (my @row = $sth->fetchrow_array()) {
          $sth_1->execute($row[0], $row[1], $row[2], $row[3]);
          push (@maps, $row[3]);
      }
      $dbh->commit();
      # adding indices
      doAndCommit($dbh, qq(CREATE INDEX mapprot ON  map(protein)));
      doAndCommit($dbh, qq(CREATE INDEX mappath ON  map(path)));
      doAndCommit($dbh, qq(CREATE INDEX keggid ON  map(keggid)));
    } else {
      doAndCommit($dbh, qq(CREATE TABLE map (cpd TEXT NOT NULL, color TEXT NOT NULL, path TEXT NOT NULL);));
      # fill the map table
      my $sth_1 = $dbh->prepare("INSERT INTO map VALUES (?,?,?)");
      my $sth = $dbh->prepare("SELECT a.cpd, a.color, h.path FROM cpdpath h INNER JOIN acc a ON a.cpd=h.cpd");
      $sth->execute();
      while (my @row = $sth->fetchrow_array()) {
          $sth_1->execute($row[0], $row[1], $row[2]);
          push (@maps, $row[2]);
      }
      $dbh->commit();
      # adding indices
      doAndCommit($dbh, qq(CREATE INDEX mapprot ON  map(cpd)));
      doAndCommit($dbh, qq(CREATE INDEX mappath ON  map(path)));
    }
    
    # disconnect from database
    $dbh->disconnect();
    
    @maps = sort (uniq(@maps));
    print scalar(@maps)." maps have been added to the database\n";
    return @maps;
}

sub updateMaps {
    my ($taxonomy, @maps) = @_;

    print "Updating maps from KEGG central database\n";
    my @elements=('link', 'entry', 'number', 'org', 'name', 'image', 'title');
    my $xs = new XML::Simple(keeproot => 1, searchpath => ".", forcearray => ['id'], KeyAttr => {entry =>"id"});
    foreach my $map (@maps) {
        $map =~ s/path:$taxonomy//;
        # only update maps older than 2 month
        if(-f "$DIR_XML/$taxonomy$map.xml") {
            my $mtime = (-C "$DIR_XML/$taxonomy$map.xml");
            my $delta = 30 * 2;
            next if ((-e "$DIR_MAP/$map.png") && (-e "$DIR_CONF/$map.conf") && (-e "$DIR_XML/$taxonomy$map.xml") && (-e "$DIR_INFO/$map.txt") && ($mtime < $delta));
        }
        
        # the following lines will update each file
        restGetToFile("http://rest.kegg.jp/get/map$map", "$DIR_INFO/$map.txt");
        restGetToFile("http://rest.kegg.jp/get/map$map/image", "$DIR_MAP/$map.png");
        restGetToFile("http://rest.kegg.jp/get/map$map/conf", "$DIR_CONF/$map.conf");
        # this file is in XML and has to be modified before saving
        my $ref = $xs->XMLin(REST_GET("http://rest.kegg.jp/get/$taxonomy$map/kgml"));
        my $entry = $ref->{pathway};
        # remove items that are not contained in @elements
        foreach my $id (keys %$entry) {
            next if(grep(/$id/, @elements));
            delete $entry->{$id};
        }
        # remove entries that are not gene type
        $entry=$ref->{pathway}{entry};
        foreach my $id (keys(%$entry)) {
            delete $entry->{$id} if($entry->{$id}{type} ne "gene");
        };
        open (my $fh, ">", "$DIR_XML/$taxonomy$map.xml") or stderr("Can't open file '$DIR_XML/$taxonomy$map.xml': $!");
        print $fh $xs->XMLout($ref);
        close $fh;
        sleep 10;
    }
}

sub updateMapsCpd {
    my (@maps) = @_;

    print "Updating maps from KEGG central database\n";
    my @elements=('link', 'entry', 'number', 'org', 'name', 'image', 'title');
    foreach my $map (@maps) {
        $map =~ s/path:map//;
        # only update maps older than 2 month
        if(-f "$DIR_XML/map$map.xml") {
            my $mtime = (-C "$DIR_XML/map$map.xml");
            my $delta = 30 * 2;
            next if ((-e "$DIR_MAP/$map.png") && (-e "$DIR_CONF/$map.conf") && (-e "$DIR_INFO/$map.txt") && ($mtime < $delta));
        }

        # the following lines will update each file
        restGetToFile("http://rest.kegg.jp/get/map$map", "$DIR_INFO/$map.txt");
        restGetToFile("http://rest.kegg.jp/get/map$map/image", "$DIR_MAP/$map.png");
        restGetToFile("http://rest.kegg.jp/get/map$map/conf", "$DIR_CONF/$map.conf");
        # extract compounds from conf file
        my @compounds;
        open(my $fh, "<", "$DIR_CONF/$map.conf") or stderr("Can't open file '$DIR_CONF/$map.conf': $!");
        while(<$fh>) {
            chomp;		
            my @line = split(/\t/);
            next if($line[2] !~ /^C\d{5}/);
            push (@compounds, $_);
        }
        close $fh;

        # create the XML file (indentation of 3 space chars ; data mode 1 means line break)
        my $output = new IO::File(">$DIR_XML/map$map.xml");
        my $ref = new XML::Writer(OUTPUT => $output, DATA_INDENT => 3, DATA_MODE => 1, ENCODING => 'utf-8');
        $ref->xmlDecl("UTF-8"); # is it necessary ?
        $ref->startTag("pathway");
        my $index = 1;
        foreach my $compound (@compounds) {
            my ($type, $url, $name) = split(/\t/, $compound);
            $ref->startTag("entry", "id" => $index++, "name" => $name, "type" => "compound");
            if($type =~ m/^rect/) {
                $type =~ m/.+\((\d+)\,(\d+)\)\s\((\d+)\,(\d+)/;
                my ($left, $down, $right, $up) = ($1, $2, $3, $4);
                $ref->startTag("graphics", "bgcolor" => $COLORCODES{"G"}, "fgcolor" => $BLACK, "name" => $name, "type" => "rect", 
                    "height" => $up - $down, "width" => $right - $left, "x" => $left + floor(($right - $left) / 2), "y" => $down + floor(($up - $down) / 2));
                $ref->endTag("graphics");
            } elsif($type =~ /^circ/ || $type =~ /^filled_circ/) {
                $type =~ m/.+\((\d+)\,(\d+).+(\d+)/;
                my ($x, $y, $radius) = ($1, $2, $3);
                $ref->startTag("graphics", "bgcolor" => $COLORCODES{"G"}, "fgcolor" => $BLACK, "name" => $name, "type" => "circ", "width" => $radius, "x" => $x, "y" => $y);
                $ref->endTag("graphics");
            }
            $ref->endTag ("entry");
        }
        $ref->startTag("entry", "id" => "9999", "name" => "EMPTY", "type" => "compound"); # why ??
        $ref->endTag("entry");
        $ref->endTag("pathway");
        $ref->end();
        sleep 2;
    }
}

sub restGetToFile {
    my ($url, $outputFile) = @_;
    open (my $fh, ">", "$outputFile") or stderr("Can't create file '$outputFile': $!");
    print $fh REST_GET($url);
    close $fh;
}

sub cleanMaps {
    my ($taxonomy, @maps) = @_;

    # connection
    my $dbh = DBI->connect("dbi:SQLite:dbname=$SQLITEDB", "", "") or stderr($DBI::errstr);
    
    # Remove proteins not use in map file
    my $xs = new XML::Simple(keeproot => 1, searchpath => ".", forcearray => ['id'], KeyAttr => {entry =>"id"});
    my $sql_1 = "SELECT COUNT(keggid) FROM view_map WHERE keggid=?";
    $sql_1 = "SELECT COUNT(cpd) FROM view_map WHERE cpd=?" if($PARAMS{"type"} ne "uniprot");
    foreach my $map (@maps) {
        $map =~ s/path:$taxonomy//;
        # create a temporary view
        $dbh->do("DROP VIEW IF EXISTS view_map");
        my $sql_c = "CREATE TEMP VIEW view_map AS SELECT keggid FROM map WHERE path=\"path:$taxonomy$map\"";
        $sql_c = "CREATE TEMP VIEW view_map AS SELECT cpd FROM map WHERE path=\"path:map$map\"" if($PARAMS{"type"} ne "uniprot");
        my $sth = $dbh->prepare($sql_c);
        $sth->execute();
        my $sth_1 = $dbh->prepare($sql_1);
        my $ref = $xs->XMLin("$DIR_XML/$taxonomy$map.xml");
        my $entry = $ref->{pathway}{entry};
        foreach my $id (keys %$entry) {
            my @names = split(/ /, $entry->{$id}{name});
            my $flag = 0;
            foreach (@names) {
                $sth_1->execute($_);
                while (my @row = $sth_1->fetchrow_array()) {
                    $flag++ if($row[0] > 0);
                }
            }
            delete $entry->{$id} if (!$flag);
        }
        my $xml = $xs->XMLout($ref);
        open (my $fh, ">", "$DIR_DRAW/draw$map.xml") or stderr("Can't write file '$DIR_DRAW/draw$map.xml': $!");
        print $fh $xml;
        close $fh;
    }

    $dbh->disconnect();
}

sub prepareDrawing {
    my ($taxonomy) = @_;

    # connection
    my $dbh = DBI->connect("dbi:SQLite:dbname=$SQLITEDB", "", "") or stderr($DBI::errstr);

    # prepare XML reader
    my $xs = new XML::Simple(keeproot => 1, searchpath => ".", forcearray => ['id'], KeyAttr => {entry =>"id"});

    foreach my $map (glob("$DIR_DRAW/*.xml")) {
        my ($number) = $map =~ /(\d+)/;
        $dbh->do("DROP VIEW IF EXISTS view_map");
        my $sql_c = "CREATE VIEW view_map AS SELECT protein, color, keggid FROM map WHERE path=\"path:$taxonomy$number\"";
        $sql_c = "CREATE VIEW view_map AS SELECT cpd, color, path FROM map WHERE path=\"path:map$number\"" if($PARAMS{"type"} ne "uniprot");
        my $sth = $dbh->prepare($sql_c);
        $sth->execute();
        my $ref = $xs->XMLin($map);
        my $entry = $ref->{pathway}{entry};
        # draw rectangle in Yellow
        foreach my $id (keys %$entry) {
            next if((!looks_like_number($id)) && ($id ne "id"));
            if(looks_like_number($id)) {
                if(ref($entry->{$id}{graphics}) eq "HASH" ) {
                    $entry->{$id}{graphics}{bgcolor} = $COLORCODES{"Y"};
                    ($entry->{$id}{graphics}{name}, $entry->{$id}{graphics}{bgcolor}) = hsaToProtein(\$dbh, $entry->{$id}{name});
                } elsif(ref($entry->{$id}{graphics}) eq "ARRAY") {
                    foreach my $graphic (@{$entry->{$id}{graphics} }) {
                        $graphic->{bgcolor} = $COLORCODES{"Y"};
                        ($graphic->{name}, $graphic->{bgcolor}) = hsaToProtein(\$dbh, $entry->{$id}{name});
                    }
                }
            } else {
                if(ref($entry->{graphics}) eq "ARRAY") {
                    foreach my $graphic (@{$entry->{graphics}}) {
                        $graphic->{bgcolor} = $COLORCODES{"Y"};
                        ($graphic->{name}, $graphic->{bgcolor}) = hsaToProtein(\$dbh, $entry->{$id}{name});
                    } 
                } else {
                    $entry->{graphics}{bgcolor} = $COLORCODES{"Y"};
                    ($entry->{graphics}{name}, $entry->{graphics}{bgcolor}) = hsaToProtein(\$dbh, $entry->{name});					
                }
            };				
            
        };
        open (my $fh, ">", $map) or stderr("Can't open file '$map': $!");
        print $fh $xs->XMLout($ref);
        close $fh;
        $sth->finish;
    }
    $dbh->do("DROP VIEW IF EXISTS view_map");
    $dbh->disconnect();
}

sub hsaToProtein {
    my ($dbh, $names) = @_;
    my $sql = "SELECT protein, color FROM view_map WHERE keggid=? AND color=?";
    $sql = "SELECT cpd, color FROM view_map WHERE cpd=? AND color=?" if($PARAMS{"type"} ne "uniprot");
    my $sth = $$dbh->prepare($sql);
    my $protein = "";
    my %colors = ("Y" => 0, "B" => 0, "R" => 0, "G" => 0);
    # the order is important for later !
    foreach my $color ("Y", "B", "R", "G") {
        foreach my $name (split(/ /, $names)) {
            $sth->execute($name, $color);
            while (my @row = $sth->fetchrow_array()) {
                $protein .= $row[0]."|";
                $colors{$row[1]}++;
            }
        }
    }
	
    my $sumcolor = "";
    my $total = 0;
    foreach my $color ("Y", "B", "R", "G") {
        $sumcolor .= $colors{$color}."|";
        $total += $colors{$color};
    }
    $protein =~ s/\|$//;
    $sumcolor .= $total;
    return ($protein, $sumcolor);
}

sub createSvgFiles {
    # prepare XML reader
    my $xs = new XML::Simple(keeproot => 1, searchpath => ".", forcearray => ['id'], KeyAttr => {entry =>"id"});
    # treat each map
    foreach my $map (glob("$DIR_DRAW/*.xml")) {
        my ($num) = $map =~ /(\d+)/;
        # sometimes the png file is somehow incomplete and Windows says it cannot read it
        # the svg file can still be generated with most information, but the borders are not right
        my $png = "$DIR_MAP/$num.png";
        my ($width, $height) = imgsize($png);
        $width = 0 unless(looks_like_number($width));
        $height = 0 unless(looks_like_number($height));
        # using MIME::Base64 should be equivalent to linux base64 command
        my $delta = 100;
        my $svg = SVG->new(width  => $width + $delta, height => $height + $delta);
        my $tag = $svg->image(x => 22, y => 8, width => $width, height => $height, '-href' => "data:image/png;base64,".getBase64($png), id => 'image_1');

        # read XML file
        # TODO check if this loop can be merged with the one from prepareDrawing
        my $ref = $xs->XMLin($map);
        my $entry = $ref->{pathway}{entry};
        foreach my $id (keys(%$entry)) {
            next if((!looks_like_number($id)) && ($id ne "id")); 
            if(looks_like_number($id)) {
                if(ref($entry->{$id}{graphics}) eq "HASH" ) {
                    $svg = draw($entry->{$id}{graphics}, $svg, $id);
                } elsif(ref($entry->{$id}{graphics}) eq "ARRAY") {
                    foreach my $graphic (@{$entry->{$id}{graphics}}) {
                        $svg = draw($graphic, $svg, $id);
                    }
                }
            } else {
                if(ref($entry->{graphics}) eq "ARRAY") {
                    foreach my $graphic (@{$entry->{graphics}}) {
                        $svg = draw($graphic, $svg, $id);
                    }
                } else {
                    $svg = draw($entry->{graphics}, $svg, $id);
                }
            }		
        };
        open (my $fh, ">", "$DIR_SVG/$num.svg") or stderr("Can't create file '$DIR_SVG/$num.svg': $!");
        print $fh $svg->xmlify;
        close $fh;
    }
}

sub getBase64 {
    open (my $fh, "<", $_[0]) or stderr("$!");
    binmode($fh);
    local $/;
    my $file_contents = <$fh>;
    close $fh;
    return encode_base64($file_contents);
}

sub draw {
    my ($ptEntry, $svg, $id) = @_;
    my %entry = %{$ptEntry};
    
    # array of colors, same order as in hsaToProtein !
    my @colorIdx = ("Y", "B", "R", "G");
    if ($entry{type} eq "rectangle") {
        # colorize the existing rectangle
        # bgcolor="1|0|2|0|3" => 1 yellow, 2red, 3 in total
        my @colors = split(/\|/, $entry{bgcolor});
        my $total = pop(@colors); # last entry is the total
        $total = scalar(@colors) if($total == 0); # in case bgcolor = '0|0|0|0|0'
        my $deltaX = 0;
        my $x = $entry{x};
        my $y = $entry{y};
        my $i = 0;
        foreach my $value (@colors) {
            my $color = $colorIdx[$i];
            # calculate the percentage of the rectangle (if multiple colors)
            my $widthSize = int((($value / $total) * $entry{width}) + 0.5);
            $svg->rectangle(
                x => $x + $deltaX, y => $y,
                width	=> $widthSize, height => $entry{height},
                id => "ID$id$color",
                style => { stroke => $BLACK, fill => $COLORCODES{$color}, 'fill-opacity' => 0.7 },
            );
            $deltaX = $deltaX + $widthSize;
            $i++;
        }

        # add a tooltip to display the protein name(s)
        my $tag = $svg->group(id => 'ID'.$id.'GR', visibility => "hidden");
        $deltaX = 0;
        my @names = split(/\|/, $entry{name});
        my $first = 0;
        $i = 0;
        foreach my $value (@colors) {
            $i++;
            next if($value == 0);
            my $color = $colorIdx[$i-1];
            my $name = join("|", @names[$first .. $first + ($value - 1)]);
            $first += $value;
            my $widthSize = length($name) * 10 + 5; # using base 10
            # create one rectangle per color
            $tag->rectangle(
                x => ($x + 5) + $deltaX, y => $y - 30, 
                width => $widthSize, height => 25, 
                id => $id.'RE'.$color,
                style => { stroke => $BLACK, fill => $COLORCODES{$color}, 'fill-opacity' => 1 }, # set full opacity
            );
            # TODO check if it's correct (+= instead of =)
            #$deltaX += $deltaX + $widthSize; # looks good
            $deltaX += $widthSize; # looks just the same !?! (it must not be important)
        }
        $tag->text(id => $id.'T', x => $x + 10, y => $y - 12, fill => $BLACK, 'fill-opacity' => 1, -cdata => $entry{name});
        
        foreach (@colorIdx) {
            my $svgId = 'ID'.$id.$_;
            $tag->set(attributeName => "visibility", from => "hidden", to => "visible", begin => "$svgId.mouseover", end => "$svgId.mouseout");
        }
    } elsif($PARAMS{"type"} ne "uniprot" && ($entry{type} eq "circ" || $entry{type} eq "filled_circ")) {
        # colorize the existing circle
        my $x = $entry{x} + 22;
        my $y = $entry{y} + 8;
        my $fill = $entry{bgcolor};
        # bgcolor="1|0|2|0|3" => 1 yellow, 2red, 3 in total
        my @colors = split(/\|/, $entry{bgcolor});
        my $total = pop(@colors); # last entry is the total
        my $drawId = "";
        my $i = 0;
        foreach my $value (@colors) {
            my $color = $colorIdx[$i++];
            my $widthSize = int((($value / $total) * $entry{width}) + 0.5);
            next if ($widthSize == 0);
            $drawId = 'ID'.$id.$color;
            $svg->circle(cx => $x, cy => $y, r => $widthSize, id => $drawId, style => { stroke => $BLACK, fill => $COLORCODES{$color}, 'fill-opacity' => 1.0 });
            $svg->circle(cx => $x, cy => $y, r	=> 8, id => $drawId."1", style => { stroke => $BLACK, fill => $COLORCODES{$color}, 'fill-opacity' => 0.3 });
        }

        # add a tooltip to display the protein name(s) ?
        my $tag = $svg->group(id => 'ID'.$id.'GR', visibility => "hidden");
        my $deltaX = 0;
        my @names = split(/\|/, $entry{name});
        my $first = 0;
        $i = 0;
        foreach my $value (@colors) {
            next if($value == 0);
            my $color = $colorIdx[$i++ - 1];
            my $name = join("|", @names[$first .. $first + ($value - 1)]);
            $first += $value;
            my $widthSize = length($name) * 10 + 5; # using base 10
            # create one rectangle per color
            $tag->rectangle(
                x => ($x + 5) + $deltaX, y => $y - 30, 
                width => $widthSize, height => 25, 
                id => $id.'RE'.$color,
                style => { stroke => $BLACK, fill => $COLORCODES{$color}, 'fill-opacity' => 1 }, # set full opacity
            );
            # TODO check if it's correct (+= instead of =)
            #$deltaX += $deltaX + $widthSize; # looks good
            $deltaX += $widthSize; # looks just the same !?! (it must not be important)
        }
        $tag->text(id => $id.'T', x => $x + 10, y => $y - 8, fill => $BLACK, 'fill-opacity' => 1.0, -cdata => $entry{name});
        # add the action to show/hide the tooltip
        my $svgId = $drawId."1";
        $tag->set(attributeName => "visibility", from => "hidden", to => "visible", begin => "$svgId.mouseover", end => "$svgId.mouseout");
    }
    return ($svg);
}

sub writeExcelOutput {
    my ($ptHeaders, $taxonomy, $outputFile) = @_;

    print "Writing final Excel file\n";
    # connection
    my $dbh = DBI->connect("dbi:SQLite:dbname=$SQLITEDB", "", "") or stderr($DBI::errstr);
    # create file
    my $workbook = Excel::Writer::XLSX->new($outputFile);
    
    # prepare formats
    my $formatH = $workbook->add_format(bold => 1, bottom => 1, valign => 'top', text_wrap => 1);
    my $formatMaps = $workbook->add_format(valign => 'top', text_wrap => 1);
    my $formatY = $workbook->add_format(valign => 'top', bg_color => '#ffe333');
    my $formatR = $workbook->add_format(valign => 'top', bg_color => '#ff4c33');
    my $formatG = $workbook->add_format(valign => 'top', bg_color => '#53c326');
    my $formatB = $workbook->add_format(valign => 'top', bg_color => '#428fd3');

    # add input data and parameters
    my $sheet = $workbook->add_worksheet("Data");
    my $rowNumber = 0;
    # add parameters first
    writeExcelLine($sheet, $rowNumber++, "Date", getDate("%Y/%m/%d"));
    writeExcelLine($sheet, $rowNumber++, "P-value threshold", $PARAMS{"Statistics"}{"anova"}) unless($PARAMS{"Statistics"}{"value"} eq "none");
    writeExcelLine($sheet, $rowNumber++, "Fold Change threshold", $PARAMS{"Statistics"}{"fc"}) if($PARAMS{"Statistics"}{"value"} eq "anova_fc" || $PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    writeExcelLine($sheet, $rowNumber++, "Tukey threshold", $PARAMS{"Statistics"}{"tukey"}) if($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    $rowNumber++; # add an empty line
    # then headers
    my $headerLine = $rowNumber;
    # writeExcelLineF($sheet, $rowNumber++, $formatH, @{$ptHeaders});
    my @headers = @{$ptHeaders};
    splice(@headers, 1, 0, 'Uniprot entry') if($PARAMS{"type"} eq "uniprot");
    writeExcelLineF($sheet, $rowNumber++, $formatH, @headers);
    $sheet->freeze_panes($rowNumber);
    # then the data
    if($PARAMS{"type"} eq "uniprot") {
      for(my $i = 0; $i < scalar(keys(%DATA)); $i++) {
        writeExcelLine($sheet, $rowNumber++, $DATA{$i}{"A"}, $DATA{$i}{"Entry"}, $DATA{$i}{"B"}, $DATA{$i}{"C"}, $DATA{$i}{"D"});
      }
    } else {
      for(my $i = 0; $i < scalar(keys(%DATA)); $i++) {
        writeExcelLine($sheet, $rowNumber++, $DATA{$i}{"A"}, $DATA{$i}{"B"}, $DATA{$i}{"C"}, $DATA{$i}{"D"});
      }
    }
    # $sheet->autofilter($headerLine, 0, $rowNumber - 1, $headerLine - 2);
    $sheet->autofilter($headerLine, 0, $rowNumber - 1, scalar(@headers) - 1);
    # $sheet->set_column(0, 0, 30); # Column A width set to 30
    # $sheet->set_column(1, 1, 15);
    # $sheet->set_column(2, 2, 15) if($PARAMS{"Statistics"}{"value"} eq "anova_fc" || $PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    # $sheet->set_column(3, 3, 15) if($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    # my $col = 0;
    # print "ABU set_column($col, $col, 30)\n";
    # $sheet->set_column($col, $col++, 30); # Column A width set to 30
    # print "ABU set_column($col, $col, 30)\n";
    # $sheet->set_column($col, $col++, 30) if($PARAMS{"type"} eq "uniprot"); # Column 'Uniprot entry' width set to 30
    # print "ABU set_column($col, $col, 15)\n";
    # $sheet->set_column($col, $col++, 15);
    # print "ABU set_column($col, $col, 15)\n" if($PARAMS{"Statistics"}{"value"} eq "anova_fc" || $PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    # $sheet->set_column($col, $col++, 15) if($PARAMS{"Statistics"}{"value"} eq "anova_fc" || $PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    # print "ABU set_column($col, $col, 15)\n" if($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    # $sheet->set_column($col, $col++, 15) if($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    my @columnsWidth = (30);
    push(@columnsWidth, 30) if($PARAMS{"type"} eq "uniprot");
    push(@columnsWidth, 15);
    push(@columnsWidth, 15)if($PARAMS{"Statistics"}{"value"} eq "anova_fc" || $PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    push(@columnsWidth, 15) if($PARAMS{"Statistics"}{"value"} eq "anova_fc_tukey");
    setColumnsWidth($sheet, @columnsWidth);
    
    # add map sheet
    $sheet = $workbook->add_worksheet("Maps");
    $rowNumber = 0;
    my $field = ($PARAMS{"type"} eq "uniprot" ? "protein" : "cpd");
    writeExcelLineF($sheet, $rowNumber++, $formatH, ($PARAMS{"type"} eq "uniprot" ? "Accession numbers" : "Identifiers"), "Status", "Nb maps", "Pathway Map:level_1:level_2");
    $sheet->freeze_panes($rowNumber);
    my $rows = $dbh->selectall_arrayref("SELECT $field, color, count($field) FROM map GROUP BY $field");
    foreach my $acc (@$rows) {
        my $pathes = $dbh->selectall_arrayref("SELECT path FROM map WHERE $field='$$acc[0]'");
        my @maps;
        foreach my $path (@$pathes) {
            my ($num) = $$path[0] =~ /(\d+)/;
            my ($name, $class) = extractInfo("$DIR_INFO/$num.txt");
            if (length($class) == 0){
                push(@maps, "map:$num:$name");
            } else {
                push(@maps, "map:$num:$name:$class");
            };
        }
        my ($ac, $color, $nb) = @$acc;
        writeExcelLineF($sheet, $rowNumber, $formatMaps, $ac, "", $nb, join("\n", @maps));
        # adjust line height
        $sheet->set_row($rowNumber, $nb * 12) if($nb > 1);
        # colorize the Color cell
        if($color eq "Y") { $sheet->write($rowNumber++, 1, $COLORMEANING{$color}, $formatY);
        } elsif($color eq "G") { $sheet->write($rowNumber++, 1, $COLORMEANING{$color}, $formatG);
        } elsif($color eq "B") { $sheet->write($rowNumber++, 1, $COLORMEANING{$color}, $formatB);
        } elsif($color eq "R") { $sheet->write($rowNumber++, 1, $COLORMEANING{$color}, $formatR);
        }
    }
    $sheet->autofilter(0, 0, $rowNumber - 1, 3);
    setColumnsWidth($sheet, 25, 30, 15, 100);
    
    # add pathway sheet
    $sheet = $workbook->add_worksheet("Pathways");
    $rowNumber = 0;
    if($PARAMS{"type"} eq "uniprot") {
      writeExcelLineF($sheet, $rowNumber++, $formatH, "Map", "Name", "Level 1", "Level 2", "Nb proteins", "Proteins");
    } else {
      writeExcelLineF($sheet, $rowNumber++, $formatH, "Map", "Name", "Level 1", "Level 2", "Nb compounds", "Compounds");
    }
    $sheet->freeze_panes($rowNumber);
    foreach my $map (glob("$DIR_DRAW/*.xml")) {
        my ($num) = $map =~ /(\d+)/;
        my ($name, $class) = extractInfo("$DIR_INFO/$num.txt");
        my ($level1, $level2) = ("", "");
        ($level1, $level2) = split("; ", $class) if(length($class) != 0);
        $dbh->do("DROP VIEW IF EXISTS view_map");
        my $sql = "";
        if($PARAMS{"type"} eq "uniprot") {
            $sql = "CREATE VIEW view_map AS SELECT protein, color, keggid FROM map WHERE path=\"path:$taxonomy$num\"";
        } else {
            $sql = "CREATE VIEW view_map AS SELECT cpd, color, path FROM map WHERE path=\"path:map$num\"";
        }
        my $sth = $dbh->prepare($sql);
        $sth->execute();
        my @rows = @{$dbh->selectall_arrayref("SELECT $field FROM view_map")};
        my $proteins = "";
        foreach my $acc (@rows) {
            $proteins .= "@$acc,";
        }
        $proteins =~ s/\,$//;
        writeExcelLine($sheet, $rowNumber++, "$taxonomy$num", $name, $level1, $level2, scalar(@rows), $proteins);
    }
    $sheet->autofilter(0, 0, $rowNumber - 1, 5);
    setColumnsWidth($sheet, 15, 50, 40, 40, 15, 50);

    $dbh->disconnect();
    $workbook->close();
    print "Excel file '$outputFile' is complete\n";

}

sub extractInfo {
    my ($file) = @_;
    open(my $fh, "<", $file) or stderr("Can't open file '$file': $!");
    my $name = "";
    my $class = "";
    while(<$fh>) {
        chomp;
        $name = $1 if(m/^NAME\s+(.*)/);
        $class = $1 if(m/^CLASS\s+(.*)/);
        last if($name ne "" && $class ne "");
    }
    close $fh;
    return ($name, $class);
}


