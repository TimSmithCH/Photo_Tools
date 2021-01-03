#+##############################################################################
#                                                                              #
# File: MetaDataGym.pm                                                         #
#                                                                              #
# Description: Functions to perform useful metadata gymnastics                 #
#                                                                              #
#-##############################################################################

package MetaDataGym;
require Exporter;

# Only make callable functions visible externally
@ISA    = qw(Exporter);
@EXPORT = qw(ParseFolderTable ParseCaptionTable ParseImageTable ResolveLocations ReloadLocations ResolvePeople ResolveSources ResolveEvents UpdateExifData InitialiseGoogleAPI LookupWithGoogleAPI);

use lib "/Users/Tim/Library/Perl/5.18";   # Add Tims Perl library to @INC path
use utf8;  # To allow replacement strings to have accented characters
use MIME::Base64;
use Geo::Coder::Google;
use Image::ExifTool qw(:Public);
use Time::HiRes qw{sleep};
use File::Path qw(make_path);
use File::Basename;
use File::Copy;
use Data::Dumper;


#+++############################################################################
#                                                                              #
# Parse the FolderTable file containing the keyword index                      #
#                                                                              #
#---############################################################################
sub ParseFolderTable ($) {
  my $ktref = shift;
  # Attribute is a 32-bit word, lower 16-bit appears to be a bit string
  #  but upper 16-bit appears to be a simple value
  my $bitmask_nodisplay = 0x0001;  # Dont display as keyword category
  my $bitmask_visible = 0x0002;  # Photos are visible in browser
  my $bitmask_branch = 0x0004;  # Not a leaf
  my $match_people = 0x1;  # PSE defined people category
  my $match_place = 0x2;  # PSE defined place category
  my $match_event = 0x3;  # PSE defined event category
  my $match_other = 0x4;  # PSE defined other category
  my $match_stars = 0x7;  # PSE defined favorites category
  my $match_collection = 0x8;  # PSE collections are hidden tags
  my $match_source = 0xa;  # My extra source media category
  my $match_hidden = 0x40;  # PSE defined hidden category
  ###
  my $folderid = 0;
  my $parentid = 0;
  my $keyword = "";
  my $keyword_attr = 0;
  my %keywords = ();
  my $FolderTable = "/Users/Tim/Archive/Photo_Information/PSE_Tables/FolderTable.xml";
  my $countkey = 0;
  open (FOLDERTAB, "<$FolderTable");
  while (<FOLDERTAB>) {
    if (/\<fFolderId\>(\d+)\<\/fFolderId\>/) { # Start of new FolderTable block
      $keyword = "";
      $parentid = -1;
      $keyword_attr = -1;
      $folderid = $1;
    } elsif (/\<fFolderName\>(.+)\<\/fFolderName\>/) {
      $keyword = $1;
      $keyword =~ s/&apos;/'/g;  # The XML export from PSE converted apostrophes
    } elsif (/\<fParentFolderId\>(\d+)\<\/fParentFolderId\>/) {
      $parentid = $1;
    } elsif (/\<fFolderAttributes\>(\d+)\<\/fFolderAttributes\>/) {
      $keyword_attr = $1;
    } elsif (/\<\/FolderTable\>/) { # End of FolderTable block
      if ($keyword_attr & $bitmask_visible) {
#      if (($keyword_attr & $bitmask_visible) && (($keyword_attr>>16) == $match_collection)) {
#        printf("Folder %d   Keyword %s   Parent %d   Attributes %x\n",$folderid, $keyword, $parentid, $keyword_attr);
        $keywords{$folderid} = [$keyword, $parentid, $keyword_attr];
      }
      $countkey++;
    }
  } 
  close(FOLDERTAB);
  #
  # Expand the keyword tree above each leaf
  foreach my $id (sort keys %keywords) {
    next if ($keywords{$id}[0] eq "");
    $ktref->{$id} = $keywords{$id}[0];
    my $pid = $keywords{$id}[1];
    while ($pid != 0) {
      $ktref->{$id} = sprintf("%s\.%s",$keywords{$pid}[0],$ktref->{$id});
      $pid = $keywords{$pid}[1];
    }
  }
  return scalar keys(%$ktref);
}

#+++############################################################################
#                                                                              #
# Identify locations within the key word tree and use Google Maps to find them #
#                                                                              #
#---############################################################################
sub ResolveLocations ($$$$) {
  my $ktref = shift;
  my $mgref = shift;
  my $mlref = shift;
  my $mkref = shift;
  my %MDGoogle = ();
  my $geocoder = InitialiseGoogleAPI;
  #foreach my $id (sort {$ktref->{$a} cmp $ktref->{$b}} keys %$ktref) { # Sort lexically by name for visualising
  foreach my $id (sort {$a <=> $b} keys %$ktref) { # Sort numerically by id for visualising
    if ($ktref->{$id} =~ /Places\..*/) {
      sleep(0.2); # Limit the rate of calling the Google API to avoid being locked out
      my $location = $ktref->{$id};
      $location =~ s/\./ /g;
      $location =~ s/Places//g;
      # Places which have a [tag] at the end are special sub-locations, where tag should not be passed to Google but should go in the metadata
      my $special = undef;
      if ($location =~ /.*\s+\[(.*)\]/) {
        $special = $1;
        $location =~s/(.*\s+)\[.*\]/$1/;
      }
      my $ret = LookupWithGoogleAPI($geocoder, $location, \%MDGoogle);
      if ($ret == 0) {
        # Load the location meta data
        $mgref->{$id} = [$MDGoogle{GPSLongitude}, $MDGoogle{GPSLatitude}];
        $mkref->{$id} = $MDGoogle{printloc};
        if (defined($MDGoogle{IPTCSubLocation})) {
          $mlref->{$id} = [$MDGoogle{IPTCCountry}, $MDGoogle{IPTCState}, $MDGoogle{IPTCCity}, $MDGoogle{IPTCSubLocation}];
        } elsif (defined($MDGoogle{IPTCCity})) {
          $mlref->{$id} = [$MDGoogle{IPTCCountry}, $MDGoogle{IPTCState}, $MDGoogle{IPTCCity}];
        } elsif (defined($MDGoogle{IPTCState})) {
          $mlref->{$id} = [$MDGoogle{IPTCCountry}, $MDGoogle{IPTCState}];
        } else {
          $mlref->{$id} = [$MDGoogle{IPTCCountry}];
        }
      } else {
        print "ERROR - Location not found: $id\t$location\n";
      }
    }
  }
  return scalar keys(%$mlref);
}

#+++############################################################################
#                                                                              #
# Initialise the Google Maps API (v3)                                          #
#                                                                              #
#---############################################################################
sub InitialiseGoogleAPI () {
  # Google Maps API v3 require either an API key (private users) or client ID (business users)
  my $api_key = "*****";
  my $geocoder = Geo::Coder::Google->new(language => 'en-GB', apiver => 3);
  return $geocoder;
}

