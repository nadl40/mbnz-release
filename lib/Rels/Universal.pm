#!/usr/bin/perl
package Rels::Universal;

use strict;
use warnings;

use Selenium::Remote::Driver;

#use Selenium::ActionChains;
#use Encode 'encode';
use Data::Dumper::Simple;
use Selenium::Waiter qw/ wait_until /;
use HTTP::Request ();
use JSON::MaybeXS qw(encode_json decode_json);

#use LWP::UserAgent;
#use XML::LibXML;
#use URI::Escape;
#use Hash::Persistent;
#use Getopt::Long;
use String::Util qw(trim);
use Selenium::Remote::WDKeys;

#use Config::General;
#use Env;

# export module
use Exporter qw(import);
our @EXPORT_OK = qw( getUniversalCatalogue);

$| = 1;
binmode( STDOUT, "encoding(UTF-8)" );

# get Universal catalogue artist track credits
sub getUniversalCatalogue {
 my ($idagio) = @_;

 my $album = {};

 # find url for a relase using upc
 my $url = &getUrl( $idagio->{"upc"} );

 # if release not found, return
 if ( !$url ) {
  print("no url found for Universal\n");
  return;
 }

 # get catalogue data
 $album = &getCatalogue($url);

 my $artistHash = &getArtistTracks($album);

 #print Dumper($album);

 #print Dumper($idagio);
 # adjust track credits
 &adjustTrackCredits( $idagio, $artistHash );

 #print Dumper($idagio);

 #exit;
 return;

}

# adjust idagio track credits
sub adjustTrackCredits {
 my ( $idagio, $artistHash ) = @_;

 #print Dumper($artistHash);
 print Dumper($idagio);
 #exit;

 # idagio tracks are sequential, no volumes, need to match Universal tracks to idagio tracks
 # loop thru Universal tracks sorted by volume and track
 my $trackCount = 0;
 foreach my $volume ( sort { $a cmp $b } keys %{$artistHash} ) {
  print Dumper($volume);
 }    # end of volumes

 #exit;
}

# do search against catalogues using upc, get url
sub getUrl {
 my ($upc) = @_;

 # use hash of options to pass to sub
 # expand as necessary
 my %deccaSearch = (
  "url"         => "https://www.deccaclassics.com/en/catalogue",
  "searchClass" => "_3dDYk",
  "hrefClass"   => "_3_96o",
 );

 my %dgSearch = (
  "url"         => "https://www.deutschegrammophon.com/en/catalogue",
  "searchClass" => "_3dDYk",
  "hrefClass"   => "_3_96o",
 );

 # try Decca first
 my $url = &search( \%deccaSearch, $upc );

 # if no url, try DG
 if ( !$url ) {
  $url = &search( \%dgSearch, $upc );
 }

 return $url;

}

# search for a release
sub search {
 my ( $searchUrl, $upc ) = @_;

 print Dumper($searchUrl);
 print Dumper($upc);

 my $driver = Selenium::Remote::Driver->new(

  #debug        => 1,
  browser_name => 'chrome',

  # run headless, loosing elements
  extra_capabilities => {
   'goog:chromeOptions' => {
    'args' => ['start-maximized'],
   }
  },
  port => '9515'
 );

 # get page
 $driver->get( $searchUrl->{"url"} );
 sleep(5);

 # decline cookies
 &cookies( $driver, $searchUrl->{"url"} );

 my $element = "";
 my $href    = "";

 # get search element by class name _3dDYk wait
 wait_until { $element = $driver->find_element( $searchUrl->{"searchClass"}, 'class_name' ) };
 if ($element) {
  $element->send_keys($upc);
  $element->click();
 }
 sleep(5);

 # get url element with class name _ZlLzU wait
 wait_until { $element = $driver->find_element( $searchUrl->{"hrefClass"}, 'class_name' ) };
 if ($element) {

  # get href link from element
  $href = $element->get_attribute('href');
  print Dumper($href);

 }
 $driver->quit();

 return $href;

}

