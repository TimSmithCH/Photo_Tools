#!/usr/bin/perl -w
########################################################################
#
# @(#) ExtractMetaDataFromPSE.pl   v1.4   2009/12/22   Tim Smith
#
#  Consolidate the PSE metadata from the linked tables, decode the
#  keyword lookup and generate a simple metadata set per photo
#
########################################################################
use strict;
use diagnostics;
use utf8;  # To allow replacement strings to have accented characters
use Getopt::Long;
use Data::Dumper;
use MetaDataGym;

##################################
# Parse the command line options #
##################################
my $accelerate = -1;  # Flag to limit loops in order to speed up testing
my $NOWRITE = 0;
my $DEBUG = 0;
my $help = 0;
GetOptions("accelerate=s" => \$accelerate,
           "debug=s" => \$DEBUG,
           "nowrite=s" => \$NOWRITE,
           "help!" => \$help);
if ($help) {
  print "\nUsage:  ExtractMetaData.pl -accelerate LEVEL [-debug DEBUG] [-nowrite NOWRITE] [-help]\n";
  print " Note: all options can be abreviated to their first letter\n";
  print "  where LEVEL   is the number of loops to execute\n";
  print "Example:  ExtractMetaData.pl -a 3\n";
  exit 0;
}

my $ret;
my %keytree = ();
$ret = MetaDataGym::ParseFolderTable(\%keytree);
print "Found $ret keywords in FolderTable\n";
print Dumper(\%keytree) if $DEBUG;

my %meta_gps = ();
my %meta_location = ();
my %meta_keylocation = ();
#$ret = MetaDataGym::ResolveLocations(\%keytree, \%meta_gps, \%meta_location, \%meta_keylocation);
$ret = MetaDataGym::ReloadLocations(\%keytree, \%meta_gps, \%meta_location, \%meta_keylocation);
print " Resolved $ret locations from keytree\n";

my %meta_person = ();
$ret = MetaDataGym::ResolvePeople(\%keytree, \%meta_person);
print Dumper(\%meta_person) if $DEBUG;
print " Resolved $ret people from keytree\n";

my %meta_source = ();
$ret = MetaDataGym::ResolveSources(\%keytree, \%meta_source);
print Dumper(\%meta_source) if $DEBUG;
print " Resolved $ret sources from keytree\n";

my %meta_event = ();
$ret = MetaDataGym::ResolveEvents(\%keytree, \%meta_event);
print Dumper(\%meta_event) if $DEBUG;
print " Resolved $ret events from keytree\n";

my %captions = ();
$ret = MetaDataGym::ParseCaptionTable(\%captions);
print Dumper(\%captions) if $DEBUG;
print "Found $ret captions in CaptionTable\n";

$ret = MetaDataGym::ParseImageTable($accelerate, $NOWRITE, \%keytree, \%meta_gps, \%meta_location, \%meta_keylocation, \%meta_person, \%meta_source, \%meta_event, \%captions);
print "Found $ret images in ImageTable\n";

exit 0;
