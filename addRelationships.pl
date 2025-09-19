#!/usr/bin/env perl
#*******************************************************************************
#
# This is an attempt to add relationships to an exisitng relese in MB
#  --- second cut, using batch updates
#
#  --- updated for new MB Relationship Editor
#      had to slow it down as MB is more sluggish
#
#*******************************************************************************
use Selenium::Remote::Driver;
use Encode 'encode';
use Data::Dumper::Simple;
use Selenium::Waiter qw/ wait_until /;
use HTTP::Request ();
use JSON::MaybeXS qw(encode_json decode_json);
use Data::Dumper::Simple;
use LWP::UserAgent;
use XML::LibXML;
use URI::Escape;
use Hash::Persistent;
use Getopt::Long;
use String::Util qw(trim);
use Selenium::Remote::WDKeys;
use Config::General;
use Env;

use strict;
use warnings;

#for my modules start
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname( dirname abs_path $0) . '/mbnz/lib';
use Rels::Utils qw(readConfig);

$| = 1;
binmode( STDOUT, "encoding(UTF-8)" );

# set constant for sleep in seconds
use constant WAIT_FOR_MB => '1.5';

#how many iterations of above when saving to db
use constant WAIT_FOR_MB_SAVE => '1.5';

# get user id and pass
#define conf path
my $confPath  = ${HOME} . "/.config/mbnz";
my $confFile  = "mbnz.conf";
my $configRef = &readConfig( $confPath, $confFile );    #read config file

# get command line arguments
my ( $releaseId, $dataFileName ) = "";
GetOptions(
 "release:s" => \$releaseId,

);

if ( !$releaseId ) {
 print( "please provide release id  --release", "\n" );
 exit;
}

# get release id only
my @releaseWork   = split( "\/", $releaseId );
my $releaseIdWork = pop(@releaseWork);
if ($releaseIdWork) {
 $releaseId = $releaseIdWork;
}

$dataFileName = "relationshipsSerial.txt";

if ( -e $dataFileName ) {
} else {
 print( "data file does not exist ", $dataFileName, "\n" );
 exit;
}

#read in relationship hash
my $obj     = Hash::Persistent->new($dataFileName);
my $hashRel = $obj->{string};                         # make sure this is a proper hash reference, watch out for "\"
undef $obj;

# start the driver and login
# ./operadriver --url-base=/wd/hub
my $driver = Selenium::Remote::Driver->new(

 #debug        => 1,
 browser_name => 'chrome',

 # extra_capabilities => {
 #  'goog:chromeOptions' => {
 #   'args'  => [ 'window-size=1260,960', 'incognito' ],
 #  }
 # }
 port => '9515'
);

$driver->maximize_window();

#login
&login( $driver, $configRef->{authentication}->{user}, $configRef->{authentication}->{password} );

#open release editor
#my $sel = "https://test.musicbrainz.org/release/" . $releaseId . "/edit-relationships";
my $sel = "https://musicbrainz.org/release/" . $releaseId . "/edit-relationships";

# allow js to build elements
# it takes much longer with the new editr, allow to build
$driver->get($sel);
sleep( WAIT_FOR_MB * 7 );

# get main elements
my ( $element, $recording, $recordingSelector ) = "";
my @trackSelector = ();

#if more than 100 tracks on single volume, need to click expand to all tracks
my $numberOfTracks = keys %{ $hashRel->{"works"} };
if ( $numberOfTracks > 100 ) {
 my $element = $driver->find_element_by_class_name('load-tracks');
 if ($element) {
  $element->click();
  sleep( WAIT_FOR_MB * 2 );
 }
}

# need to expand volume arrows for CD's,  if present
my @volumesArrow = $driver->find_elements( "expand-triangle", "class_name" );
my $arrowCount   = 0;
foreach my $volumeArrow (@volumesArrow) {

 # first 10 open by default
 $arrowCount++;
 if ( $arrowCount > 10 ) {
  $volumeArrow->click();
  sleep(WAIT_FOR_MB);
 }
}

