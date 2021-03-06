#!/usr/bin/perl -w
use strict;
my $filename;
my $dir = "/Users/Tim/Temporary/Photo_Exports/2015 Calendar";
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
  my $cmd = "/Users/Tim/Code/TagPhoto.pl -f \"$filename\" -w \"$olddate\"";
#  print "$cmd\n";
  system($cmd);
}
closedir DIR;
exit 0;