# get artists per tracks from ?
sub getArtistTracks {
 my ($album) = @_;
 print("getArtistTracks\n");

 #print Dumper($album);
 #exit;


 foreach my $volume ( keys %{ $album->{"volume"} } ) {

  $volumeHash->{$volume} = 0;

  foreach my $track ( keys %{ $album->{"volume"}->{$volume}->{"track"} } ) {

   # increment number of tracks for volume
   $volumeHash->{$volume}++;

   my $artist = $album->{"volume"}->{$volume}->{"track"}->{$track}->{"artists"};

   # add duration in seconds
   # convert duration to seconds
   my $seconds  = 0;
   my $duration = $album->{"volume"}->{$volume}->{"track"}->{$track}->{"duration"};
   if ($duration) {
    my @durationArray = split( ":", $duration );
    $seconds       = $durationArray[0] * 60 + $durationArray[1];
    $albumDuration = $albumDuration + $seconds;
   }

   # split $artist by comma
   if ($artist) {
    my @artistArray = split( ",", $artist );
    foreach my $artistName (@artistArray) {

     # trim spaces
     $artistName = trim($artistName);

     # add to hash volume and track
     push @{ $artistHash->{"artists"}->{$artistName}->{"tracks"}->{$volume} }, $track;
     $artistHash->{"artists"}->{$artistName}->{"duration"} += $seconds;
    }
   } else {
    push @{ $artistHash->{"artists"}->{"unknown"}->{"tracks"}->{$volume} }, $track;
    $artistHash->{"artists"}->{"unknown"}->{"duration"} += $seconds;
   }
  }
 }

 # add total duration to album hash
 $album->{"duration"} = $albumDuration;

 print Dumper($artistHash);
 #exit;

 return $artistHash;

}

# main sub to get catalogue data, it returns a hash
sub getCatalogue {
 my ($url) = @_;

 # start webdriver, eventually headless
 # ./operadriver --url-base=/wd/hub
 my $driver = Selenium::Remote::Driver->new(

  #debug        => 1,
  browser_name => 'chrome',

  # run headless, loosing elements
  extra_capabilities => {
   'goog:chromeOptions' => {
    'args' => ['start-maximized'],
   }
  },
  port => '9515'
 );

 # for mouse moves
 #my $action_chains = Selenium::ActionChains->new( driver => $driver );

 #$driver->maximize_window();

 # open page
 wait_until { ( $driver->get($url) ) };
 sleep(5);

 # generic vars
 my $element        = "";
 my @elementArray   = ();
 my $i              = 0;
 my $size           = 0;
 my $tracksExpanded = 0;
 my $album          = {};    # holds album details
 my $volume         = "";

 # decline cookies
 &cookies( $driver, $url );

 # get album level data
 &getAlbumData( $driver, $album );

 #print Dumper($album);

 # show track listing
 wait_until { $element = $driver->find_element( "button._osfUD._3tuNp._3qtf1._2eBmm", "css" ) };
 if ($element) {
  $element->click();
 }

 # first cd auto expands, wait for it
 sleep(5);

 # get major parts, if applicable, especially for Opera
 # don't need that for original track listing

 # first volume
 my @trackArray = ();
 wait_until { @trackArray = $driver->find_elements( "css-1lpvoxz", "class_name" ) };
 $size = @trackArray;
 if ( $size == 0 ) {
  print("no tracks found, this scripts only works with older style pages, something to expand perhaps.\n");
  $driver->quit();
  exit;
 }
 print( "number of tracks: ", $size, "\n" );

 # loop thru tracks and expand
 foreach my $track (@trackArray) {
  $tracksExpanded++;
  print( "\ttrack: ", $tracksExpanded, "\n" );

  # expand it
  #sleep(1);
  $track->click();
 }    # end of tracks
 print( "tracks expanded: ", $tracksExpanded, "\n" );

 # expand tracks from next volume
 # it looks like tracks are clicable only after related volume is expanded
 wait_until { @elementArray = $driver->find_elements( "_39TBi", "class_name" ) };
 $size = @elementArray;
 print( "number of cds: ", $size, "\n" );

 #exit;
 my $cd = 0;
 foreach my $element (@elementArray) {
  $cd++;

  if ( $cd > 1 ) {
   print( "cd: ", $cd, "\n" );
   $element->click();
   sleep(5);

   @trackArray = ();
   wait_until { @trackArray = $driver->find_elements( "css-1lpvoxz", "class_name" ) };
   $size = @trackArray;
   print( "total number of tracks: ",  $size,           "\n" );
   print( "tracks already expanded: ", $tracksExpanded, "\n" );

   #sleep(30);

   # loop thru tracks and expand
   $i = 0;
   foreach my $track (@trackArray) {
    $i++;

    # expand it
    #sleep(1);
    if ( $i > $tracksExpanded ) {
     $tracksExpanded++;
     print( "\ttrack: ", $tracksExpanded, "\n" );
     $track->click();
    }
   }    # end of tracks
   print( "tracks expanded: ", $tracksExpanded, "\n" );
  }    # greater than cd 1
 }

 # get all expanded track info
 @trackArray = ();
 wait_until { @trackArray = $driver->find_elements( "_1RPNl", "class_name" ) };
 $size = @trackArray;
 print( "number of info for tracks: ", $size, "\n" );

 # loop thru track info elements
 $i = 0;
 my $trackCount = "0";
 foreach my $info (@trackArray) {
  $i++;
  $trackCount++;
  print( "\tinfo: ", $i, "\n" );

  # run a sub to work on the element
  ( $trackCount, $volume, $album ) = &processTrackInfo( $driver, $trackCount, $volume, $info, $album );

 }    # end of tracks

 #print Dumper($album);
 $driver->quit();

 return $album;

}

