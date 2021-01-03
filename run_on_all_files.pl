#!/usr/bin/perl -w
use strict;
#####################################################
# 3   Digital Camera
# 2   Scanned from Print
# 1   Scanned from Film: Negatives
# 0   Scanned from Film: Slides
#####################################################
my $filename;
my $timer = 0;
my $timerd;
#
### Directory to operate on ###
my $dir = "/Users/Tim/Archive/Photo_Masters/2012/08/23";
#my $dir = "/Users/Tim/Archive/Photo_Masters/Hard_Copies/2000";
#my $dir = "/Users/Tim/Archive/Photo_Masters/Negatives/N/Negatives_NG";
#my $dir = "/Users/Tim/Archive/Photo_Masters/Slides/1/Slides_1O1";
#my $dir = "/Users/Tim/Archive/Photo_Masters/Slides/GG_Walker/Guernsey_1966";
#
chdir($dir);
opendir(DIR, $dir) || die "can't opendir $dir: $!";
while (defined($filename = readdir(DIR))) {
  next if ($filename =~ /^\..*/);
#  next if ($filename !~ /^DSC0.*/);
#  next if ($filename !~ /^2000_Sark.*/);
#  next if ($filename =~ /.* 21-5\d{1}-\d{2}\.JPG/);
#  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -s 1";
#  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -l \"Petit Vélan\" -s 0 -w \"1993:04:04 11:11:11\"";
  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -c \"Esplanade\" -l \"Manhatten Down-town\"";
### Only update GPS not the location names ###
#  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -g -l \"Saint Cyrus\"";
### Append mode to preserve GPS information in iPhoto photos ###
#  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -a -f \"$filename\" -l \"New York\"";
### Tag times incrementally ###
#  $timer += 1;
#  $timerd = sprintf("%02d",$timer);
#  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -s 0 -l Uxmal -w \"1993:12:03 11:11:$timerd\"";
#  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -s 1 -w \"1989:03:27 11:11:$timerd\"";
#  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -s 2 -l Sark -w \"2000:07:16 11:11:$timerd\"";
#  my $cmd = "/usr/local/bin/exiftool -IPTC:Sub-location= \"$filename\"";
### Debug ###
#  printf("%s\n", $cmd);
### Execute ###
  system($cmd);
}
closedir DIR;
exit 0;