# Note
my $crlf     = chr(10) . chr(13);
my $noteText = $hashRel->{"url"} . $crlf . "addRelationships.pl Classical Music Uploader" . $crlf . "https://github.com/nadl40/mbnz-release";
$element = wait_until { $driver->find_element_by_class_name('editnote') };
my $note = wait_until { $driver->find_child_element( $element, './div/textarea' ) };

# checkboxes to select a track
my @tracks = $driver->find_elements( "track", "class_name" );
foreach my $track (@tracks) {
 $recording         = wait_until { $driver->find_child_element( $track,     'recording', "class_name" ) };
 $recordingSelector = wait_until { $driver->find_child_element( $recording, './input' ) };
 push @trackSelector, $recordingSelector;
}

my $size = @trackSelector;
print "number of tracks selected: ", $size, "\n";

# checkbox to select all recordings, for clean up
$element = wait_until { $driver->find_element_by_class_name('recordings') };
my $recordingsSelected = wait_until { $driver->find_child_element( $element, './input' ) };

# checkbox to select a work
# use css selector
my $batchAdd = wait_until { $driver->find_element( ".add-item.with-label.batch-add-recording-relationship", "css" ) };

# work selector
my @workSelector = ();

# there is no need for wait_until, built in ?
my @works = $driver->find_elements( "works", "class_name" );

# drop first element as it uses the same class name as checkboxes to recordings
shift @works;
foreach my $work (@works) {
 my $workAdd = wait_until { $driver->find_child_element( $work, './button', 'xpath' ) };
 push @workSelector, $workAdd;
}
$size = @workSelector;
print "number of works selected: ", $size, "\n";

# loop relationship hash
foreach my $type ( keys %{$hashRel} ) {

 #print Dumper($type);
 if ( $type ne "volumes" && $type ne "url" && $type ne "works" ) {
  &addCredits( $hashRel->{"volumes"}, $type, $driver, $hashRel->{$type}, $batchAdd, $recordingsSelected, @trackSelector );
 }
}

# loop for work
foreach my $type ( keys %{$hashRel} ) {

 if ( $type eq "works" ) {    #
  &addWorks( $driver, $hashRel->{$type}, @workSelector );
 }
}

# add note at the end
$note->send_keys($noteText);

# quit manually as this gives time on long or problematic releases
sleep 3000;

#$driver->quit();

#************************************************
#
# Subs
#
#************************************************

### add Credits ###
sub addWorks {
 my ( $driver, $works, @workSelector ) = @_;

 #sort tracks in sequence, it's a hash.
 my $i = 0;
 foreach my $track ( sort { $a cmp $b } keys %{$works} ) {

  if ( $works->{$track} ) {

   $workSelector[ $track - 1 ]->click();
   sleep(WAIT_FOR_MB);

   wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Work");
   sleep(WAIT_FOR_MB);

   # this is not required, it defaults
   #$driver->find_element('.relationship-type.required','css')->send_keys("recording of");

   # work mb id
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $works->{$track} );
      
   sleep(WAIT_FOR_MB);

   &clickSave( $driver, WAIT_FOR_MB_SAVE * 2 );

  }    # if works exists

 }    # loop

}    # sub

### add Credits ###
sub addCredits {
 my ( $volumes, $type, $driver, $artists, $batchAddButton, $recordingsSelectedCheckBox, @trackSelector ) = @_;

 my @tracks = ();

 foreach my $artistId ( keys %{$artists} ) {

  # artists can have multiple insruments
  print( "\n", $type, "->", $artists->{$artistId}->{"name"}, "\n" );

  ### venue ###
  if ( $type eq 'venue' ) {

   &addVenueRel( $driver, $artists->{$artistId}, $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector );
  }

  ### ensembles ###
  if ( $type =~ m/(ensembles|ensemble)/i ) {

   #print( "ensemble ", $artistId, "\n" );
   &addEnsembleRel( $driver, $artists->{$artistId}, $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector );
  }

  ### conductor ###
  if ( $type eq 'conductor' ) {

   #print( "conductor ", $artistId, "\n" );
   &addConductorRel( $driver, $artists->{$artistId}, $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector );
  }

  ### soloists ###
  if ( $type =~ m/(soloists|soloist)/i ) {

   &addArtistRel( $driver, $artists->{$artistId}, $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector );
  }

 }    # artist

}

