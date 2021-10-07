#!/usr/bin/perl
package LsmboMPI;

use strict;
use warnings;

use List::MoreUtils qw(uniq);
use Parallel::Loops;
use Sys::CpuAffinity;

# only export these methods so they can be used without specifying the namespace
use Exporter qw(import);
our @EXPORT = qw(getNbCpu removeSubSequencesMT runCommand);


sub getTotalCPUCount {
  return Sys::CpuAffinity::getNumCpus();
}

sub getNbCpu {
  # default ratio is 1/4 of all CPU
  my $default = 0.25;
  my $ratio = $default;
  $ratio = $_[0] if(scalar(@_));
  # only use the arg if it's a number between 0 and 1
  $ratio = $default if($ratio !~ m/^\d+\.?\d*$/ || $ratio > 1 || $ratio < 0);
  # get the total number of CPU
  my $nb = getTotalCPUCount();
  # only use 1 CPU if there is 1 or 2 CPU (or if the number could not be obtained)
  return 1 if(!$nb || $nb <= 2);
  # use the ratio given of the CPU otherwise
  return int($nb * $ratio);
}

# If we assume there is very little subsequences, then we may not need to care about 
# removing subsequences to avoid checking them twice.
# A multi-threaded approach could be to compare sequence i in [1..nbCPU] to all the others,
# and then moving to i+nbCPU, until the end of the list.
# This should reduce the complexity to N/nbCPU, even if the total number of comparisons get higher
sub removeSubSequencesMT {
  my @sequences = @{$_[0]};
  my $nbCPU = getNbCpu(0.75);
  print "Searching for sub sequences, using $nbCPU CPUs...\n";
  # sort the sequences shorter to longer
  my @sortedSequences = sort { length $a <=> length $b } @sequences;
  my $total = scalar(@sortedSequences);
  # prepare the parallelization
  my %returnValues;
  my $pl = Parallel::Loops->new($nbCPU);
  $pl->share(\@sortedSequences, \%returnValues);
  # start multi-threading
  $pl->foreach([1 .. $nbCPU], sub {
    my $n = $_;
    for(my $i = $n - 1; $i < $total; $i += $nbCPU) {
      my $shorterSequence = $sortedSequences[$i];
      my $isSub = 0;
      my $j = $i + 1;
      while($isSub == 0 && $j < $total) {
        # no need to compare this sequence to others
        if(index($sortedSequences[$j++], $shorterSequence) != -1) {
          push(@{$returnValues{$n}{"subseq"}}, $shorterSequence);
          $isSub = 1;
        }
      }
    }
  });
  # gather all the sub-sequences
  my @subSequences;
  for(1..$nbCPU) {
    if(exists($returnValues{$_}{"subseq"})) {
      my @subs = @{$returnValues{$_}{"subseq"}};
      push(@subSequences, @subs);
    }
  }
  @subSequences = sort(uniq(@subSequences));
  my $nbSubSequences = scalar(@subSequences);
  print STDOUT "$nbSubSequences sub sequences have been found in the $total protein sequences\n";
  return @subSequences;
}

# this function runs a list of commands in parallel.
# it assumes the arguments, input and output files are managed by the caller
sub runCommandList {
  my ($pctCpu, @commandList) = @_;
  # get number of CPU to use
  my $nbCPU = getNbCpu($pctCpu);
  # prepare the parallelization
  my $pl = Parallel::Loops->new($nbCPU);
  # start multi-threading
  $pl->foreach(\@commandList, sub {
    # s/\//\\/g;
    print("$_\n");
    system($_);
  });
}

1;
