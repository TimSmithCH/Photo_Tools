#!/usr/bin/perl -w
########################################################################
#
# @(#) BulkOperations.pl   v1.0   2011/09/19   Tim Smith
#
#  Automate operations of mutiple files
#
########################################################################
use lib "/Users/Tim/Code/PhotoOps";   # Add Tims code directory to @INC path
use strict;
use diagnostics;
use Getopt::Long;

##################################
# Parse the command line options #
##################################
my $date = "-";
my $location = "-";
my $neg_set = "AA";
my $date_seq = "-";
my $start_seq = "01";
my $end_seq = "36";
my $DEBUG = 0;
my $help = 0;
GetOptions("when=s" => \$date,
           "negatives=s" => \$neg_set,
           "location=s" => \$location,
           "sseq=s" => \$start_seq,
           "eseq=s" => \$end_seq,
           "debug" => \$DEBUG,
           "help!" => \$help);
if ($help || $date eq "-") {
  print "\nUsage:  BulkOperations.pl -negatives NEG_SET -sseq START_SEQ -eseq END_SEQ -when DATE [-debug] [-help]\n";
  print "Example:  BulkOperations.pl -n LP -sseq 02 -eseq 09 -w \"1989:06:01\"\n\n";
  exit 0;
}

my $filename;
# 3   Digital Camera
# 2   Scanned from Print
# 1   Scanned from Film: Negatives
# 0   Scanned from Film: Slides
my $dirlett = substr($neg_set, 0, 1);
my $dir = "/Users/Tim/Archive/Photo_Masters/Negatives/$dirlett/Negatives_$neg_set";
chdir($dir);
opendir(DIR, $dir) || die "can't opendir $dir: $!";
while (defined($filename = readdir(DIR))) {
  my $cmd = "nop";
  next if ($filename =~ /^\..*/);
  next unless (my $seq) = $filename =~ /.*(\d{2})\.tif/;
  next if ($seq<$start_seq || $seq>$end_seq);
  $date_seq = sprintf("%10s 11:11:%02d",$date,$seq);
  if ($location ne "-") {
    $cmd = "/Users/Tim/Code/PhotoOps/TagPhoto.pl -f \"$filename\" -s 2 -l \"$location\" -w \"$date_seq\"";
  } else {
    $cmd = "/Users/Tim/Code/PhotoOps/TagPhoto.pl -f \"$filename\" -s 2 -w \"$date_seq\"";
  }
#  printf("%s\n", $cmd);
  system($cmd);
}
closedir DIR;
exit 0;