### add venues attributes ###
sub addVenueRel {
 my ( $driver, $artist, $volumes, $batchAddButton, $recordingsSelectedCheckBox, $trackSelectorRef ) = @_;

 my @trackSelector = @{$trackSelectorRef};

 foreach my $tracks ( keys %{ $artist->{"venue"} } ) {

  my @tracks = @{ $artist->{"venue"}->{$tracks}->{"tracks"} };

  &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, @tracks );

  my $selected = "";

  wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Place");
  sleep(WAIT_FOR_MB);
  wait_until { $driver->find_element( '//input[@placeholder="Type or click to search"]', 'xpath' ) }->send_keys("recorded-at");
  $driver->send_keys_to_active_element( KEYS->{'enter'} );
  sleep(WAIT_FOR_MB);

  if ( $artist->{"id"} ) {
   print Dumper( $artist->{"id"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $artist->{"id"} );
   sleep(WAIT_FOR_MB);
  } else {
   print Dumper( $artist->{"name"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
   $driver->send_keys_to_active_element( KEYS->{'enter'} );
  }

  # credited as
  sleep(WAIT_FOR_MB);
  if ( $artist->{"name"} ) {
   wait_until { $driver->find_element( '//input[@placeholder="Credited as"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
  }

  my $dateEntered = "";
  if ( $artist->{"recording_date"}->{"year"} ) {

   # there are 2 classes for Begin and End
   # use the first one
   # use labels if Begin and End is avaliable
   my @elements = $driver->find_element( 'partial-date-year', 'class_name' );
   $elements[0]->send_keys( $artist->{"recording_date"}->{"year"} );
   $dateEntered = "yes";
  }

  if ( $artist->{"recording_date"}->{"month"} ) {
   my @elements = $driver->find_element( 'partial-date-month', 'class_name' );
   $elements[0]->send_keys( $artist->{"recording_date"}->{"month"} );
  }

  if ( $artist->{"recording_date"}->{"day"} ) {
   my @elements = $driver->find_element( 'partial-date-day', 'class_name' );
   $elements[0]->send_keys( $artist->{"recording_date"}->{"day"} );
  }

  # copy to end date unless we have end dates, idagio does not seems to have it
  # discogs does not have at all
  # use // for xpath to start from the root of popup
  if ($dateEntered) {
   my $element = $driver->find_element( '//button[@title="Copy to end date"]', 'xpath' );
   $element->click();
   sleep(WAIT_FOR_MB);
  }

  $driver->send_keys_to_active_element( KEYS->{'enter'} );
  &clickSave( $driver, WAIT_FOR_MB_SAVE * 2 );

 }

}

### add ensemble attributes ###
sub addEnsembleRel {
 my ( $driver, $artist, $volumes, $batchAddButton, $recordingsSelectedCheckBox, $trackSelectorRef ) = @_;

 my @trackSelector = @{$trackSelectorRef};

 foreach my $instrument ( keys %{ $artist->{"instrument"} } ) {

  my @tracks = @{ $artist->{"instrument"}->{$instrument}->{"tracks"} };

  &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, @tracks );

  my $selected = "";

  wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Artist");
  sleep(WAIT_FOR_MB);

  wait_until { $driver->find_element( '//input[@placeholder="Type or click to search"]', 'xpath' ) }->send_keys( "orchestra" . " " );
  sleep(WAIT_FOR_MB);
  $driver->send_keys_to_active_element( KEYS->{'enter'} );

  if ( $artist->{"id"} ) {
   print Dumper( $artist->{"id"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $artist->{"id"} );
   sleep(WAIT_FOR_MB);
  } else {
   print Dumper( $artist->{"name"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
   $driver->send_keys_to_active_element( KEYS->{'enter'} );
  }

  # credited as
  sleep(WAIT_FOR_MB);
  if ( $artist->{"name"} ) {
   wait_until { $driver->find_element( '//input[@placeholder="Credited as"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
  }

  &clickSave( $driver, WAIT_FOR_MB_SAVE * 2 );

 }

}

### add conductor attributes ###
sub addConductorRel {
 my ( $driver, $artist, $volumes, $batchAddButton, $recordingsSelectedCheckBox, $trackSelectorRef ) = @_;

 my @trackSelector = @{$trackSelectorRef};

 foreach my $instrument ( keys %{ $artist->{"instrument"} } ) {

  my @tracks = @{ $artist->{"instrument"}->{$instrument}->{"tracks"} };

  &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, @tracks );

  my $selected = "";

  wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Artist");
  sleep(WAIT_FOR_MB);

  wait_until { $driver->find_element( '//input[@placeholder="Type or click to search"]', 'xpath' ) }->send_keys("conductor");
  sleep(WAIT_FOR_MB);
  $driver->send_keys_to_active_element( KEYS->{'enter'} );

  if ( $artist->{"id"} ) {
   print Dumper( $artist->{"id"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $artist->{"id"} );
   sleep(WAIT_FOR_MB);
  } else {
   print Dumper( $artist->{"name"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
   $driver->send_keys_to_active_element( KEYS->{'enter'} );
  }

  # credited as
  sleep(WAIT_FOR_MB);
  if ( $artist->{"name"} ) {
   wait_until { $driver->find_element( '//input[@placeholder="Credited as"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
  }

  &clickSave( $driver, WAIT_FOR_MB_SAVE * 2 );

 }

}

### add artist attributes ###
sub addArtistRel {

 my ( $driver, $artist, $volumes, $batchAddButton, $recordingsSelectedCheckBox, $trackSelectorRef ) = @_;

 my @trackSelector = @{$trackSelectorRef};

 # artists can have multiple instruments per track, common in non Classical
 foreach my $instrument ( keys %{ $artist->{"instrument"} } ) {

  my @tracks = @{ $artist->{"instrument"}->{$instrument}->{"tracks"} };

  &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, @tracks );

  my $selected = "";

  wait_until { $driver->find_element( 'entity-type', 'class' ) }->send_keys("Artist");

  my $creditType = "";
  if ( $artist->{"instrument"}->{$instrument}->{"keystrokes"} ) {
   $creditType = "vocals";
  } else {
   $creditType = "instruments";
  }
  wait_until { $driver->find_element( '//input[@placeholder="Type or click to search"]', 'xpath' ) }->send_keys($creditType);
  $driver->send_keys_to_active_element( KEYS->{'enter'} );

  # need  enter only for name
  my $keyValue = "";
  if ( $artist->{"id"} ) {
   print Dumper( $artist->{"id"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' )->send_keys( $artist->{"id"} ) };
   #$element->send_keys( $artist->{"id"});
   sleep(WAIT_FOR_MB);
   sleep(WAIT_FOR_MB);
  } else {
   print Dumper( $artist->{"name"} );
   wait_until { $driver->find_element( '//input[@placeholder="Type to search, or paste an MBID"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
   $driver->send_keys_to_active_element( KEYS->{'enter'} );
  }

  # credited as
  sleep(WAIT_FOR_MB);
  if ( $artist->{"name"} ) {
   wait_until { $driver->find_element( '//input[@placeholder="Credited as"]', 'xpath' ) }->send_keys( $artist->{"name"} );
   sleep(WAIT_FOR_MB);
  }

  #print Dumper($creditType);
  #instruments
  if ( $creditType eq "instruments" ) {
   if ( $artist->{"instrument"}->{$instrument}->{"id"} ) {
    wait_until { $driver->find_element( '//input[@placeholder="instrument"]', 'xpath' ) }->send_keys( $artist->{"instrument"}->{$instrument}->{"id"} );
   } else {
    $keyValue = $artist->{"instrument"}->{$instrument}->{"name"};
    wait_until { $driver->find_element( '//input[@placeholder="instrument"]', 'xpath' ) }->send_keys( $artist->{"instrument"}->{$instrument}->{"name"} );
    $driver->send_keys_to_active_element( KEYS->{'enter'} );
   }
  }

  # incase I need inputs
  #wait_until {$driver->find_element( '//input[@placeholder="instrument"]', 'xpath' )}->send_keys( $keyValue );
  #$driver->send_keys_to_active_element( KEYS->{'enter'} );
  #my @inputs  = $driver->find_child_elements( $element, 'input', 'css' );

  # take first input
  #if ( $artist->{"instrument"}->{$instrument}->{"id"} ) {
  # $inputs[0]->send_keys( $artist->{"instrument"}->{$instrument}->{"id"} );
  # sleep(WAIT_FOR_MB);
  #} else {
  # $inputs[0]->send_keys( $artist->{"instrument"}->{$instrument}->{"name"} );
  # sleep(WAIT_FOR_MB);
  # $driver->send_keys_to_active_element( KEYS->{'enter'} );
  #}
  #}

  #vocals
  if ( $creditType eq "vocals" ) {
   if ( $artist->{"instrument"}->{$instrument}->{"keystrokes"} ) {
    my $vocalString = "";
    if ( $artist->{"instrument"}->{$instrument}->{"name"} =~ m/vocals/i ) {
     $vocalString = lc( $artist->{"instrument"}->{$instrument}->{"name"} );
    } else {
     $vocalString = lc( $artist->{"instrument"}->{$instrument}->{"name"} ) . " vocals";
    }
    wait_until { $driver->find_element( '//input[@placeholder="vocal"]', 'xpath' ) }->send_keys($vocalString);
    $driver->send_keys_to_active_element( KEYS->{'enter'} );
   }
  }

  &clickSave( $driver, WAIT_FOR_MB_SAVE * 2 );

 }    #instrument

}

### select all releavant tracks
sub prepSelection {
 my ( $volumes, $batchAddButton, $recordingsSelectedCheckBox, $trackSelectorRef, @tracks ) = @_;

 my @trackSelector = @{$trackSelectorRef};

 # reset track selection
 $recordingsSelectedCheckBox->click();
 sleep(WAIT_FOR_MB);

 $recordingsSelectedCheckBox->click();
 sleep(WAIT_FOR_MB);

 # select tracks
 my $tracksSize        = @tracks;
 my $trackSelectorSize = @trackSelector;

 # click 1 track at the time, more reliable
 my @sortedTracks = sort { $a <=> $b } @tracks;

 #print Dumper(@sortedTracks);
 my $trackToClick = 0;
 foreach my $track (@sortedTracks) {

  $trackToClick = &offsetTracks( $track, $volumes );
  $trackSelector[ $trackToClick - 1 ]->click();
  sleep( WAIT_FOR_MB / 2 );
 }

 #select batch add
 $batchAddButton->click();
 sleep(WAIT_FOR_MB);

}

# offset tracks by volume if any
sub offsetTracks {
 my ( $track, $volumes ) = @_;

 #print Dumper($track, $volumes);

 my $trackAll = 0;
 my @arr      = split( "-", $track );

 # if volume from disocgs and we have volume hash
 if ( $arr[1] && $volumes ) {

  # need to loop and add tracks to create offset
  my $offset = 0;
  foreach my $volume ( keys %{$volumes} ) {
   if ( $volume < $arr[0] ) {
    $offset = $offset + $volumes->{$volume};
   }
  }
  $trackAll = $offset + $arr[1];

  # no volume info
 } else {
  $trackAll = $track;
 }    # volumes

 #print Dumper($trackAll);
 return $trackAll;

}

### click save
sub clickSave {
 my ( $driver, $waits ) = @_;

 my $selected = "";
 wait_until { $selected = $driver->find_element_by_xpath('//button[normalize-space()="Done"]') }->click();
 for my $i ( 0 .. $waits - 1 ) {
  sleep(WAIT_FOR_MB);
 }

}

### log in ###
sub login {
 my ( $driver, $userid, $password ) = @_;

 my $depth = 1;

 #my $sel = 'https://test.musicbrainz.org/login';
 my $sel = 'https://musicbrainz.org/login';
 $driver->get($sel);

 wait_until { $driver->find_element_by_name('username') }->send_keys($userid);
 $driver->find_element_by_name('password')->send_keys($password);
 $driver->find_element_by_class("login")->click();

}

__END__
