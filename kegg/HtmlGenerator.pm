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
my $TRANSLATE = 6;

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
  my ($data, $excludedStatus, @ids) = @_;
  # $data{userId}{site} -> status_key
  return "Default" if(scalar(@ids) == 0);
  my %keys;
  foreach my $id (@ids) {
    foreach my $site (keys(%{$data->{$id}})) {
      # $keys{$data->{$id}{$site}}++;
      foreach my $condition (sort(keys(%{$data->{$id}{$site}}))) {
        # $keys{$data->{$id}{$site}{$condition}}++;
        my $status = $data->{$id}{$site}{$condition};
        $keys{$status}++ if($status ne $excludedStatus);
        # $keys{$status}++;
      }
    }
  }
  return join(SEP, sort(keys(%keys)));
}

sub makeTooltipText {
  my ($data, $indicateSite, $conditions, $indicateConditions, $indicateStatus, $excludedStatus, @ids) = @_;
  # $data{userId}{site}{condition} -> status_key
  # if $indicateSite eq 0, then there will be only one site per id
  my %text;
  my $nbRows = 0;
  foreach my $id (@ids) {
    foreach my $site (sort(keys(%{$data->{$id}}))) {
      foreach my $cnd (sort(keys(%{$data->{$id}{$site}}))) {
        my $key = $data->{$id}{$site}{$cnd};
        next if($key eq $excludedStatus);
        $key = "NA" if($indicateStatus eq 0);
        $text{$nbRows}{"text"} = $indicateSite eq 1 ? "$id at site $site" : "$id";
        $text{$nbRows}{"text"} .= $indicateConditions eq 1 ? " [".$conditions->{$cnd}."]" : "";
        $text{$nbRows++}{"status"} = $key;
      }
    }
  }
  return \%text;
}

sub makeTooltipBox {
  my ($id, $name, $lines, $ind) = @_;
  return "" if(scalar(%$lines) == 0);
  my $tt = $ind."<div id=\"${id}tt\" class=\"TT\">\n";
  $tt .= "$ind\t<p class=\"title\">$name</p>\n";
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
  $css .= $ind."a.rect, a.arrow, a.circ, a.line { border: 3px solid transparent; position: absolute; z-index: 10; }\n";
  $css .= $ind."a.rect.rounded { border-radius: 10px; }\n";
  $css .= $ind."a.circ { border-radius: 50%; mask-image: radial-gradient(circle, transparent 40%, rgba(0, 0, 0, 1) 0); }\n";
  $css .= $ind."div.TT { visibility:hidden; width:max-content; max-width:500px; background-color:#f9f9f9; border:1px solid gray; color:black; position:absolute; left: 0; top: 0; z-index: 20; }\n";
  $css .= $ind."div#help { position:absolute; top:8px; left:8px; border:1px solid black; padding:1px 5px }\n";
  $css .= $ind."div#legend { visibility:hidden; width:max-content; background-color:#555; color:white; padding:5px 10px; position:fixed; left: 8px; top: 8px; z-index: 20; }\n";
  $css .= $ind."div#legend p { line-height: 10px; }\n";
  $css .= $ind."div#legend font { font-weight: bold; }\n";
  $css .= $ind."table#info { visibility:hidden; width:75%; background-color:#555; color:white; padding:5px 10px; position:fixed; left: 8px; top: 8px; z-index: 20; }\n";
  $css .= $ind."table#info td { min-width: 150px; vertical-align : top; }\n";
  $css .= $ind."table#info td a { color: #ffd561; }\n";
  $css .= $ind."table#info td a:hover { color: #fcba03; }\n";
  $css .= $ind."table#info td a:visited { color: #fcba03; }\n";
  $css .= $ind."table#info td a:visited:hover { color: #9e843e; }\n";
  my @ps = map {"p.$_"} keys(%$status);
  $css .= $ind.join(", ", @ps).", p.NA, p.title { line-height: 25px; padding: 0px 5px 0px 0px; margin: 0; border-bottom: 1px solid #ccc; }\n";
  my @psb = map {"p.${_}::before"} keys(%$status);
  $css .= $ind.join(", ", @psb).", p.NA::before { display:inline-block; width:25px; margin-right:5px; text-align:center; }\n";
  $css .= $ind."p.title { color: white; background-color: #555; padding-left: 10px; }\n";
  foreach my $key (keys(%$status)) {
    $css .= $ind."p.${key}::before { content:\"".$status->{$key}{"symbol"}."\"; background-color:".$status->{$key}{"color"}."; }\n";
    $css .= $ind."p.${key}::after { content:\": ".$status->{$key}{"text"}."\"; }\n";
  }
  $css .= $ind."p.NA::before { content:\"\\2022\"; background-color:white; color: #555; }\n";
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
  $css .= $ind."a.blink { animation: 1s linear infinite jiggler; }\n";
  $css .= $ind."\@keyframes jiggler { from { transform: rotate(0deg) translateX(10px) rotate(0deg); } to { transform: rotate(360deg) translateX(10px) rotate(-360deg); }}\n";
  return $css;
}

