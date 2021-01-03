#!/usr/bin/perl -w
use strict;
my $filename;
my $dir = "/Users/Tim/Archive/Photo_Masters/Slides/GG_Walker/Guernsey_1972";
chdir($dir);
opendir(DIR, $dir) || die "can't opendir $dir: $!";
while (defined($filename = readdir(DIR))) {
  next if ($filename =~ /^\..*/);
#  my $olddate = `exiftool -X \"$filename\" | grep ExifIFD:DateTimeOriginal | sed -e "s/ \<ExifIFD:DateTimeOriginal\>//" | sed -e "s/\<\\/ExifIFD:DateTimeOriginal\>//"`;
  my $olddate = `exiftool -X \"$filename\" | grep IFD0:ModifyDate | sed -e "s/ \<IFD0:ModifyDate\>//" -e "s/\<\\/IFD0:ModifyDate\>//" -e "s/[[:digit:]][[:digit:]][[:digit:]][[:digit:]]\.[[:digit:]][[:digit:]]/1972.08/" -e "s/\\./:/g"`;
  if ($olddate eq "") {
    print "No date found in $filename\n";
    next;
  }
  my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -p \"$filename\" -w \"$olddate\"";
#  print "$cmd\n";
  system($cmd);
}
closedir DIR;
exit 0;
