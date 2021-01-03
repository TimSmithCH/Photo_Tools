#!/usr/bin/perl -w
use strict;
my $filename;
my $dir = "/Users/Tim/Archive/Photo_Masters/2011/08/02";
chdir($dir);
opendir(DIR, $dir) || die "can't opendir $dir: $!";
while (defined($filename = readdir(DIR))) {
  next if ($filename =~ /^\..*/);
  my $camera = `exiftool -X \"$filename\" | grep IFD0:Model`;
  if ($camera =~ /.*A1200.*/) {
    my $filenamenew = $filename;
    $filenamenew =~ s/-/:/g;
    $filenamenew =~ s/at //g;
    $filenamenew =~ s/.JPG//g;
    my $cmd = "/Users/Tim/Tools/Scripts/TagPhoto.pl -f \"$filename\" -w \"$filenamenew\"";
#    print "$cmd\n";
    system($cmd);
  }
}
closedir DIR;
exit 0;
