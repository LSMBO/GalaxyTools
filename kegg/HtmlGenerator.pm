#!/usr/bin/perl
package HtmlGenerator;

use strict;
use warnings;
use Image::Size;
use MIME::Base64 qw(encode_base64);

use File::Basename;
use lib dirname(__FILE__)."/../Modules";
use LsmboFunctions;

# only export these methods so they can be used without specifying the namespace
use Exporter qw(import);
our @EXPORT = qw(createHtmlFile);

use constant KEGG_URL => "https://www.kegg.jp";
use constant SEP => "-";

my $VERBOSE = 0;

# sub getProteins {
sub getIds {
  my ($kegg, $keggId) = @_;
  # $kegg{userId}{keggId} -> array(pathway)
  my %ids;
  foreach my $id (sort(keys(%$kegg))) {
    next if(!exists($kegg->{$id}{$keggId}));
    next if(scalar(@{$kegg->{$id}{$keggId}}) == 0);
    $ids{$id} = 1;
  }
  return sort(keys(%ids));
}

# sub getAssociatedProteins {
sub getAssociatedIds {
  my ($url, $kegg) = @_;
  # /dbget-bin/www_bget?hsa:2203+hsa:8789
  # $kegg{userId}{keggId} -> array(pathway)
  my %ids;
  # extract the kegg ids from the url
  $url =~ s/.*\?//;
  foreach my $keggId (split(/\+/, $url)) {
    foreach (getIds($kegg, $keggId)) { $ids{$_}++; }
  }
  return sort(keys(%ids));
}

sub getFullStatus {
  my ($data, @ids) = @_;
  # $data{userId}{site} -> status_key
  return "Default" if(scalar(@ids) == 0);
  my %keys;
  foreach my $id (@ids) {
    foreach my $site (keys(%{$data->{$id}})) {
      $keys{$data->{$id}{$site}}++;
    }
  }
  return join(SEP, sort(keys(%keys)));
}

sub makeTooltipText {
  my ($data, $status, $indicateSite, @ids) = @_;
  # $data{userId}{site} -> status_key
  # $status{status_key} -> {id: int, text: string, color: #ffffff}
  # if $indicateSite eq 0, then there will be only one site per id
  my %text;
  my $nbRows = 0;
  my $maxNbChar = 0;
  foreach my $id (@ids) {
    foreach my $site (sort(keys(%{$data->{$id}}))) {
      my $key = $data->{$id}{$site};
      $text{$nbRows}{"text"} = $indicateSite eq 1 ? "Identifier $id at site $site" : "Identifier $id";
      $maxNbChar = length($text{$nbRows}{"text"}) if(length($text{$nbRows}{"text"}) > $maxNbChar);
      $text{$nbRows++}{"status"} = $key;
    }
  }
  return \%text;
}

sub makeTooltipBox {
  my ($id, $lines, $ind) = @_;
  return "" if(scalar(%$lines) == 0);
  my $tt = $ind."<div id=\"${id}tt\" class=\"TT\">\n";
  foreach my $id (sort(keys(%$lines))) {
    $tt .= "$ind\t<p class=\"".$lines->{$id}{"status"}."\">".$lines->{$id}{"text"}."</p>\n";
  }
  $tt .= "$ind</div>\n";
  return $tt;
}

# if we have 4 status, we want to make the equivalent of 4 for loops within each other
# start with an empty combination
# add one item, four times consecutively
sub getAllCombinations {
  my ($status, $nbStatus, @current) = @_;
  # stop condition: the combination is long enough
  return join(SEP, @current) if(scalar(@current) eq $nbStatus);
  # otherwise, loop on each item
  my @combinations;
  for my $i (0 .. $nbStatus - 1) {
    push(@combinations, getAllCombinations($status, $nbStatus, (@current, $status->[$i])));
  }
  return @combinations;
}

sub getCombinations {
  my (@status) = @_;
  my %combinations;
  # generate all possible combinations (KO, KO-KO, KO-KO-UP, KO-DO-UP-KO, ...)
  foreach my $cmb (getAllCombinations(\@status, scalar(@status),())) {
    # put the items in a hash to remove consecutive keys (KO, KO, KO-UP, DO-KO-UP, ...)
    my %items = map { $_ => 1 } split(SEP, $cmb);
    # remove a potential empty item
    delete $items{""};
    # sort the items to avoid duplicates later (KO, KO-KO, KO-KO-UP, DO-KO-KO-UP, ...)
    my $combination = join(SEP, sort(keys(%items)));
    # do not store a potential empty combination
    next if($combination eq "");
    # put the simplified combination in the main hash
    $combinations{$combination} = 1;
  }
  return sort(keys(%combinations));
}

