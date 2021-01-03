#!/usr/bin/perl -w
########################################################################
#
# @(#) TagPhoto.pl   v1.0   2009/12/30   Tim Smith
#
#  Look up the GPS coordinates and Country-State-City hierarchy of a
#  location using the Google Maps API, then load the meta-data into
#  the EXIF and IPTC data of the photo file
#
########################################################################
use strict;
use diagnostics;
use utf8;  # To allow replacement strings to have accented characters
use Getopt::Long;
use Data::Dumper;
#binmode(STDOUT, ":utf8");
use lib "/Users/Tim/Code/PhotoOps";   # Add Tims code directory to @INC path
use MetaDataGym;

##################################
# Parse the command line options #
##################################
my %photoinfo = ();
my @photokeyarray = ();
my @photokeylocation = ();
my $photosource = -1;
my $photocaption = "";
my $photoevent = "";
my @photolocation = ();
my @photogps = ();
my $photodate = "";
my $photocreationdate = "";
my $isvideo = 0;
my $inputfilename = "";
my $outputfilename = "";

my $location = undef;
my $SubLocation = undef;
my @personarray = ();
my $GPSONLY = 0;
my $DEBUG = 0;
my $NOWRITE = 0;
my $APPEND = 0;
my $help = 0;
GetOptions("location=s" => \$location,
           "gpsonly" => \$GPSONLY,
           "file=s" => \$inputfilename,
           "people=s" => \@personarray,
           "caption=s" => \$photocaption,
           "event=s" => \$photoevent,
           "source=i" => \$photosource,
           "output=s" => \$outputfilename,
           "when=s" => \$photodate,
           "debug" => \$DEBUG,
           "nowrite" => \$NOWRITE,
           "append" => \$APPEND,
           "help!" => \$help);
if ($help) {
  print "\nUsage:  TagPhoto.pl -filename PHOTO [-location PLACE] [-people PEOPLE] [-caption CAPTION] [-event EVENT]\n";
  print "                      [-source SOURCE] [-when DATE] [-output NEWPHOTO] [-gpsonly]\n";
  print "                      [-debug] [-nowrite] [-append] [-help]\n";
  print " Note: all options can be abreviated to their first letter\n";
  print "  where PHOTO     is the filename of a photo file to update\n";
  print "  where PLACE     can include country, state, town, road\n";
  print "  where PEOPLE    should be of the form 'Smith.Tim, Smith.Alison'\n";
  print "  where CAPTION   is the caption to add\n";
  print "  where EVENT     is the event to add\n";
  print "  where SOURCE    is the source code [0=Slide,1=Negative,2=Print,3=Digital]\n";
  print "  where DATE      is the date in the form 1963:11:19 09:06:03\n";
  print "  where NEWPHOTO  is the filename of a new photo file if the original is to be left untouched\n";
  print "  where GPSONLY   indicates that only the GPS part of the location will be written\n";
  print "Example:  TagPhoto.pl -f pic.jpg -l \"19, Chemin du Pralet, Founex, Switzerland\"\n\n";
  exit 0;
}

if (!-w $inputfilename) {
  print "Cant find (or write to) $inputfilename\n";
  exit -1;
}

#####################
# Initialise hashes #
#####################
my $ret;
my $matched;
my $fullmatched;
my $locptr;
my %keytree = ();
#$ret = MetaDataGym::ReloadKeywords(\%keytree);
#print "Found $ret keywords from keytree store\n";
#print Dumper(\%keytree) if $DEBUG;

if (defined($location)) {
  my %meta_gps = ();
  my %meta_location = ();
  my %meta_keylocation = ();
  $matched = 0;
  $fullmatched = 0;
  if ($location =~ /.*\s+\[(.*)\]/) {
    $SubLocation = $1;
    $location =~s/(.*\s+)\[.*\]/$1/;
  }
  $ret = MetaDataGym::ReloadLocations(\%meta_gps, \%meta_location, \%meta_keylocation);
  print " Resolved $ret locations from keytree\n" if $DEBUG;
  print Dumper(\%meta_location) if $DEBUG;
  foreach my $id (sort keys %meta_location) {
    $locptr = scalar @{$meta_location{$id}} - 1;
    if ($location eq $meta_location{$id}[$locptr]) {
      print " ...Matched location @{$meta_location{$id}}\n";
      push(@photogps, @{$meta_gps{$id}});
      push(@photolocation, @{$meta_location{$id}}) unless $GPSONLY;
      push(@photokeylocation, $meta_keylocation{$id}) unless $GPSONLY;
      $matched++;
    }
    foreach my $loc (@{$meta_location{$id}}) {
      if ($loc eq $location) {
        $fullmatched++;
      }
    }
  }
  if ($fullmatched != 1) {
    print "WARNING: extra matches ($fullmatched) for location ($location)\n";
  }
  if ($matched != 1) {
    print "ERROR: didnt find a single match ($matched) for location ($location)\n";
    exit 0;
  }
}
if (scalar @personarray > 0) {
  my %meta_people = ();
  $ret = MetaDataGym::ReloadPeople(\%meta_people);
  print " Resolved $ret people from keytree\n" if $DEBUG;
  print Dumper(\%meta_people) if $DEBUG;
  foreach my $p (@personarray) {
    $matched = 0;
    foreach my $per (sort keys %meta_people) {
      if ($p eq $meta_people{$per}) {
        print " ...Matched person $p\n";
        push(@photokeyarray, $p);
        $matched++;
      }
    }
    if ($matched != 1) {
      print "ERROR: didnt find a single match ($matched) for person ($p)\n";
      exit 0;
    }
  }
}
if ($photodate ne "") {
  $photocreationdate = "7777";   # Indicate that the file modify date be used as the creation date
}

############################
# Prepare updated metadata #
############################
# Update metadata for the Country/State/City hierarchy
if (defined($photolocation[0])) {
}

# Update metadata for the GPS information
if (defined($photogps[0])) {
}

# Update metadata for the keywords PEOPLE
if ((scalar @photokeyarray > 0) || (scalar @photokeylocation > 0)) {
}

# Update metadata for the CAPTION
if ($photocaption ne "") {
}

# Update metadata for the keyword EVENT
if ($photoevent ne "") {
}

# Update metadata for the keyword SOURCE
if ($photosource != -1) {
}

# Update metadata for the Date/Time
if (($photodate ne "") && ($photodate ne $photocreationdate)) {
}

##################################################################
# Store all data in a photoinfo hash and pass to output function #
##################################################################
$photoinfo{"photokeyarray"} = [ @photokeyarray ];
$photoinfo{"photokeylocation"} = [ @photokeylocation ];
$photoinfo{"photosource"} = $photosource;
$photoinfo{"photocaption"} = $photocaption;
$photoinfo{"photoevent"} = $photoevent;
$photoinfo{"photolocation"} = [ @photolocation ];
$photoinfo{"photogps"} = [ @photogps ];
$photoinfo{"photodate"} = $photodate;
$photoinfo{"photocreationdate"} = $photocreationdate;
$photoinfo{"isvideo"} = $isvideo;
print Dumper(\%photoinfo) if $DEBUG;
$ret = UpdateExifData($inputfilename, $outputfilename, \%photoinfo, $NOWRITE, $APPEND);

exit 0;