#+++############################################################################
#                                                                              #
# Call the Google Maps API to resolve location hierarchy and GPS coordinates   #
#                                                                              #
#---############################################################################
sub LookupWithGoogleAPI ($$$$) {
  my $geocoder = shift;
  my $location = shift;
  my $mdgref = shift;
  my $DEBUG = shift;
  my $geolocation = $geocoder->geocode(location => $location);
  if (ref($geolocation) eq "HASH") {
    print "Returned hash\n" if $DEBUG;
    print Dumper(\%{$geolocation}) if $DEBUG;
    my $Country = undef;
    my $CountryCode = "??";
    my $State = "??";
    my $StateCode = "??";
    my $SubState = "??";
    my $SubSubState = "??";
    my $Town = "??";
    my $poi = undef;
    $mdgref->{GPSLongitude} = undef;
    $mdgref->{GPSLatitude} = undef;
    $mdgref->{IPTCCountry} = undef;
    $mdgref->{IPTCState} = undef;
    $mdgref->{IPTCCity} = undef;
    if (defined($special)) {
      $mdgref->{IPTCSubLocation} = $special;
    } else {
      $mdgref->{IPTCSubLocation} = undef;
    }
    # Places which are defined using a Country-State-City hierarchy e.g. "Oxford"
    print "\n |--------------|-----Long-Name------|-----Short-Name-----|\n";
#    if (grep {${$_}{types}[0] eq "country"} @{${$geolocation}{address_components}}) {
#      $ac = $_;
    for my $ac (@{${$geolocation}{address_components}}) {
      if (${$ac}{types}[0] eq "country") {
        printf(" | Country      | %18s | %18s |\n", ${$ac}{long_name}, ${$ac}{short_name});
        $Country = ${$ac}{long_name};
        # Havent used the home-language tag in the Google API as it translates all of the address to English,
        # and only want the country name, so do by hand instead
        if ($Country =~ /Österreich/) {
          $Country = "Austria";
        } elsif ($Country =~ /Ελλάς/) {
          $Country = "Greece";
        } elsif ($Country =~ /Schweiz/) {
          $Country = "Switzerland";
        } elsif ($Country =~ /Espanya/) {
          $Country = "Spain";
        } elsif ($Country =~ /Italia/) {
          $Country = "Italy";
        } elsif ($Country =~ /Italien/) {
          $Country = "Italy";
        } elsif ($Country =~ /México/) {
          $Country = "Mexico";
        } elsif ($Country =~ /United States/) {
          $Country = "USA";
        }
        $mdgref->{IPTCCountry} = $Country;
        $CountryCode = ${$ac}{short_name};   # 2-digit
#        $mdgref->{IPTCCountryCode} = $CountryCode;  # Unfortunately IPTC data expects 3-digit
      } elsif (${$ac}{types}[0] eq "administrative_area_level_1") {
        $State = ${$ac}{long_name};
        $StateCode = ${$ac}{short_name};
        $mdgref->{IPTCState} = $State;
        printf(" | State        | %18s | %18s |\n", ${$ac}{long_name}, ${$ac}{short_name});
      } elsif (${$ac}{types}[0] eq "administrative_area_level_2") {
        $SubState = ${$ac}{long_name};
        printf(" | SubState     | %18s | %18s |\n", ${$ac}{long_name}, ${$ac}{short_name});
      } elsif (${$ac}{types}[0] eq "administrative_area_level_3") {
        $SubSubState = ${$ac}{long_name};
        printf(" | SubSubState  | %18s | %18s |\n", ${$ac}{long_name}, ${$ac}{short_name});
      } elsif (${$ac}{types}[0] eq "locality") {
        $Town = ${$ac}{long_name};
        $mdgref->{IPTCCity} = $Town;
        printf(" | Town         | %18s | %18s |\n", ${$ac}{long_name}, ${$ac}{short_name});
      } elsif (${$ac}{types}[0] eq "point_of_interest") {
        $poi = ${$ac}{long_name};
        $mdgref->{IPTCSubLocation} = $poi;
        printf(" | POI          | %18s | %18s |\n", ${$ac}{long_name}, ${$ac}{short_name});
      } elsif (${$ac}{types}[0] eq "natural_feature") {
        $poi = ${$ac}{long_name};
        $mdgref->{IPTCSubLocation} = $poi;
        # In case natural fetaure has no associated locality
        $mdgref->{IPTCCity} = $Town if (!defined $mdgref->{IPTCCity});
        printf(" | Nat. Feature | %18s | %18s |\n", ${$ac}{long_name}, ${$ac}{short_name});
      }
    }
    print " |--------------|--------------------|--------------------|\n";
    # If Country is USA or Canada then use short state names
    if ($Country eq "USA" || $Country eq "Canada") {
      $State = $StateCode;
      $mdgref->{IPTCState} = $State;
    }
    if (defined(${$geolocation}{geometry}{location})) {
      $mdgref->{GPSLongitude} = ${$geolocation}{geometry}{location}{lng};
      $mdgref->{GPSLatitude} = ${$geolocation}{geometry}{location}{lat};
    }
    # Places of Interest (POI) which are defined simply by an address e.g. "The Lake District"
    # Need to extract the info from the address
    if (!defined($Town) && defined($poi)) {
      if (${$geolocation}{formatted_address} =~ /(.*?),.*?\s*(\S+),\s*(\S+)$/) {
        $location = "$3";
        if ($location eq "UK") {  # UK addresses have the postcode after the name
          ${$geolocation}{formatted_address} =~ /^(.*?),\s*(.+?)\s\w+\d+\s\d+,\s*(\S+)$/;
          $location .= " $2";
        } else {
          $location .= " $2";
        }
#        $geolocation = $geocoder->geocode(location => $location);
      }
      $mdgref->{IPTCCity} = $location;
      $Town = $location;
    }
    # Create the printable single string location hierarchy
    $mdgref->{printloc} = $CountryCode.".".$State.".".$Town;
    $mdgref->{printloc} =~ s/ /_/g;
    printf(" | Lat/Long     | %18f | %18f |\n", $mdgref->{GPSLatitude}, $mdgref->{GPSLongitude});
    print " |--------------|--------------------|--------------------|\n";
  } else {
    return -1;
  }
  return 0;
}