sub makeCss {
  my ($status, $ind) = @_;
  my $css = $ind."html { font-family:Calibri; }\n";
  $css .= $ind."a { z-index: 50; }\n";
  $css .= $ind."a.h.rect, a.h.circ { border-color:#f2549e; }\n";
  $css .= $ind."a.h.arrow, a.h.line { background-color:#f2549e; }\n";
  $css .= $ind."a.rect, a.arrow, a.circ, a.line { border: 3px solid transparent; position: absolute; transform: translate(6px, 6px); z-index: 10; }\n";
  $css .= $ind."a.rect.rounded { border-radius: 10px; }\n";
  $css .= $ind."a.circ { border-radius: 50%; mask-image: radial-gradient(circle, transparent 40%, rgba(0, 0, 0, 1) 0); }\n";
  $css .= $ind."div.TT { visibility:hidden; width:max-content; background-color:#f9f9f9; border:1px solid gray; color:black; padding:5px 10px; position:absolute; left: 0; top: 0; z-index: 20; }\n";
  $css .= $ind."div#legend { visibility:hidden; width:max-content; background-color:#555; color:white; padding:5px 10px; position:absolute; left: 8px; top: 8px; z-index: 20; }\n";
  $css .= $ind."div#legend p { line-height: 10px; }\n";
  $css .= $ind."div#legend font { font-weight: bold; }\n";
  my @ps = map {"p.$_"} keys(%$status);
  $css .= $ind.join(", ", @ps)." { padding-top:5px; margin: 0; }\n";
  my @psb = map {"p.${_}::before"} keys(%$status);
  $css .= $ind.join(", ", @psb)." { display:inline-block; width:20px; height:20px; border:1px solid gray; border-radius:25%; margin-right:5px; text-align:center; }\n";
  foreach my $key (keys(%$status)) {
    $css .= $ind."p.${key}::before { content:\"".$status->{$key}{"symbol"}."\"; background-color:".$status->{$key}{"color"}."; }\n";
    $css .= $ind."p.${key}::after { content:\": ".$status->{$key}{"text"}."\"; }\n";
  }
  my @combinations = getCombinations(SEP, keys(%$status));
  foreach my $combination (@combinations) {
    my @colors;
    foreach (split(SEP, $combination)) {
      push(@colors, $status->{$_}{"color"});
    }
    # if only one color (ie. DO or OK), double the color to make a gradient from A to A
    push(@colors, $colors[0]) if(scalar(@colors) eq 1);
    # add the rules
    $css .= $ind."a.$combination { border-image: linear-gradient(to right, ".join(", ", @colors).") 1; }\n";
    $css .= $ind."a.arrow.$combination, a.line.$combination { background-image: linear-gradient(to right, ".join(", ", @colors)."); }\n";
  }
  return $css;
}

sub makeJs {
  my ($ind) = @_;
  my $js .= $ind."function moveTooltip(e){ var tt = document.getElementById(this.id + 'tt');var n = 15;var newX = e.clientX + n;var newY = e.clientY + n;if(newX + tt.offsetWidth >= window.innerWidth && newY + tt.offsetHeight >= window.innerHeight) {newX = window.innerWidth - tt.offsetWidth - n*2;newY = e.clientY - tt.offsetHeight - n*2;} else if(newX + tt.offsetWidth >= window.innerWidth) {newX = window.innerWidth - tt.offsetWidth - n*2;} else if(newY + tt.offsetHeight >= window.innerHeight) {newY = window.innerHeight - tt.offsetHeight - n*2 + (e.pageY-e.clientY);}tt.style.left = newX + 'px';tt.style.top = newY + 'px';tt.style.opacity = 1;};\n";
  $js .= $ind."function showTooltip(e){ document.getElementById(this.id + 'tt').style.visibility = 'visible'; };\n";
  $js .= $ind."function hideTooltip(e){ document.getElementById(this.id + 'tt').style.visibility = 'hidden'; };\n";
  $js .= $ind."var items = document.getElementsByClassName('WITHTT');\n";
  $js .= $ind."var anchors = document.getElementsByTagName('a');\n";
  $js .= $ind."for(var i = 0; i < items.length; i++) {\n";
  $js .= $ind."\titems[i].addEventListener('mousemove', moveTooltip);\n";
  $js .= $ind."\titems[i].addEventListener('mouseenter', showTooltip);\n";
  $js .= $ind."\titems[i].addEventListener('mouseleave', hideTooltip);\n";
  $js .= $ind."};\n";
  $js .= $ind."document.addEventListener('keydown', event => {\n";
  $js .= $ind."\tif(event.keyCode == 72) {\n";
  $js .= $ind."\t\tfor(var i = 0; i < anchors.length; i++) { anchors[i].classList.add('h'); }\n";
  $js .= $ind."\t} else if(event.keyCode == 76) {\n";
  $js .= $ind."\t\tdocument.getElementById('legend').style.visibility = 'visible';\n";
  $js .= $ind."\t}\n";
  $js .= $ind."});\n";
  $js .= $ind."document.addEventListener('keyup', event => {\n";
  $js .= $ind."\tfor(var i = 0; i < anchors.length; i++) { anchors[i].classList.remove('h'); };\n";
  $js .= $ind."\tdocument.getElementById('legend').style.visibility = 'hidden';\n";
  $js .= $ind."});\n";
  return $js;
}

