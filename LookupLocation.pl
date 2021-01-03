#!/usr/bin/perl -w
########################################################################
#
# @(#) LookupLocation.pl   v1.0   2009/12/31   Tim Smith
#
#  Look up the GPS coordinates and Country-State-City hierarchy of a
#  location using the Google Maps API
#
########################################################################
use strict;
use diagnostics;
use utf8;  # To allow replacement strings to have accented characters
use Getopt::Long;
use Data::Dumper;
binmode(STDOUT, ":utf8");
use lib "/Users/Tim/Code/PhotoOps";   # Add Tims code directory to @INC path
use MetaDataGym;
use vars qw($DEBUG);

##################################
# Parse the command line options #
##################################
my $location = "-";
my $SubLocation = undef;
my $DEBUG = 0;
my $help = 0;
GetOptions("location=s" => \$location,
           "debug" => \$DEBUG,
           "help!" => \$help);
if ($help || $location eq "-") {
  print "\nUsage:  LookupLocation.pl -location PLACE [-debug] [-help]\n";
  print " Note: all options can be abreviated to their first letter\n";
  print "  where PLACE     can include country, state, town, road\n";
  print "Example:  LookupLocation.pl -l \"19, Chemin du Pralet, Founex, Switzerland\"\n\n";
  exit 0;
}

#if ($location =~ /.*\s+\[(.*)\]/) {
#  $IPTCSubLocation = $1;
#  $location =~s/(.*\s+)\[.*\]/$1/;
#}

########################
# Initialise GoogleAPI #
########################
my $geocoder = undef;
$geocoder = MetaDataGym::InitialiseGoogleAPI;

#########################
# Lookup with GoogleAPI #
#########################
my %MDGoogle = ();
my $ret = LookupWithGoogleAPI($geocoder, $location, \%MDGoogle, $DEBUG);
print Dumper(\%MDGoogle) if $DEBUG;
print "\n$MDGoogle{printloc}\n";
if (defined($MDGoogle{IPTCSubLocation})) {
  print "iiii == $MDGoogle{IPTCCountry}; $MDGoogle{IPTCState}; $MDGoogle{IPTCCity}; $MDGoogle{IPTCSubLocation} == $MDGoogle{GPSLongitude}; $MDGoogle{GPSLatitude}\n";
} else {
  print "iiii == $MDGoogle{IPTCCountry}; $MDGoogle{IPTCState}; $MDGoogle{IPTCCity} == $MDGoogle{GPSLongitude}; $MDGoogle{GPSLatitude}\n";
}

exit 0;
