#!/usr/bin/perl -w
########################################################################
#
# @(#) name_slides.pl   v1.0   2009/10/19   Tim Smith
#
#  Rename photos from the form Image{1}.tif to Slide_2C1_{01}.tif
#
########################################################################
use strict;
use diagnostics;
use File::Copy;
my $set = "1V2";

my $dir = "/Users/Tim/Archive/Photo_Masters/Slides/1/Slides_$set";
opendir(D,$dir) or die "cannot opendir \"$dir\"";
foreach my $photo (readdir(D)) {
  my $photo_old = $dir."/".$photo;
#  next unless $photo =~ s/Image(\d+)\.tif/sprintf("%s\/Slide_%s_%02d.tif",$dir,$set,$1)/eg;
  next unless $photo =~ s/\.jpg/\.tif/g;
  printf("Moved\n $photo_old\n $photo\n");
  move("$photo_old","$photo");
} 
closedir(D);
exit 0;