sub getImage {
  my ($pngFile, $width, $height) = @_;
  open (my $fh, "<", $pngFile) or LsmboFunctions::stderr("$!");
  binmode($fh);
  local $/;
  my $file_contents = <$fh>;
  close $fh;
  my $base64 = encode_base64($file_contents);
  $base64 =~ s/\r?\n//g;
  return "<img width=\"${width}px\" height=\"${height}px\" src=\"data:image/png;base64,$base64\" />";
}

sub getTopLeftWidthHeight {
  my @points = @_; # ie. 877,777,873,768,880,768
  my $minX = 0; my $maxX = 0;
  my $minY = 0; my $maxY = 0;
  for(my $i = 0; $i < scalar(@points); $i += 2) {
    $minX = $points[$i] if($minX eq 0 || $points[$i] < $minX);
    $minY = $points[$i+1] if($minY eq 0 || $points[$i+1] < $minY);
    $maxX = $points[$i] if($points[$i] > $maxX);
    $maxY = $points[$i+1] if($points[$i+1] > $maxY);
  }
  my $width = $maxX - $minX;
  my $height = $maxY - $minY;
  return ($minY, $minX, $width, $height);
}

sub getLineClipPath {
  my ($points) = @_; # ie. 877,777,873,768,880,768
  my @points = split(",", $points);
  die("Odd number of points not allowed") if(scalar(@points) % 2 != 0);
  # get values top, left, width and height
  my ($top, $left, $width, $height) = getTopLeftWidthHeight(@points);
  # add coordinates twice, with a small modification to avoid an invisible 1D shape
  my @coords;
  my $tr = 3;
  my @forward;
  for(my $i = 0; $i < scalar(@points); $i += 2) {
    my $x = $points[$i] - $left + $tr - 1;
    my $y = $points[$i+1] - $top + $tr - 1;
    push(@forward, "${x},${y}");
  }
  my @backward;
  for(my $i = 0; $i < scalar(@points); $i += 2) {
    my $x = $points[$i] - $left + $tr + 1;
    my $y = $points[$i+1] - $top + $tr + 1;
    push(@backward, "${x},${y}");
  }
  push(@coords, @forward, reverse(@backward));
  
  return "top:${top}px;left:${left}px;width:${width}px;height:${height}px;clip-path:path('M ".join(" L ", @coords)." Z');";
}

sub round { return sprintf("%.2f", $_[0]); }

sub transformArrowSummit {
  # we have 3 points A, B and C
  my ($ax, $ay, $bx, $by, $cx, $cy, $n) = @_;
  
  # get the coordinates of the point BC between B and C
  my $BCx = ($bx + $cx) / 2;
  my $BCy = ($by + $cy) / 2;
  # calculate the equation of the line A_BC : y = A_BCa * x + A_BCb
  my $A_BCa = 0; # careful, $by can be equal to $cy (horizontal line)
  $A_BCa = ($BCy - $ay) / ($BCx - $ax) if($ax ne $BCx);
  my $A_BCb = $ay - $A_BCa * $ax;
  # get the distance between A and BC
  my $d = round(sqrt(($BCx - $ax)**2 + ($BCy - $ay)**2));
  
  # find the coordinates of the 2 points on the line A_BC with a distance of d+1 from point BC
  my $DeltaA = $A_BCa**2 + 1;
  my $DeltaB = -2 * $BCx + 2 * $A_BCa * $A_BCb - 2 * $A_BCa * $BCy;
  my $DeltaC = $BCx**2 + $BCy**2 - ($d+$n)**2 + $A_BCb**2 - 2 * $A_BCb * $BCy;
  my $delta = $DeltaB**2 - 4 * $DeltaA * $DeltaC;
  my $x1 = round((-1 * $DeltaB - sqrt($delta)) / (2 * $DeltaA));
  my $y1 = round($A_BCa * $x1 + $A_BCb);
  my $x2 = round((-1 * $DeltaB + sqrt($delta)) / (2 * $DeltaA));
  my $y2 = round($A_BCa * $x2 + $A_BCb);

  # get on which side is A compared to the line BC
  my $sideA = (($bx - $cx) * ($ay - $by) - ($by - $cy) * ($ax - $bx));
  # get on which side is Point 1 compared to the line BC
  my $side1 = (($bx - $cx) * ($y1 - $by) - ($by - $cy) * ($x1 - $bx));
  # return the point that is on the same side of line BC
  return $sideA > 0 && $side1 > 0 || $sideA < 0 && $side1 < 0 ? ($x1, $y1) : ($x2, $y2);
}

