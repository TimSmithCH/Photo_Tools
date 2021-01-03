#!/usr/bin/perl -w
use strict;
my @people = ();
my %persons = ();
my $TransFile = "/Users/Tim/Archive/Photo_Information/PhotoTransferResults_run4";
open (TRANSFILE, "<$TransFile");
while (<TRANSFILE>) {
  if (/\sKeywords:\s(.*$)/) {
    @people = split(/\s/,$1);
    foreach my $p (@people) {
      $persons{$p} = 1;
    }
  }
} 
foreach my $p (sort keys %persons) {
  print "$p\n";
}
close(TRANSFILE);
exit 0;