# get album data
sub getAlbumData {
 my ( $driver, $album ) = @_;

 my $element = "";

 # get album title
 $element = wait_until { $driver->find_element( '_3Y0Lj', 'class_name' ) };
 if ($element) {
  $album->{"title"} = $element->get_text();
 }

 # get UPC and label
 # _ra0iJ
 $element = wait_until { $driver->find_element( '_ra0iJ', 'class_name' ) };
 my $text = $element->get_text();

 # split by newline
 my @textArray = split( "\n", $text );

 if ( $textArray[1] ) {
  $album->{"label"} = $textArray[1];
 } else {
  $album->{"label"} = "";
 }

 if ( $textArray[3] ) {
  $album->{"upc"} = $textArray[3];
 } else {
  $album->{"upc"} = "";
 }

 # get release date
 $element = wait_until { $driver->find_element( '_6GMq7', 'class_name' ) };
 if ($element) {
  $album->{"releaseDate"} = $element->get_text();
 }

 #get cover
 $element = wait_until { $driver->find_element( '_RhlOl', 'class_name' ) };
 if ($element) {
  $album->{"cover"} = $element->get_attribute('src');
 }

}

# process track info element
sub processTrackInfo {
 my ( $driver, $myTrackCount, $volume, $info, $album ) = @_;

 my ( $trackNo, $composer, $title, $artists, $duration, $firstRelease, $recordingDate, $recordingLocation, $producers, $engineers ) = "";

 # get all track info elements
 my $elements = wait_until { $driver->find_child_elements( $info, 'tr', "css" ) };

 # loop thru @elements of a track and grep for what we need
 ( $trackNo, $composer, $title, $artists, $duration, $firstRelease, $recordingDate, $recordingLocation, $producers, $engineers ) = "";
 foreach my $element (@$elements) {

  my $text = $element->get_text();

  # it is possible that Info is missing, so at least add empty track

  # if $text starts with word Track, it's a track number
  if ( $text =~ m/^Track/ ) {
   $trackNo = $text;
   $trackNo =~ s/Track\s//;
   $trackNo =~ s/\s//g;

   # add 2 leading zeros to make it 3 digits
   #$trackNo = sprintf( "%03d", $trackNo );
   if ( $trackNo eq '1' ) {
    if ( $volume eq '0' ) {
     $volume = 1;
    } else {
     $volume++;
     $myTrackCount = 1;
    }
   }
  }

  # if there is no info, create an empty track
  if ( !$trackNo ) {
   $trackNo = $myTrackCount;
  }

  # if $text starts with word Composer, it's a composer
  if ( $text =~ m/^Composer/ ) {
   $composer = $text;
   $composer =~ s/Composer\s//;

   # remove text pass comma
   $composer =~ s/,.*//;

   # remove text between round brackets
   $composer =~ s/\(.*\)//;

   # remove trailing spaces
   $composer = trim($composer);
  }

  # if $text starts with word Title, it's a title
  if ( $text =~ m/^Title/ ) {
   $title = $text;
   $title =~ s/Title\s//;

   # replace - with :
   $title =~ s/ - /: /g;
  }

  # if $text starts with word Artists, it's a artists
  if ( $text =~ m/^Artists/ ) {
   $artists = $text;
   $artists =~ s/Artists\s//;
  }

  # if $text starts with word Duration, it's a duration
  if ( $text =~ m/^Duration/ ) {
   $duration = $text;
   $duration =~ s/Duration\s//;
  }

  # if $text starts with word First Release, it's a first release
  if ( $text =~ m/^First Release/ ) {
   $firstRelease = $text;
   $firstRelease =~ s/First Release\s//;
  }

  # if $text starts with word Recording Date, it's a recording date
  if ( $text =~ m/^Recording Date/ ) {
   $recordingDate = $text;
   $recordingDate =~ s/Recording Date\s//;
  }

  # if $text starts with word Recording Location, it's a recording location
  if ( $text =~ m/^Recording Location/ ) {
   $recordingLocation = $text;
   $recordingLocation =~ s/Recording Location\s//;

   # replace newline ith comma
   $recordingLocation =~ s/\n/, /g;
  }

  # if $text starts with word Producers, it's a producers
  if ( $text =~ m/^Producers/ ) {
   $producers = $text;
   $producers =~ s/Producers\s//;

   # replace newline with comma
   $producers =~ s/\n/, /g;
  }

  # if $text starts with word Engineers, it's a engineers
  if ( $text =~ m/^Engineers/ ) {
   $engineers = $text;
   $engineers =~ s/Engineers\s//;
   $engineers =~ s/\n/, /g;
  }

 }    # end of tracks info

 # add to album hash
 # if $trackNo not null
 print Dumper($trackNo);
 my $trackPrint = sprintf( "%03d", $trackNo );
 my $volPrint   = sprintf( "%03d", $volume );
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"composer"}          = $composer;
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"title"}             = $title;
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"artists"}           = $artists;
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"duration"}          = $duration;
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"firstRelease"}      = $firstRelease;
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"recordingDate"}     = $recordingDate;
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"recordingLocation"} = $recordingLocation;
 $album->{"volume"}->{$volPrint}->{"track"}->{$trackPrint}->{"engineers"}         = $engineers;

 #print Dumper($album);
 #$driver->quit();
 #exit;
 return ( $myTrackCount, $volume, $album );
}

# reject all cookies
sub cookies {
 my ( $driver, $url ) = @_;

 my $element = "";

 # if url contains deccaclassics it's a Decca release
 if ( $url =~ m/deccaclassics/ ) {
  wait_until { $element = $driver->find_element_by_xpath('/html/body/div[3]/button[1]') };
  if ($element) {
   $element->click();
  }
 }

 # if url contains deutschegrammophon it's a DG release
 if ( $url =~ m/deutschegrammophon/ ) {
  my $shadow_host   = $driver->find_element( "cmpwrapper", "class_name" );
  my $shadow_driver = MyShadow->new( driver => $driver, shadow_host => $shadow_host );
  if ($shadow_driver) {
   for my $element ( @{ $shadow_driver->find_elements( '#cmpwelcomebtnsave > a', 'css' ) } ) {
    $element->click();
   }
  }
 }

}

1;