sub getTotalDistance {
  my @points = @_; # ie. 877,777,873,768,880,768
  my $distance = 0;
  for(my $i = 2; $i < scalar(@points); $i += 2) {
    $distance += sqrt(($points[0] - $points[$i])**2 + ($points[1] - $points[$i+1])**2);
  }
  return $distance;
}

sub transformArrowCoordinates {
  my @points = @_; # ie. 877,777,873,768,880,768
  if(scalar(@points) eq 8) {
    # if there are 4 points, it's also an arrow but we have to remove the central point
    # basic idea: for each point, sum the distances to all the others, the point with the lowest sum has to be removed
    my %distances;
    $distances{0} = getTotalDistance($points[0], $points[1], $points[2], $points[3], $points[4], $points[5], $points[6], $points[7]);
    $distances{2} = getTotalDistance($points[2], $points[3], $points[0], $points[1], $points[4], $points[5], $points[6], $points[7]);
    $distances{4} = getTotalDistance($points[4], $points[5], $points[0], $points[1], $points[2], $points[3], $points[6], $points[7]);
    $distances{6} = getTotalDistance($points[6], $points[7], $points[0], $points[1], $points[2], $points[3], $points[4], $points[5]);
    my @ids = sort { $distances{$a} <=> $distances{$b} } keys(%distances); # sort by distances
    my $removedId = shift(@ids); # remove the id with the lowest distance
    my @newPoints;
    for(my $i = 0; $i < scalar(@ids); $i++) {
      my $id = $ids[$i];
      push(@newPoints, $points[$id], $points[$id+1]);
    }
    @points = @newPoints; # replace the four points with the three points;
  }
  if(scalar(@points) ne 6) {
    my $n = scalar(@points) / 2;
    return @points;
  }
  # if there are 3 points, it's an arrow
  my $n = 2;
  my ($ax, $ay) = transformArrowSummit($points[0], $points[1], $points[2], $points[3], $points[4], $points[5], $n); # A B C
  my ($bx, $by) = transformArrowSummit($points[2], $points[3], $points[0], $points[1], $points[4], $points[5], $n); # B A C
  my ($cx, $cy) = transformArrowSummit($points[4], $points[5], $points[0], $points[1], $points[2], $points[3], $n); # C A B
  return ($ax, $ay, $bx, $by, $cx, $cy);
}

sub getArrowClipPath {
  my ($points) = @_; # ie. 877,777,873,768,880,768
  my @points = split(",", $points);
  my ($top, $left, $width, $height) = getTopLeftWidthHeight(@points);
  my @newPoints = transformArrowCoordinates(@points);
  my @coords;
  while(scalar(@newPoints) > 0) {
    my $x = shift(@newPoints) - $left + 3;
    my $y = shift(@newPoints) - $top + 3;
    push(@coords, "${x}px ${y}px");
  }
  return "top:${top}px;left:${left}px;width:${width}px;height:${height}px;clip-path:polygon(".join(", ", @coords).");";
}