#+++############################################################################
#                                                                              #
# Identify the locations within the key word tree and reload GPS information   #
#  from the file from the previous run                                         #
#                                                                              #
#---############################################################################
sub ReloadLocations ($$$) {
  my $mgref = shift;
  my $mlref = shift;
  my $mkref = shift;
  my $LocationFile = "/Users/Tim/Archive/Photo_Information/GPS_Locations";
  my $loc_id;
  my $loc_name_string;
  my $loc_gps_string;
  my @locarr = ();
  my %CountryCode = ();
  $CountryCode{"Switzerland"}     = "CH";
  $CountryCode{"France"}          = "FR";
  $CountryCode{"Mexico"}          = "MX";
  $CountryCode{"Great Britain"}   = "GB";
  $CountryCode{"United Kingdom"}  = "GB";
  $CountryCode{"Holland"}         = "NL";
  $CountryCode{"Italy"}           = "IT";
  $CountryCode{"Austria"}         = "AT";
  $CountryCode{"Germany"}         = "DE";
  $CountryCode{"Nepal"}           = "NP";
  $CountryCode{"Tanzania"}        = "TZ";
  $CountryCode{"Kenya"}           = "KE";
  $CountryCode{"Spain"}           = "ES";
  $CountryCode{"Canada"}          = "CA";
  $CountryCode{"Greece"}          = "GR";
  $CountryCode{"Australia"}       = "AU";
  $CountryCode{"New Zealand"}     = "NZ";
  $CountryCode{"Chile"}           = "CL";
  $CountryCode{"Argentina"}       = "AR";
  $CountryCode{"Pakistan"}        = "PK";
  $CountryCode{"Denmark"}         = "DK";
  $CountryCode{"Sweden"}          = "SE";
  $CountryCode{"Norway"}          = "NO";
  $CountryCode{"USA"}             = "US";
  $CountryCode{"Belgium"}         = "BE";
  $CountryCode{"Lithuania"}       = "LT";
  $CountryCode{"Andorra"}         = "AD";
  $CountryCode{"Monaco"}          = "MC";
  open (LOCATIONS, "<$LocationFile");
  while (<LOCATIONS>) {
    chomp;
    next if (/^#/);
    ($loc_id, $loc_name_string, $loc_gps_string) = split(/ == /);
    (@locarr) = split(/\s*;\s* /, $loc_name_string);
    my $numel = scalar @locarr;
    ($GPSLongitude, $GPSLatitude) = split(/\s*;\s* /, $loc_gps_string);
    # Load the location meta data
    $mgref->{$loc_id} = [ $GPSLongitude, $GPSLatitude ];
    $mlref->{$loc_id} = [ @locarr ];
    if (!defined($CountryCode{$locarr[0]})) {
      print "ERROR - no country code for $locarr[0]\n";
      return -1;
    } else {
      my $printloc = $CountryCode{$locarr[0]}."\.".$locarr[1];
      if ($numel >= 3) {
        $printloc = $printloc."\.".$locarr[2];
      }
      $printloc =~ s/ /_/g;
      $mkref->{$loc_id} = $printloc;
    }
  }
  close(LOCATIONS);
  return scalar keys(%$mlref);
}

#+++############################################################################
#                                                                              #
# Identify the people within the key word tree                                 #
#                                                                              #
#---############################################################################
sub ResolvePeople ($$) {
  my $ktref = shift;
  my $mpref = shift;
  my %person_exception = ();
  $person_exception{"Alison"}                      = "Smith.Alison";
  $person_exception{"Eddy"}                        = "NOT ALLOWED";
  $person_exception{"Eddy Andrew"}                 = "NOT ALLOWED";
  $person_exception{"Eddy Andrew.Andrew"}          = "Eddy.Andrew";
  $person_exception{"Eddy Andrew.Frankie"}         = "Eddy.Frankie";
  $person_exception{"Eddy Andrew.Madeline"}        = "Eddy.Madeline";
  $person_exception{"Eddy Andrew.Sarah"}           = "Eddy.Sarah";
  $person_exception{"Eddy Jon"}                    = "NOT ALLOWED";
  $person_exception{"Eddy Jon.Caitlin"}            = "Eddy.Caitlin";
  $person_exception{"Eddy Jon.Christopher Eddy"}   = "Eddy.Jon.Christopher";
  $person_exception{"Eddy Jon.Freya"}              = "Eddy.Freya";
  $person_exception{"Eddy Jon.Jonathon"}           = "Eddy.Jonathon";
  $person_exception{"Eddy Jon.Lauren"}             = "Eddy.Lauren";
  $person_exception{"Eddy Jon.Lisa"}               = "Eddy.Lisa";
  $person_exception{"Eddy Robin"}                  = "NOT ALLOWED";
  $person_exception{"Eddy Robin.Ebolyn"}           = "Eddy.Ebolyn";
  $person_exception{"Eddy Robin.Kiera"}            = "Eddy.Kiera";
  $person_exception{"Eddy Robin.Robin"}            = "Eddy.Robin";
  $person_exception{"Eddy.Christopher"}            = "Eddy.Thackray.Christopher";
  $person_exception{"Eddy.David Eddy"}             = "Eddy.David";
  $person_exception{"Eddy.Freda"}                  = "Liversidge.Freda";
  $person_exception{"Eddy.Grandma Margaret"}       = "Eddy.Margaret";
  $person_exception{"Eddy.Grandpa Chris"}          = "Eddy.Christopher";
  $person_exception{"Eddy.Rachael Eddy"}           = "Eddy.Rachael";
  $person_exception{"Grandad Apple"}               = "Smith.Brian";
  $person_exception{"Grandma Apple"}               = "Smith.Gillian";
  $person_exception{"Luke"}                        = "Smith.Luke";
  $person_exception{"Marsh"}                       = "NOT ALLOWED";
  $person_exception{"Mullineux"}                   = "NOT ALLOWED";
  $person_exception{"Pickard"}                     = "NOT ALLOWED";
  $person_exception{"Pickard.Alison Pickard"}      = "Pickard.Alison";
  $person_exception{"Ridley"}                      = "NOT ALLOWED";
  $person_exception{"Samuel"}                      = "Smith.Samuel";
  $person_exception{"Smith"}                       = "NOT ALLOWED";
  $person_exception{"Smith.Doreen"}                = "Tompkins.Doreen";
  $person_exception{"Smith.Grandad George"}        = "Smith.George";
  $person_exception{"Smith.Grandma Nora"}          = "Smith.Nora";
  $person_exception{"Smith.Great Grandma Smith"}   = "Smith.Mary";
  $person_exception{"Smith.Norman"}                = "Tompkins.Norman";
  $person_exception{"Tim"}                         = "Smith.Tim";
  $person_exception{"Walker"}                      = "NOT ALLOWED";
  $person_exception{"Walker.Gandad Charlie"}       = "Walker.Charles";
  $person_exception{"Walker.John Walker"}          = "Walker.John";
  $person_exception{"Webster"}                     = "NOT ALLOWED";
  $person_exception{"Webster.Samuel Webster"}      = "Webster.Samuel";
  $person_exception{"Alan"}                        = "Goldsmith.Alan";
  $person_exception{"Alix"}                        = "Carollo.Alix";
  $person_exception{"Annalisa"}                    = "Stagliano.Annalisa";
  $person_exception{"Anya"}                        = "French.Anya";
  $person_exception{"Beaud"}                       = "NOT ALLOWED";
  $person_exception{"Beaud.Alexandre Beaud"}       = "Beaud.Alexandre";
  $person_exception{"Beaud.Karina Beaud"}          = "Beaud.Karina";
  $person_exception{"Beaud.Tanya Beaud"}           = "Beaud.Tanya";
  $person_exception{"Blythe"}                      = "NOT ALLOWED";
  $person_exception{"Blythe.Alan Blythe"}          = "Blythe.Alan";
  $person_exception{"Borner"}                      = "NOT ALLOWED";
  $person_exception{"Caravelas"}                   = "NOT ALLOWED";
  $person_exception{"Drayton"}                     = "NOT ALLOWED";
  $person_exception{"Drayton.Alex Drayton"}        = "Drayton.Alex";
  $person_exception{"Drayton.Carol Drayton"}       = "Drayton.Carol";
  $person_exception{"Drayton.Neil Drayton"}        = "Drayton.Neil";
  $person_exception{"Drayton.Steve Drayton"}       = "Drayton.Steve";
  $person_exception{"Ernie"}                       = "Odoom.Ernie";
  $person_exception{"Ferguson"}                    = "NOT ALLOWED";
  $person_exception{"Ferguson.Kate Ferguson"}      = "Ferguson.Kate";
  $person_exception{"Fiette"}                      = "NOT ALLOWED";
  $person_exception{"Fiona"}                       = "Macartney.Fiona";
  $person_exception{"Forshaw"}                     = "NOT ALLOWED";
  $person_exception{"Gamble"}                      = "NOT ALLOWED";
  $person_exception{"Graeme"}                      = "Cameron.Graeme";
  $person_exception{"Greenaway"}                   = "NOT ALLOWED";
  $person_exception{"Greenaway.Beanie Greeaway"}   = "Hughes.Phoebe";
  $person_exception{"Greenaway.Buzz Greenaway"}    = "Hughes.Alex";
  $person_exception{"Greenaway.Emma Greenaway"}    = "Hughes-Greenaway.Emma";
  $person_exception{"Greenaway.Mike Greenaway"}    = "Hughes.Mike";
  $person_exception{"Guides"}                      = "NOT ALLOWED";
  $person_exception{"Guides.Guide Alex"}           = "Guides.Alex";
  $person_exception{"Halle"}                       = "NOT ALLOWED";
  $person_exception{"Hamill"}                      = "NOT ALLOWED";
  $person_exception{"Hamill.Cath Hamill"}          = "Hamill.Cath";
  $person_exception{"Hamill.Ellen Hamill"}         = "Hamill.Ellen";
  $person_exception{"Harris"}                      = "NOT ALLOWED";
  $person_exception{"Harwood"}                     = "NOT ALLOWED";
  $person_exception{"Harwood.Evelyn Harwood"}      = "Harwood.Evelyn";
  $person_exception{"Harwood.Peter Harwood"}       = "Harwood.Peter";
  $person_exception{"Jes"}                         = "Autie.Jes";
  $person_exception{"Jez"}                         = "Thorpe.Jez";
  $person_exception{"Landecy"}                     = "NOT ALLOWED";
  $person_exception{"Marriott"}                    = "NOT ALLOWED";
  $person_exception{"Marriott.Jane Marriott"}      = "Marriott.Jane";
  $person_exception{"McClure"}                     = "NOT ALLOWED";
  $person_exception{"McClure.Alice McClure"}       = "McClure.Alice";
  $person_exception{"McClure.Biddy McClure"}       = "McClure.Biddy";
  $person_exception{"McClure.Kate McClure"}        = "McClure.Kate";
  $person_exception{"McCluskie"}                   = "NOT ALLOWED";
  $person_exception{"McCormack"}                   = "NOT ALLOWED";
  $person_exception{"McCormack.David McCormack"}   = "McCormack.David";
  $person_exception{"McCormack.Leslie McCormack"}  = "McCormack.Leslie";
  $person_exception{"McCormack.Stuart McCormack"}  = "McCormack.Stuart";
  $person_exception{"Miller"}                      = "NOT ALLOWED";
  $person_exception{"Perry"}                       = "NOT ALLOWED";
  $person_exception{"Perry.Christine Perry"}       = "Perry.Christine";
  $person_exception{"Pfister"}                     = "NOT ALLOWED";
  $person_exception{"Phil"}                        = "Miles.Phil";
  $person_exception{"Piazza"}                      = "NOT ALLOWED";
  $person_exception{"Plummer-Walker"}              = "NOT ALLOWED";
  $person_exception{"Plummer-Walker.Jay"}          = "Plummer.Jay";
  $person_exception{"Plummer-Walker.Osy"}          = "Plummer.Osy";
  $person_exception{"Plummer-Walker.Zara"}         = "Plummer.Zara";
  $person_exception{"Rietbergen"}                  = "NOT ALLOWED";
  $person_exception{"Rietbergen.Emma Rietbergen"}  = "Rietbergen.Emma";
  $person_exception{"Rietbergen.Jenny Rietbergen"} = "Rietbergen.Jenny";
  $person_exception{"Rietbergen.Lilly Rietbergen"} = "Rietbergen.Lilly";
  $person_exception{"Rietbergen.Sam Rietbergen"}   = "Rietbergen.Sam";
  $person_exception{"Rietbergen.Simon Rietbergen"} = "Rietbergen.Simon";
  $person_exception{"Sabha"}                       = "Aazami.Sabha";
  $person_exception{"Sarah Autie"}                 = "Autie.Sarah";
  $person_exception{"School GES"}                  = "NOT ALLOWED";
  $person_exception{"School GES.Mr Dalton"}        = "Teacher.GES.Dalton";
  $person_exception{"School GES.Mr O&apos;Byrne"}  = "Teacher.GES.O\'Byrne";
  $person_exception{"School GES.Mr O'Byrne"}       = "Teacher.GES.O\'Byrne";
  $person_exception{"School GES.Mr Unsworth"}      = "Teacher.GES.Unsworth";
  $person_exception{"School GES.Mrs Piguet"}       = "Teacher.GES.Piguet";
  $person_exception{"Seaton"}                      = "NOT ALLOWED";
  $person_exception{"Seaton.Andrea Seaton"}        = "Seaton.Andrea";
  $person_exception{"Seaton.Florence Seaton"}      = "Seaton.Florence";
  $person_exception{"Seaton.Jane Seaton"}          = "Seaton.Jane";
  $person_exception{"Seaton.Mark Seaton"}          = "Seaton.Mark";
  $person_exception{"Sherpa"}                      = "NOT ALLOWED";
  $person_exception{"Stourton"}                    = "NOT ALLOWED";
  $person_exception{"Wavre"}                       = "NOT ALLOWED";
  $person_exception{"Wavre.Anthony Wavre"}         = "Wavre.Anthony";
  foreach my $id (sort {$a <=> $b} keys %$ktref) { # Sort numerically by id for visualising
    if ($ktref->{$id} =~ /People\..*/) {
      my $person = $ktref->{$id};
      $person =~ s/People\.Family\.//g;
      $person =~ s/People\.Friends\.//g;
      if (defined($person_exception{$person})) {
        $mpref->{$id} = $person_exception{$person};
      } else {
        $mpref->{$id} = $person;
      }
    }
  }
  return scalar keys(%$mpref);
}

#+++############################################################################
#                                                                              #
# Reload the people within the key word tree from file from the previous run   #
#                                                                              #
#---############################################################################
sub ReloadPeople ($) {
  my $mpref = shift;
  my $per_id;
  my $per_name;
  my $PeopleFile = "/Users/Tim/Archive/Photo_Information/AuthorisedNames";
  open (PEOPLE, "<$PeopleFile");
  while (<PEOPLE>) {
    chomp;
    ($per_id, $per_name) = split(/ == /);
    $mpref->{$per_id} = $per_name;
  }
  close(PEOPLE);
  return scalar keys(%$mpref);
}

#+++############################################################################
#                                                                              #
# Identify the source media within the key word tree                           #
#                                                                              #
#---############################################################################
sub ResolveSources ($$) {
  my $ktref = shift;
  my $msref = shift;
  foreach my $id (sort {$a <=> $b} keys %$ktref) { # Sort numerically by id for visualising
    if ($ktref->{$id} =~ /Source\sMedia\..*/) {
      if ($ktref->{$id} =~ /Source\sMedia\.Digital\s\(Native\)/) {
        $msref->{$id} = 3;  # Digital Camera
      } elsif ($ktref->{$id} =~ /Source\sMedia\.Hard\scopy/) {
        $msref->{$id} = 2;  # Scanned from Print
      } elsif ($ktref->{$id} =~ /Source\sMedia\.Negative/) {
        $msref->{$id} = 1;  # Scanned from Film
      } elsif ($ktref->{$id} =~ /Source\sMedia\.Slide/) {
        $msref->{$id} = 0;  # Scanned from Film (The convention uses 1 for both slides and negatives, but 0 is allowed, though classed as unknown)
      }
    }
  }
  return scalar keys(%$msref);
}

#+++############################################################################
#                                                                              #
# Identify the events within the key word tree                                 #
#                                                                              #
#---############################################################################
sub ResolveEvents ($$) {
  my $ktref = shift;
  my $meref = shift;
  foreach my $id (sort {$a <=> $b} keys %$ktref) { # Sort numerically by id for visualising
    if ($ktref->{$id} =~ /Events\..*/) {
        my $event = $ktref->{$id};
        $event =~ s/Events\.//g;
        $event =~ s/GES events\.GES/GES:/g;
        $event =~ s/Escalade Run/Running: Escalade/g;
        $event =~ s/Marathon: Geneve/Running: Genève Marathon/g;
        $event =~ s/Triathlon:Nyon/Triathlon: Nyon/g;
        $meref->{$id} = $event;
    }
  }
  return scalar keys(%$meref);
}

#+++############################################################################
#                                                                              #
# Parse the CaptionTable file containing the caption index                     #
#                                                                              #
#---############################################################################
sub ParseCaptionTable ($) {
  my $capref = shift;
  my $captionid = 0;
  my $caption = "";
  my $CaptionTable = "/Users/Tim/Archive/Photo_Information/PSE_Tables/MediaShortCaptionTable.xml";
  open (CAPTIONTAB, "<$CaptionTable");
  while (<CAPTIONTAB>) {
    if (/\<fMediaShortCaptionId\>(\d+)\<\/fMediaShortCaptionId\>/) { # Start of new CaptionTable block
      $caption = "";
      $captionid = $1;
    } elsif (/\<fMediaShortCaption\>(.+)\<\/fMediaShortCaption\>/) {
      $caption = $1;
      $caption =~ s/&apos;/'/g;  # The XML export from PSE converted apostrophes
    } elsif (/\<\/MediaShortCaptionTable\>/) { # End of CaptionTable block
      if ($caption !~ /SONY DSC\s*/) {
        $capref->{$captionid} = $caption;
        printf("CaptionID %d   Caption %s\n",$captionid, $caption) if $DEBUG;
      }
    }
  } 
  close(CAPTIONTAB);
  return scalar keys(%$capref);
}

#+++############################################################################
#                                                                              #
# Parse the ImageTable file containing the list of photos                      #
#                                                                              #
#---############################################################################
sub ParseImageTable ($$$$$$$$$$) {
  my $accelerate = shift;
  my $NOWRITE = shift;
  my $ktref = shift;
  my $mgref = shift;
  my $mlref = shift;
  my $mkref = shift;
  my $mpref = shift;
  my $msref = shift;
  my $meref = shift;
  my $mcref = shift;
  my $APPEND = 0;
  my %photoinfo = ();
  my $photoid = -1;
  my $photoname = "";
  my $photocaptionid = -1;
  my $photocaption = "";
  my @photokeyarray = ();
  my @photokeylocation = ();
  my $photokey = "";
  my @photogps = ();
  my @photolocation = ();
  my $photosource = -1;
  my $photoevent = "";
  my $photodate = "";
  my $photocreationdate = "";
  my $countimage = 0;
  my $isvideo = 0;
  my $success;
  my $ImageTable = "/Users/Tim/Archive/Photo_Information/PSE_Tables/ImageTable.xml";
  open (IMAGETAB, "<$ImageTable");
  while (<IMAGETAB>) {
    if (/\<fImageId\>(\d+)\<\/fImageId\>/) { # Start of new ImageTable block
      $photoid = $1;
      $photokey = "";
      $photoname = "";
      $photocaptionid = -1;
      $photocaption = "";
      @photokeyarray = ();
      @photokeylocation = ();
      @photogps = ();
      @photolocation = ();
      $photosource = -1;
      $photoevent = "";
      $photodate = "";
      $photocreationdate = "";
      $isvideo = 0;
    # Identify the full path to the photo, and remove the Windows specific start
    } elsif (/\<fMediaFullPath\>(.+)\<\/fMediaFullPath\>/) {
      $photoname = $1;
      $photoname =~ s/C:\\Documents and Settings\\Tim\\Mes documents\\Mes images\\/\/Users\/Tim\/Temp\/Pictures from PC\//;
      $photoname =~ s/\\/\//g;
      $photoname =~ s/&apos;/'/g;  # The XML export from PSE converted apostrophes
      $photoname =~ s/&amp;/&/g;  # The XML export from PSE converted ampersands
    # Identify the date/time of the action in the image which can be set retrospectively for a scanned image
    } elsif (/\<fImageTime\>(.+)\<\/fImageTime\>/) {
      $photodate = $1;
      $photodate =~ s/-/:/g;
      $photodate =~ s/T/ /g;
    # Identify the date/time the image file was created
    } elsif (/\<fMDCreationDate\>(.+)\<\/fMDCreationDate\>/) {
      $photocreationdate = $1;
      $photocreationdate =~ s/-/:/g;
      $photocreationdate =~ s/T/ /g;
    # Identify which caption is referenced, and look it up in the preloaded caption hash
    } elsif (/\<fMediaShortCaptionIdFromMedia\>(\d+)\<\/fMediaShortCaptionIdFromMedia\>/) {
      $photocaptionid = $1;
      if (defined $mcref->{$photocaptionid}) {
        $photocaption = $mcref->{$photocaptionid};
      }
    # Identify which keywords (an array) are referenced, and look them up in the preloaded keyword hash
    } elsif (/\<fFolderInfoArray\>(.+)/) {  # 64 bit encoded byte strings spanning 8 lines
      chomp;
      $photokey = $1;
      while (my $line = <IMAGETAB>) {  # The array spans multiple (8 usually) lines
        last if ($line =~ /\<\/fFolderInfoArray\>/);
        chomp $line;
        $photokey .= $line;
      }
      my $location_check = 0;
      my $photokeydata = decode_base64($photokey);
      for (my $i = 0; $i < 50; $i++) {
        my $photokeyid = (unpack("N", pack("V", vec($photokeydata, $i, 32))));
        if (defined $ktref->{$photokeyid}) {
          # See what type of keyword it is (People/Place/Source/Event) and handle appropriately
          if (defined($mpref->{$photokeyid})) {
            push(@photokeyarray, $mpref->{$photokeyid});
          } elsif (defined($mgref->{$photokeyid})) {
            if ($location_check == 0) {
              push(@photogps, @{ $mgref->{$photokeyid} });
              push(@photolocation, @{ $mlref->{$photokeyid} });
              push(@photokeylocation, $mkref->{$photokeyid});  # For the sake of iPhoto load the place as a keyword anyway, even if coded accurately elsewhere
              $location_check++;
            } else {
              if ($mkref->{$photokeyid} ne "CH") {  # Drop the first location and keep this one (apart from one special case)
                @photogps = ();
                @photolocation = ();
                @photokeylocation = ();
                push(@photogps, @{ $mgref->{$photokeyid} });
                push(@photolocation, @{ $mlref->{$photokeyid} });
                push(@photokeylocation, $mkref->{$photokeyid});  # For the sake of iPhoto load the place as a keyword anyway, even if coded accurately elsewhere
                $location_check++;
                print "WARNING - multiple location (first) ignored\n";
              } else {  # Drop this new location
                print "WARNING - multiple location (second) ignored\n";
              }
            }
          } elsif (defined($msref->{$photokeyid})) {
            $photosource = $msref->{$photokeyid};
          } elsif (defined($meref->{$photokeyid})) {
            $photoevent = $meref->{$photokeyid};
          }
#        } else {  # There are lots of invisible keys used internally by PhotoShop which we can ignore here
#          printf("Undefined photokey %d\n", $photokeyid) unless ($photokeyid == 0);
        }
      }
    # End of block describing one photo, so should have all the necessary info to update the photo master
    } elsif (/\<\/ImageTable\>/) { # End of ImageTable block
      my $inputfilename;
      my $outputfilename;
      if (-w $photoname) {
        print "Found $photoname\n";
        if ($photodate eq "") {
          print "ERROR - no date found for $photoname\n";
          next;
        } else {
          if ($photodate =~ /(\d{4}):(\d{2}):(\d{2})\s\d{2}:\d{2}:\d{2}/) {
            my $pyear = $1;
            my $pmonth = $2;
            my $pday = $3;
            my $ppath;
            my $ppatha;
            my $pfilename = File::Basename::basename($photoname);
            my $parentdir = File::Basename::basename(File::Basename::dirname($photoname));
            if ($photosource == 1) {
              if ($parentdir =~ /Jura_More/) {
                $ppath = sprintf("/Users/Tim/Archive/Photo_Masters/%s/%s/%s", $pyear, $pmonth, $pday);
                $inputfilename = $photoname;
                $outputfilename = sprintf("%s/%s", $ppath, $pfilename);
              } elsif ((my $dirletn) = $parentdir =~ /Negatives_(\w)\w/) {
                $inputfilename = sprintf("/Users/Tim/Temp/Pictures from PC/Negatives/%s/%s/%s", $dirletn, $parentdir, $pfilename);
                $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Negatives/%s/%s/%s", $dirletn, $parentdir, $pfilename);
              } else {
                print "ERROR - cant parse negative directory $parentdir\n";
                next;
              }
              if (-w $inputfilename) {
                print " Found real negative master $inputfilename\n";
              } else {
                print "ERROR - cant find real master $inputfilename\n";
                next;
              }
            } elsif ($photosource == 2) {
              if ($parentdir =~ /MaD_printed/) {
                $inputfilename = sprintf("/Users/Tim/Temp/Pictures from PC/Hard_Copies/%s/%s", $parentdir, $pfilename);
                $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Hard_Copies/%s/%s", $parentdir, $pfilename);
              } else {
                $inputfilename = $photoname;
                $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Hard_Copies/%s/%s", $pyear, $pfilename);
              }
              if (-w $inputfilename) {
                print " Found real scanned master $inputfilename\n";
              } else {
                $inputfilename = $photoname;
                print "WARNING - revert to fake master $inputfilename\n";
              }
            } elsif ($photosource == 0) {
              if ((my $dirlets) = $parentdir =~ /(\w)\w{2}/) {
                if ($parentdir =~ /GG_Apple/) {  # Backtrack - if it wasnt a simple 1A3 style name, have to handle exceptions individually
                  $inputfilename = sprintf("/Users/Tim/Temp/Pictures from PC/Slides/GG_Apple/%s/%s", $parentdir, $pfilename);
                  $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Slides/GG_Apple/%s/%s", $parentdir, $pfilename);
                } elsif ($parentdir =~ /Random/) {
                  $inputfilename = sprintf("/Users/Tim/Temp/Pictures from PC/Slides/Random/%s", $pfilename);
                  $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Slides/Random/%s", $pfilename);
                } elsif ($parentdir =~ /_1\d{3}/) {
                  $inputfilename = sprintf("/Users/Tim/Temp/Pictures from PC/Slides/GG_Walker/%s/%s", $parentdir, $pfilename);
                  $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Slides/GG_Walker/%s/%s", $parentdir, $pfilename);
                } elsif ($pfilename =~ /^s_/) {
                  $inputfilename = $photoname;
                  $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Slides/ReScan/%s", $pfilename);
                } else {
                  $inputfilename = sprintf("/Users/Tim/Temp/Pictures from PC/Slides/%s/Slides_%s/%s", $dirlets, $parentdir, $pfilename);
                  $inputfilename =~ s/\.jpg/\.tif/g;
                  $outputfilename = sprintf("/Users/Tim/Archive/Photo_Masters/Slides/%s/Slides_%s/%s", $dirlets, $parentdir, $pfilename);
                }
                if (-w $inputfilename) {
                  print " Found real slide master $inputfilename\n";
                } else {
                  $inputfilename = $photoname;
                  print "WARNING - revert to fake master $inputfilename\n";
                }
              } else {
                print "ERROR - cant parse slide directory $parentdir\n";
                next;
              }
            } else {
              if ((lc($photoname) =~ /.*\.avi$/) || (lc($photoname) =~ /.*\.wmv$/) || (lc($photoname) =~ /.*\.mov$/) || (lc($photoname) =~ /.*\.mpg$/)) {  # Different hierarchy for movie files
                $ppath = sprintf("/Users/Tim/Archive/Video_Masters/%s/%s/%s", $pyear, $pmonth, $pday);
                $isvideo = 1;
              } else {
                $ppath = sprintf("/Users/Tim/Archive/Photo_Masters/%s/%s/%s", $pyear, $pmonth, $pday);
                $isvideo = 0;
              }
              $inputfilename = $photoname;
              $outputfilename = sprintf("%s/%s", $ppath, $pfilename);
              if ((my $dirextn) = $parentdir =~ /.*-(\d)$/) {  # Mutiple cameras on the same day had different directory names but same photo names
                my $newindex = 0;
                (my $firstbit, my $indexnum, my $secondbit) = $pfilename =~ /(\d{4} \d{2} \d{2} )(\d{3})(.*)/;
                if (defined($indexnum)) {
                  if ($firstbit =~ /2009 06 18 /) {   # On this day Dad took over 100 photos
                    $newindex = int($indexnum) + (int($dirextn) * 200);
                  } else {
                    $newindex = int($indexnum) + (int($dirextn) * 100);
                  }
                  $outputfilename = sprintf("%s/%s%s%s", $ppath, $firstbit, $newindex, $secondbit);
                  print " MULTI-camera fix to output: $outputfilename\n";
                } else {
                  print "WARNING - MULTI-camera fix failed to parse for new filename: $outputfilename\n";
                }
              }
            }
            $ppatha = File::Basename::dirname($outputfilename);
            if ($NOWRITE) {
              $success = 99;
            } else {
              $success = File::Path::make_path($ppatha);
            }
            print " Made ($success elements of) directory $ppatha\n";
          } else {
            print "ERROR - couldnt parse $photodate\n";
            next;
          }
        }
        print " OUTPUT: $outputfilename\n";
        if (-w $outputfilename) {
          print "ERROR - output file already exists $outputfilename\n";
          next;
        }
        # Store all data in a photoinfo hash to be passed to output function
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
#        print Dumper(\%photoinfo);
        my $ret = UpdateExifData($inputfilename, $outputfilename, \%photoinfo, $NOWRITE, $APPEND);
      } else {
        print "ERROR - cant find $photoname\n";
      }
      $countimage++;
      last if ($accelerate != -1 && $countimage >= $accelerate);
    } 
  } 
  close(IMAGETAB);
  return $countimage;
}

#+++############################################################################
#                                                                              #
# Update the EXIF information in the photo file                                #
#                                                                              #
#---############################################################################
sub UpdateExifData ($$$$$) {
  my $inputfilename = shift;
  my $outputfilename = shift;
  my $piref = shift;
  my $NOWRITE = shift;
  my $APPEND = shift;
  my %options = ();
  my %xgps = ();
  my $success;
  #
  #####################################
  # Initialise the ExifTool functions #
  #####################################
  # Create a new Image::ExifTool object
  my $exifTool = new Image::ExifTool;
  # Modify default error handling
  $exifTool->Options(IgnoreMinorErrors => 1);
  # Indicate that the strings are written out in UTF8 character encoding
  $success = $exifTool->SetNewValue('IPTC:CodedCharacterSet' => 'UTF8', Protected => 0x01);
  print "ERROR - setting CharacterSet $success\n" if ($success < 1);
  #
  #####################################
  # Load current meta data from photo #
  #####################################
  # Extract meta information from an image
  $success = $exifTool->ExtractInfo($inputfilename, \%options);
  print "ERROR - extracting EXIF info from $inputfilename\n" if ($success != 1);
  #
  ################################
  # Prepare additional meta data #
  ################################
  # Prepare metadata for write: the keywords PEOPLE (and location for iPhoto)
  if ((scalar @{ $piref->{"photokeyarray"} } > 0) || (scalar @{ $piref->{"photokeylocation"} } > 0)) {
    push(@{ $piref->{"photokeyarray"} }, @{ $piref->{"photokeylocation"} }) if (scalar @{ $piref->{"photokeylocation"} } > 0);
    if ($APPEND) {
      my @xkeywords = $exifTool->GetValue('Keywords');
      if (scalar(@xkeywords) > 0) {
        print " ...APPEND: Pre-Existing Keywords: @xkeywords\n";
      } else {
        print " ...APPEND: Pre-Existing Keywords: NONE\n";
      }
      push(@{ $piref->{"photokeyarray"} }, @xkeywords);
    }
    print "> Keywords: @{ $piref->{photokeyarray} }\n";
    # Output the people as EXIF(Keywords)
    $success = $exifTool->SetNewValue(Keywords => \@{ $piref->{"photokeyarray"} });
    print "   Set keywords $success\n" if ($success < 1);
  }
  # Prepare metadata for write: the keyword SOURCE
  if ($piref->{photosource} != -1) {
    print "   Source: $piref->{photosource}\n";
    # Output the source as EXIF(FileSource) and EXIFTOOL adds XMP(exif:FileSource)
    $success = $exifTool->SetNewValue('ExifIFD:FileSource' => $piref->{photosource}, Type => 'ValueConv');
    print "ERROR - setting FileSource $success\n" if ($success < 1);
    # Output the source also to the IPTC space (although this is a misuse of the field) as Aperture doesnt seem to display the EXIF FileSource
    $success = $exifTool->SetNewValue('IPTC:Source' => $piref->{photosource});
    print "ERROR - setting FileSource $success\n" if ($success < 1);
  }
  # Prepare metadata for write: the CAPTION
  if ($piref->{photocaption} ne "") {
    print "> Caption: $piref->{photocaption}\n";
    # Output the caption as EXIF(ImageDescription) !!doesnt!! and EXIFTOOL adds XMP(tiff:ImageDescription)
    $success = $exifTool->SetNewValue('IFD0:ImageDescription' => $piref->{photocaption});
    print "ERROR - setting caption $success\n" if ($success < 1);
    # Output the caption as IPTC(Caption) and EXIFTOOL adds XMP(dc:Description)
    $success = $exifTool->SetNewValue('IPTC:Caption-Abstract' => $piref->{photocaption});
    print "ERROR - setting caption $success\n" if ($success < 1);
  }
  # Prepare metadata for write: the keyword EVENT
  if ($piref->{photoevent} ne "") {
    print "> Event: $piref->{photoevent}\n";
    # Output the event as IPTC(ObjectName) to represent the Title
    $success = $exifTool->SetNewValue('IPTC:ObjectName' => $piref->{photoevent});
    print "ERROR - setting event $success\n" if ($success < 1);
  }
  # Prepare metadata for write: the Country/State/City hierarchy
  if (defined($piref->{photolocation}[0])) {
    $success = $exifTool->SetNewValue('IPTC:Country-PrimaryLocationName' => $piref->{photolocation}[0]);
    print "ERROR - setting Country $success\n" if ($success < 1);
#    $success = $exifTool->SetNewValue('IPTC:Country-PrimaryLocationCode' => $piref->{photocountrycode});
#    print "ERROR - setting CountryCode $success\n" if ($success < 1);
    if (defined($piref->{photolocation}[1])) {
      $success = $exifTool->SetNewValue('IPTC:Province-State' => $piref->{photolocation}[1]);
      print "ERROR - setting State $success\n" if ($success < 1);
      if (defined($piref->{photolocation}[2])) {
        $success = $exifTool->SetNewValue('IPTC:City' => $piref->{photolocation}[2]);
        print "ERROR - setting City $success\n" if ($success < 1);
        if (defined($piref->{photolocation}[3])) {
          print "> Location: $piref->{photolocation}[0] $piref->{photolocation}[1] $piref->{photolocation}[2] $piref->{photolocation}[3]\n";
          $success = $exifTool->SetNewValue('IPTC:Sub-location' => $piref->{photolocation}[3]);
          print "ERROR - setting SubLocation $success\n" if ($success < 1);
        } else {
          print "> Location: $piref->{photolocation}[0] $piref->{photolocation}[1] $piref->{photolocation}[2]\n";
        }
      } else {
        print "> Location: $piref->{photolocation}[0] $piref->{photolocation}[1]\n";
      }
    } else {
      print "ERROR - Location: $piref->{photolocation}[0] LOCATION MISSING\n";
    }
  }
  # Prepare metadata for write: the GPS information
  if (defined($piref->{photogps}[0])) {
    my $skipgpswrite = 0;
    if ($APPEND) {   # Actually append all other location information, but leave GPS alone
      my $xgpslor = $exifTool->GetValue('GPSLongitudeRef');
      my $xgpslo = $exifTool->GetValue('GPSLongitude');
      my $xgpslar = $exifTool->GetValue('GPSLatitudeRef');
      my $xgpsla = $exifTool->GetValue('GPSLatitude');
      if (defined($xgpslor) || defined($xgpslo) || defined($xgpslar) || defined($xgpsla)) {
        if (defined($xgpslor) && defined($xgpslo) && defined($xgpslar) && defined($xgpsla)) {
          print " ...APPEND: Pre-Existing GPS information:   $xgpslor $xgpslo $xgpslar $xgpsla\n";
        } else {
          print " ...APPEND: Pre-Existing GPS information (incomplete):   $xgpslor $xgpslo $xgpslar $xgpsla\n";
        }
        $skipgpswrite = 1;
      } else {
        print " ...APPEND: Pre-Existing GPS information: NONE\n";
      }
    }
    if ($skipgpswrite == 0) {
      if ($piref->{photogps}[0] < 0) {   # Negative values arent allowed, so have to swap the reference
        $success = $exifTool->SetNewValue('GPS:GPSLongitudeRef' => "W");
      } else {
        $success = $exifTool->SetNewValue('GPS:GPSLongitudeRef' => "E");
      }
      print "ERROR - setting Longitude Ref $success\n" if ($success != 1);
      $success = $exifTool->SetNewValue('GPS:GPSLongitude' => abs($piref->{photogps}[0]));
      print "ERROR - setting Longitude $success\n" if ($success < 1);
      if (defined($piref->{photogps}[1])) {
        if ($piref->{photogps}[1] < 0) {   # Negative values arent allowed, so have to swap the reference
          $success = $exifTool->SetNewValue('GPS:GPSLatitudeRef' => "S");
        } else {
          $success = $exifTool->SetNewValue('GPS:GPSLatitudeRef' => "N");
        }
        print "ERROR - setting Latitude Ref $success\n" if ($success != 1);
        $success = $exifTool->SetNewValue('GPS:GPSLatitude' => abs($piref->{photogps}[1]));
        print "ERROR - setting Latitude $success\n" if ($success < 1);
        print "> GPS: $piref->{photogps}[0] $piref->{photogps}[1]\n";
      } else {
        print "ERROR - GPS: $piref->{photogps}[0] GPS MISSING\n";
      }
    }
  }
  # Prepare metadata for write: the Date/Time
  if (($piref->{photodate} ne "") && ($piref->{photodate} ne $piref->{photocreationdate})) {
    print "> Date: $piref->{photodate}\n";
    $success = $exifTool->SetNewValue('ExifIFD:DateTimeOriginal' => $piref->{photodate});
    print "ERROR - setting DateTime $success\n" if ($success < 1);
    if ($piref->{photocreationdate} eq "7777") {   # Flag to indicate using file modify date
      if ($piref->{photosource} != 2) {  # The ModifyDate is set by good scanners like the NikonScan
        my $mdate = $exifTool->GetValue('ModifyDate');
        if (!defined($mdate)) { # Check both anyway for photoshopped photos
          $mdate = $exifTool->GetValue('FileModifyDate');
        }
        if (ref $mdate eq 'SCALAR') {
          print "ERROR - reading file modify date\n";
          $piref->{photocreationdate} = $photodate;
        } else {
          $piref->{photocreationdate} = $mdate;
        }
      } else {  # For flatbed scanners like the PhotoSmart try the FileModifyDate
        my $mdate = $exifTool->GetValue('FileModifyDate');
        if (ref $mdate eq 'SCALAR') {
          print "ERROR - reading file modify date\n";
          $piref->{photocreationdate} = $photodate;
        } else {
          $piref->{photocreationdate} = $mdate;
        }
      }
    }
    $piref->{photocreationdate} =~ s/\./:/g;  # Scanner used dots instead of colons as date/time separators
    # Method 1
    (my $createdate, my $createtime) = split(/\s+/,$piref->{photocreationdate});
    print "> Creation: $createdate (date) $createtime (time)\n";
    $success = $exifTool->SetNewValue('IPTC:DigitalCreationDate' => $createdate);
    print "ERROR - setting CreationDate $success\n" if ($success < 1);
    $success = $exifTool->SetNewValue('IPTC:DigitalCreationTime' => $createtime);
    print "ERROR - setting CreationTime $success\n" if ($success < 1);
    # Method 2
    $success = $exifTool->SetNewValue('CreateDate' => $piref->{photocreationdate});
    print "ERROR - setting CreateDate $success\n" if ($success < 1);
    # Necessary for Aperture to see image date (PhotoShop probably copies it into XMP-xmp:ModifyDate)
    $success = $exifTool->SetNewValue('IFD0:ModifyDate' => $piref->{photodate});
    print "ERROR - setting ModifyDate $success\n" if ($success < 1);
  }
  #
  ################################
  # Write all meta data to photo #
  ################################
  # Write new meta information to a new file
  if ($piref->{isvideo}) {  # Simply copy movie files and write an xmp info file
    if ($NOWRITE) {
      $success = 1;
    } else {
      if ($outputfilename ne "") {
        $success = File::Copy::copy($inputfilename, $outputfilename);
      }
    }
    if ($success == 0) {
      print "   ERROR on write $!\n";
    } else {
      if ($outputfilename ne "") {
        print "   Copy $success (to $outputfilename)\n";
      } else {
        print "   Copy: No output filename specified so no copy done\n";
      }
    }
    # create XMP data file from scratch
    $outputfilename =~ s/\.avi$/\.xmp/i;
    $outputfilename =~ s/\.wmv$/\.xmp/i;
    $outputfilename =~ s/\.mov$/\.xmp/i;
    $outputfilename =~ s/\.mpg$/\.xmp/i;
    if ($NOWRITE) {
      $success = 1;
    } else {
      if ($outputfilename ne "") {
        $success = $exifTool->WriteInfo(undef, $outputfilename, 'XMP');
      }
    }
    if ($success == 0) {
      my $errorMessage = $exifTool->GetValue('Error');
      print "   ERROR - on xmp write $errorMessage (to $outputfilename)\n";
    } else {
      if ($outputfilename ne "") {
        print "   Write $success (to $outputfilename)\n";
      } else {
        print "   Write: No output filename specified so no xmp write done\n";
      }
    }
  } else {  # So long as not a movie file
    if ($NOWRITE) {
      $success = 1;
    } else {
      if ($outputfilename ne "") {
        $success = $exifTool->WriteInfo($inputfilename, $outputfilename);
      } else {
        $success = $exifTool->WriteInfo($inputfilename);
      }
    }
    my $updatedfile = "";
    if ($success == 0) {
      my $errorMessage = $exifTool->GetValue('Error');
      print "   ERROR - on write $errorMessage\n";
    } else {
      if ($outputfilename ne "") {
        print ">   Write $success (to $outputfilename)\n";
        $updatedfile = $outputfilename;
      } else {
        print ">   Write $success (overwrote $inputfilename)\n";
        $updatedfile = $inputfilename;
      }
      if ($updatedfile =~ /png$/i) {
        # If it was a PNG file, Aperture will not read the updated metadata directly,
        # it has to be copied to an XMP sidecar file instead (and then new version from original in Aperture)
        my $xmpfile = $updatedfile;
        $xmpfile =~ s/\.png$/\.xmp/i;
        my $perlargsdir = "/Users/Tim/Library/Perl/Sources/Image-ExifTool-9.45/arg_files";
        my $cmd = "/usr/bin/exiftool -tagsfromfile \"$updatedfile\" -@ $perlargsdir/exif2xmp.args -@ $perlargsdir/iptc2xmp.args \"$xmpfile\"";
        printf("XMP generation command: %s\n", $cmd) if $DEBUG;
        system($cmd);
        print ">   Wrote sidecar as well: $xmpfile\n";
      }
    }
  }
  return $success;
}