sub makeJs {
  # if one day we want to display elements without having to keep a key pressed:
  # then comment the keyup listener, and use the following methods
  # function toggle(e) { e.style.visibility=e.style.visibility=='visible'?'hidden':'visible'; }
  # function toggleClass(e,c) { e.classList.toggle(c); }
  my ($ind) = @_;
  my $js .= $ind."function moveTooltip(e){var tt = document.getElementById(this.id + 'tt');var n = 15;var lmin = e.pageX + n;var tmin = e.pageY + n*2;var ttleft = Math.min(lmin, window.innerWidth + window.pageXOffset - tt.offsetWidth - n*2);var tttop = Math.min(tmin, window.innerHeight + window.pageYOffset - tt.offsetHeight - n*2);if(ttleft != lmin + n && tttop != tmin) tttop = e.pageY - tt.offsetHeight - n*2;tt.style.left = ttleft + 'px';tt.style.top = tttop + 'px';};\n";
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
  $js .= $ind."\t} else if(event.keyCode == 69) {\n";
  $js .= $ind."\t\tdocument.getElementById('info').style.visibility = 'visible';\n";
  $js .= $ind."\t} else if(event.keyCode == 76) {\n";
  $js .= $ind."\t\tdocument.getElementById('legend').style.visibility = 'visible';\n";
  $js .= $ind."\t} else if(event.keyCode == 74) {\n";
  $js .= $ind."\t\tfor(var i = 0; i < items.length; i++) { items[i].classList.add('blink'); }\n";
  $js .= $ind."\t}\n";
  $js .= $ind."});\n";
  $js .= $ind."document.addEventListener('keyup', event => {\n";
  $js .= $ind."\tif(event.keyCode == 72) for(var i = 0; i < anchors.length; i++) { anchors[i].classList.remove('h'); };\n";
  $js .= $ind."\tif(event.keyCode == 74) for(var i = 0; i < items.length; i++) { items[i].classList.remove('blink'); };\n";
  $js .= $ind."\tif(event.keyCode == 69) document.getElementById('info').style.visibility = 'hidden';\n";
  $js .= $ind."\tif(event.keyCode == 76) document.getElementById('legend').style.visibility = 'hidden';\n";
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
  my @points = map { $_ + $TRANSLATE } split(",", $points);
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
  my @points = map { $_ + $TRANSLATE } split(",", $points);
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
  my ($status, $excludedStatus, $indicateStatus, $ind) = @_;
  my $bull1 = "&bull;&nbsp;";
  my $bull2 = "&nbsp;&nbsp;&nbsp;&bull;&nbsp;";
  my $legend = "<div id=\"legend\">\n";
  $legend .= "$ind\t<p>$bull1 The elements can have one or more of the following shape:</p>\n";
  $legend .= "$ind\t<p>$bull2 Rectangles represent a gene product and its complex (including an ortholog group)</p>\n";
  $legend .= "$ind\t<p>$bull2 Round rectangles represent a linked pathway</p>\n";
  $legend .= "$ind\t<p>$bull2 Lines represent a reaction or a relation (and also a gene or an ortholog group)</p>\n";
  $legend .= "$ind\t<p>$bull2 Circles specify any other molecule such as a chemical compound and a glycan</p>\n";
  if($indicateStatus eq 1) {
    $legend .= "$ind\t<p>$bull1 An element can have one or more of the following status:</p>\n";
    foreach my $key (keys(%$status)) {
      next if($key eq $excludedStatus);
      $legend .= "$ind\t<p>$bull2 Symbol <font style=\"color:".$status->{$key}{"color"}."\">".$status->{$key}{"html"}."</font> means \"".$status->{$key}{"text"}."\": ".$status->{$key}{"description"}."</p>\n";
    }
  }
  $legend .= "$ind\t<p>$bull1 Shortcuts:</p>\n";
  $legend .= "$ind\t<p>$bull2 Press 'E' to display information on the current Entry</p>\n";
  $legend .= "$ind\t<p>$bull2 Press 'J' to make the elements Jiggle</p>\n";
  $legend .= "$ind\t<p>$bull2 Press 'H' to Highlight the other links</p>\n";
  $legend .= "$ind</div>\n";
  return $legend;
}