sub getLegend {
  my ($status, $ind) = @_;
  my $legend = "<div id=\"legend\">\n";
  $legend .= "$ind\t<p>&bull;&nbsp;Rectangles represent a gene product and its complex (including an ortholog group)</p>\n";
  $legend .= "$ind\t<p>&bull;&nbsp;Round rectangles represent a linked pathway</p>\n";
  $legend .= "$ind\t<p>&bull;&nbsp;Lines represent a reaction or a relation (and also a gene or an ortholog group)</p>\n";
  $legend .= "$ind\t<p>&bull;&nbsp;Circles specify any other molecule such as a chemical compound and a glycan</p>\n";
  $legend .= "$ind\t<p>&bull;&nbsp;An element can have one or more of the following status:</p>\n";
  foreach my $key (keys(%$status)) {
    $legend .= "$ind\t<p>&nbsp;&nbsp;&nbsp;&bull;&nbsp;Symbol <font style=\"color:".$status->{$key}{"color"}."\">".$status->{$key}{"html"}."</font> means: '".$status->{$key}{"text"}."'</p>\n";
  }
  $legend .= "$ind\t<p>&bull;&nbsp;Press 'H' to visualize the clickable links</p>\n";
  $legend .= "$ind</div>\n";
  return $legend;
}

sub createHtmlFile {
  my ($confFile, $pngFile, $title, $outputFile, $kegg, $data, $status, $indicateSite) = @_;
  # $kegg{userId}{keggId} -> array(pathway)
  # $data{userId}{site} -> status_key
  # $status{status_key} -> {id: int, text: string, color: #ffffff, symbol: \1234, html: &#4567;}
  $VERBOSE = $confFile =~ m/01200.conf/ ? 1 : 0;
  # print "Creating $outputFile from $confFile\n";
  
  # get the actual size of the png image
  my ($imgWidth, $imgHeight) = imgsize($pngFile);
  
  # create the HTML file and header
  open(my $fho, ">", $outputFile) or LsmboFunctions::stderr("Can't create output file '$outputFile': $!");
  print $fho "<!DOCTYPE html>\n";
  print $fho "<html>\n";
  print $fho "\t<head>\n";
  print $fho "\t\t<title>$title</title>\n";
  print $fho "\t\t<style>\n".makeCss($status, "\t\t\t")."\t\t</style>\n";
  print $fho "\t</head>\n";
  print $fho "\t<body>\n";
  print $fho "\t\t".getImage($pngFile, $imgWidth, $imgHeight)."\n";
  print $fho "\t\t".getLegend($status, "\t\t")."\n";
  
  # create links for the SVG elements based on the coordinates of confFile
  my %items; my %itemsWithTooltips; my %tooltips;
  my $id = 1;
  open(my $fh, "<", $confFile) or LsmboFunctions::stderr("Can't open input file '$confFile': $!");
  while(<$fh>) {
    chomp;
    # example: circ (146,958) 4\t/dbget-bin/www_bget?C00033\tC00033 (Acetate)
    my ($type, $url, $name) = split(/\t/);
    my $style = "";
    my $class = "";
    
    if($type =~ m/circ \((\d+),(\d+)\) (\d+)/ || $type =~ m/filled_circ \((\d+),(\d+)\) (\d+)/) {
      $class = "circ";
      my $r = $3 * 1.5;
      my $left = $1 - $r/2;
      my $top = $2 - $r/2;
      $style = "left:${left}px;top:${top}px;width:${r}px;height:${r}px;";
    } elsif($type =~ m/line \(([\d,]+)\) (\d+)/) {
      $class = "line";
      $style = getLineClipPath($1);
    } elsif($type =~ m/poly \(([\d,]+)\)/) {
      $class = "arrow";
      $style = getArrowClipPath($1);
    } elsif($type =~ m/rect \((\d+),(\d+)\) \((\d+),(\d+)\)/) {
      $class = "rect";
      my $rw = $3 - $1; my $rh = $4 - $2;
      $style = "left:${1}px;top:${2}px;width:${rw}px;height:${rh}px;";
      $class .= "rounded" if($url =~ m/pathway/);
    }
    
    my @ids = getAssociatedIds($url, $kegg);
    my $fullStatus = getFullStatus($data, @ids);
    my $lines = makeTooltipText($data, $status, $indicateSite, @ids);
    my $tooltip = makeTooltipBox("A$id", $lines, "\t\t");
    
    $class .= " WITHTT $fullStatus" if($tooltip ne "");
    print $fho "\t\t<a id=\"A$id\" class=\"$class\" style=\"$style\" title=\"$name\" href=\"".KEGG_URL."$url\" target=\"_blank\"></a>\n";
    print $fho $tooltip; # will be "" if there is no tooltip
    $id++;
  }
  close $fh;
  
  # JS has to be written at the end, so the HTML elements already exist
  print $fho "\t\t<script type=\"text/javascript\">\n".makeJs("\t\t\t")."\t\t</script>\n";
  print $fho "\t</body>\n";
  print $fho "</html>";
  close $fho;
}

1;
