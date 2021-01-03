#!/usr/bin/perl -w
use strict;
my $TransFile = "/Users/Tim/Tools/Scripts/PhotoTransferResults_run1";
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