sub parseInfo {
  my ($value) = @_;
  return $1 if($value =~ m/^([^\s]+) \[.*\]/);
  return $value;
}
sub getInfoRow {
  my ($name, $info, $tag, $link, $ind) = @_;
  return "" if(!exists($info->{$tag}));
  my $rows = "";
  foreach my $value (@{$info->{$tag}}) {
    my $content = $value;
    if($link ne "") {
      my $id = parseInfo($value);
      $content = "<a href='https://www.kegg.jp/".($link eq "e" ? "entry" : "pathway")."/$id' target='_blank'>$value</a>";
    }
    $rows .= "$ind<tr><td>$name</td><td>$content</td></tr>\n";
    $name = ""; # only print it once
  }
  return $rows;
}
sub getInfo {
  my ($info, $ind) = @_;
  my $legend = "<table id=\"info\">\n";
  $legend .= "\t".getInfoRow("Entry", $info, "ENTRY", "e", $ind);
  $legend .= "\t".getInfoRow("Name", $info, "NAME", "", $ind);
  $legend .= "\t".getInfoRow("Description", $info, "DESCRIPTION", "", $ind);
  $legend .= "\t".getInfoRow("Class", $info, "CLASS", "", $ind);
  $legend .= "\t".getInfoRow("Pathway map", $info, "PATHWAY_MAP", "p", $ind);
  $legend .= "\t".getInfoRow("Organism", $info, "ORGANISM", "", $ind);
  $legend .= "\t".getInfoRow("Related pathways", $info, "REL_PATHWAY", "e", $ind);
  $legend .= "\t".getInfoRow("KO pathways", $info, "KO_PATHWAY", "e", $ind);
  $legend .= "$ind</table>\n";
  return $legend;
}

sub createHtmlFile {
  my ($confFile, $pngFile, $info, $outputFile, $kegg, $data, $status, $indicateSite, $conditions, $indicateConditions, $indicateStatus, $excludedStatus) = @_;
  # $kegg{userId}{keggId} -> array(pathway)
  # $data{userId}{site}{condition_id} -> status_key
  # $conditions{condition_id} -> condition_name
  # $status{status_key} -> {id: int, text: string, color: #ffffff, symbol: \1234, html: &#4567;}
  $VERBOSE = $confFile =~ m/03050.conf/ ? 1 : 0;
  
  # get the actual size of the png image
  my ($imgWidth, $imgHeight) = imgsize($pngFile);
  my @names = @{$info->{"NAME"}};
  
  # create the HTML file and header
  open(my $fho, ">", $outputFile) or LsmboFunctions::stderr("Can't create output file '$outputFile': $!");
  print $fho "<!DOCTYPE html>\n";
  print $fho "<html>\n";
  print $fho "\t<head>\n";
  print $fho "\t\t<title>".$names[0]."</title>\n";
  print $fho "\t\t<style>\n".makeCss($status, "\t\t\t")."\t\t</style>\n";
  print $fho "\t</head>\n";
  print $fho "\t<body>\n";
  print $fho "\t\t".getImage($pngFile, $imgWidth, $imgHeight)."\n";
  print $fho "\t\t<div id='help'>Press L to display the legend</div>\n";
  print $fho "\t\t".getLegend($status, $excludedStatus, $indicateStatus, "\t\t")."\n";
  print $fho "\t\t".getInfo($info, "\t\t")."\n";
  
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
      my $left = $1 - $r/2 + $TRANSLATE;
      my $top = $2 - $r/2 + $TRANSLATE;
      $style = "left:${left}px;top:${top}px;width:${r}px;height:${r}px;";
    } elsif($type =~ m/line \(([\d,]+)\) (\d+)/) {
      $class = "line";
      $style = getLineClipPath($1);
    } elsif($type =~ m/poly \(([\d,]+)\)/) {
      $class = "arrow";
      $style = getArrowClipPath($1);
    } elsif($type =~ m/rect \((\d+),(\d+)\) \((\d+),(\d+)\)/) {
      $class = "rect";
      my $left = $1 + $TRANSLATE;
      my $top = $2 + $TRANSLATE;
      my $rw = $3 - $1; my $rh = $4 - $2;
      $style = "left:${left}px;top:${top}px;width:${rw}px;height:${rh}px;";
      $class .= "rounded" if($url =~ m/pathway/);
    }
    
    my @ids = getAssociatedIds($url, $kegg);
    my $fullStatus = "";
    my $lines;
    $fullStatus = getFullStatus($data, $excludedStatus, @ids);
    $lines = makeTooltipText($data, $indicateSite, $conditions, $indicateConditions, $indicateStatus, $excludedStatus, @ids);
    my $tooltip = makeTooltipBox("A$id", $name, $lines, "\t\t");
    
    my $title = "title=\"$name\"";
    if($tooltip ne "") {
      $class .= " WITHTT $fullStatus";
      $title = ""; # it's in the tooltip
    }
    print $fho "\t\t<a id=\"A$id\" class=\"$class\" style=\"$style\" $title href=\"".KEGG_URL."$url\" target=\"_blank\"></a>\n";
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
