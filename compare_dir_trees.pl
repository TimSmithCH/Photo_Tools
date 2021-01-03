#!/usr/bin/perl -w
use strict;
my $olddir = "/Users/Tim/Temp/Picture from PC/";
my $newdir = "/Users/Tim/Archive/Photo_Masters/";
opendir(DIR, $olddir) || die "can't opendir $olddir: $!";
@dots = grep { /^\./ && −f "$some_dir/$_" } readdir(DIR);
closedir DIR;
open (TRANSFILE, "<$TransFile");
while (<TRANSFILE>) {
  if (/\sLocation:\s(.*$)/) {
    printf("%s == ", $1);
  } elsif (/\sGPS:\s(.*$)/) {
    printf("%s\n", $1);
  }
} 
close(TRANSFILE);
exit 0;
