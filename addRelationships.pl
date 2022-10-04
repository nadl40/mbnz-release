#!/usr/bin/env perl
#*******************************************************************************
#
# This is an attempt to add relationships to an exisitng relese in MB
#  --- second cut, using batch updates
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

# set constant for sleep in seconds
use constant WAIT_FOR_MB => '1.5';

#how many iterations of above when saving to db
use constant WAIT_FOR_MB_SAVE => '1';

# get user id and pass
#define conf path
my $confPath  = ${HOME} . "/.config/mbnz";
my $confFile  = "mbnz.conf";
my $configRef = &readConfig( $confPath, $confFile );    #read config file

#print Dumper($configRef);exit(0);

# get command line arguments
my ( $releaseId, $dataFileName ) = "";
GetOptions(
 "release:s" => \$releaseId,
 "data:s"    => \$dataFileName,

);

if ( !$releaseId ) {
 print( "please provide release id  --release", "\n" );
 exit;
}

if ( !$dataFileName ) {
 print( "please provide relationship hash data  --data", "\n" );
 exit;
}

if ( -e $dataFileName ) {
} else {
 print( "data file does not exist ", $dataFileName, "\n" );
 exit;
}

#read in relationship hash
my $obj     = Hash::Persistent->new($dataFileName);
my $hashRel = $obj->{string};                         # make sure this is a proper hash reference, watch out for "\"
undef $obj;

#printDumper($hashRel);exit;

# start the driver and login
# ./operadriver --url-base=/wd/hub
my $driver = Selenium::Remote::Driver->new(

 debug        => 1,
 browser_name => 'chrome',

 # extra_capabilities => {
 #  'goog:chromeOptions' => {
 #   'args'  => [ 'window-size=1260,960', 'incognito' ],
 #  }
 # }
 port => '9515'
);

$driver->maximize_window();

#sleep(0.5);

#login
&login( $driver, $configRef->{authentication}->{user}, $configRef->{authentication}->{password} );

#open release edit
#my $sel = "https://test.musicbrainz.org/release/" . $releaseId . "/edit-relationships";
my $sel = "https://musicbrainz.org/release/" . $releaseId . "/edit-relationships";

# allow js to build elements
$driver->get($sel);
sleep(WAIT_FOR_MB);
sleep(WAIT_FOR_MB);

# get main elements
my ( $element, $recording, $recordingSelector ) = "";
my @trackSelector = ();

# Note
my $crlf = chr(10).chr(13);
my $noteText = "addRelationships.pl Classical Music Uploader" .$crlf. "https://github.com/nadl40/mbnz-release";
$element = wait_until { $driver->find_element_by_class_name('editnote') };
my $note = wait_until { $driver->find_child_element( $element, './div/textarea' ) };

# checkbox to select a track
my @tracks = $driver->find_elements( "track", "class_name" );
foreach my $track (@tracks) {
 $recording = wait_until { $driver->find_child_element( $track, 'recording', "class_name" ) };
 $recordingSelector = wait_until { $driver->find_child_element( $recording, './input' ) };
 push @trackSelector, $recordingSelector;
}

# checkbox to select all recordings, for clean up
$element = wait_until { $driver->find_element_by_class_name('recordings') };
my $recordingsSelected = wait_until { $driver->find_child_element( $element, './input' ) };

# checkbox to select a work
my $batchAdd = wait_until { $driver->find_element( "batch-recording", "id" ) };

# batch push button
my @workSelector = ();
my @works        = $driver->find_elements( "relate-work", "class_name" );
foreach my $workAdd (@works) {
 push @workSelector, $workAdd;
}

# loop relationship hash

foreach my $type ( keys %{$hashRel} ) {

 #print Dumper($type);
 if ( $type ne "works" && $type ne "volumes" ) {
  &addCredits( $hashRel->{"volumes"}, $type, $driver, $hashRel->{$type}, $batchAdd, $recordingsSelected, @trackSelector );
 }
}

# loop for work
foreach my $type ( keys %{$hashRel} ) {

 if ( $type eq "works" ) {
  &addWorks( $driver, $hashRel->{$type}, @workSelector );
 }
}

# add note at the end
$note->send_keys($noteText);

# quit manually as this gives time on long or problematic releases
#sleep 300;
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

   #print( "track ", $track, " work mbid ", $works->{$track}, "\n" );
   $workSelector[ $track - 1 ]->click();
   sleep(WAIT_FOR_MB);

   wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Work");
   sleep(WAIT_FOR_MB);
   wait_until { $driver->find_element_by_class('link-type') }->send_keys("recording of");
   sleep(WAIT_FOR_MB);

   wait_until { $driver->find_element_by_class('name') }->send_keys( $works->{$track} );
   sleep(WAIT_FOR_MB);

   &clickSave( $driver, WAIT_FOR_MB_SAVE );

  }

 }

}

### add Credits ###
sub addCredits {
 my ( $volumes, $type, $driver, $artists, $batchAddButton, $recordingsSelectedCheckBox, @trackSelector ) = @_;

 my @tracks = ();

 foreach my $artistId ( keys %{$artists} ) {

  #print Dumper( $artistId );
  #print Dumper( $artists->{$artistId} );exit;
  print( "\n", $type, "->", $artistId, "->", $artists->{$artistId}->{"name"}, "\n" );

  @tracks = @{ $artists->{$artistId}->{"tracks"} };

  ### venue ###
  if ( $type eq 'venue' ) {

   #print( "venue ", $artistId, "\n" );
   &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, \@tracks );
   &addVenueRel( $driver, $artists->{$artistId} );
  }

  ### ensembles ###
  if ( $type =~ m/(ensembles|ensemble)/i ) {

   #print( "ensemble ", $artistId, "\n" );
   &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, \@tracks );
   &addEnsembleRel( $driver, $artists->{$artistId} );
  }

  ### conductor ###
  if ( $type eq 'conductor' ) {

   #print( "conductor ", $artistId, "\n" );
   &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, \@tracks );
   &addConductorRel( $driver, $artists->{$artistId} );
  }

  ### soloists ###
  if ( $type =~ m/(soloists|soloist)/i ) {

   #print( "artistId ", $artistId, "\n" );
   &prepSelection( $volumes, $batchAddButton, $recordingsSelectedCheckBox, \@trackSelector, \@tracks );
   &addArtistRel( $driver, $artists->{$artistId} );
  }

 }

}

### add venues attributes ###
sub addVenueRel {
 my ( $driver, $artist ) = @_;

 my $selected = "";

 wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Place");
 sleep(WAIT_FOR_MB);
 wait_until { $driver->find_element_by_class('link-type') }->send_keys("recorded-at");
 sleep(WAIT_FOR_MB);

 if ( $artist->{"id"} ) {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"id"} );
  sleep(WAIT_FOR_MB);
 } else {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"name"} );
  sleep(WAIT_FOR_MB);
  $driver->send_keys_to_active_element( KEYS->{'enter'} );
 }

 my $dateEntered = 0;
 if ( $artist->{"recording_date"}->{"year"} ) {
  my $element = wait_until { $driver->find_element_by_class_name('partial-date') };
  my $child   = wait_until { $driver->find_child_element( $element, './input[@placeholder="YYYY"]' ) };
  $child->send_keys( $artist->{"recording_date"}->{"year"} );
  $dateEntered = 1;
 }

 if ( $artist->{"recording_date"}->{"month"} ) {
  my $element = wait_until { $driver->find_element_by_class_name('partial-date') };
  my $child   = wait_until { $driver->find_child_element( $element, './input[@placeholder="MM"]' ) };
  $child->send_keys( $artist->{"recording_date"}->{"month"} );
 }

 if ( $artist->{"recording_date"}->{"day"} ) {
  my $element = wait_until { $driver->find_element_by_class_name('partial-date') };
  my $child   = wait_until { $driver->find_child_element( $element, './input[@placeholder="DD"]' ) };
  $child->send_keys( $artist->{"recording_date"}->{"day"} );
 }

 #now copy to end date unless we have end dates, idagio does not seems to have it
 if ( $dateEntered == 1 ) {
  my $element = wait_until { $driver->find_element_by_class_name('partial-date') };
  my $child   = wait_until { $driver->find_child_element( $element, './button[@title="Copy to end date"]' ) };
  $child->click();
 }

 &clickSave( $driver, WAIT_FOR_MB_SAVE );

}

### add ensemble attributes ###
sub addEnsembleRel {
 my ( $driver, $artist ) = @_;

 my $selected = "";

 wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Artist");
 sleep(WAIT_FOR_MB);
 wait_until { $driver->find_element_by_class('link-type') }->send_keys("orchestra");
 sleep(WAIT_FOR_MB);

 if ( $artist->{"id"} ) {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"id"} );
  sleep(WAIT_FOR_MB);
 } else {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"name"} );
  sleep(WAIT_FOR_MB);
  $driver->send_keys_to_active_element( KEYS->{'enter'} );
 }

 my $return = &addCreditedAs( $driver, $artist->{"name"} );

 &clickSave( $driver, WAIT_FOR_MB_SAVE );

}

### add conductor attributes ###
sub addConductorRel {
 my ( $driver, $artist ) = @_;

 #print Dumper($artist);

 #exit;

 my $selected = "";

 wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Artist");
 sleep(WAIT_FOR_MB);
 wait_until { $driver->find_element_by_class('link-type') }->send_keys("conductor");
 sleep(WAIT_FOR_MB);

 if ( $artist->{"id"} ) {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"id"} );
  sleep(WAIT_FOR_MB);
 } else {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"name"} );
  sleep(WAIT_FOR_MB);
  $driver->send_keys_to_active_element( KEYS->{'enter'} );
 }

 my $return = &addCreditedAs( $driver, $artist->{"name"} );

 &clickSave( $driver, WAIT_FOR_MB_SAVE );

}

### add artist attributes ###
sub addArtistRel {
 my ( $driver, $artist ) = @_;

 #print Dumper($artist);

 #exit;

 my $selected = "";

 wait_until { $driver->find_element_by_class('entity-type') }->send_keys("Artist");
 sleep(WAIT_FOR_MB);

 # try to handle vocals
 my $creditType = "";
 if ( $artist->{"instrument"}->{"keystrokes"} ) {
  $creditType = "vocal";
  wait_until { $driver->find_element_by_class('link-type') }->send_keys("vocals");
  sleep(WAIT_FOR_MB);
 } else {
  $creditType = "instrument";
  wait_until { $driver->find_element_by_class('link-type') }->send_keys("instruments");
  sleep(WAIT_FOR_MB);
 }

 if ( $artist->{"id"} ) {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"id"} );
  sleep(WAIT_FOR_MB);
 } else {
  wait_until { $driver->find_element_by_class('name') }->send_keys( $artist->{"name"} );
  sleep(WAIT_FOR_MB);
  $driver->send_keys_to_active_element( KEYS->{'enter'} );
 }

 my $return = &addCreditedAs( $driver, $artist->{"name"} );

 if ( $creditType eq "instrument" ) {
  my $element = wait_until { $driver->find_element_by_class('instrument-selection-credit') };
  my $child   = wait_until { $driver->find_child_element( $element, './span[@class="autocomplete"]' ) };
  my $child1  = wait_until { $driver->find_child_element( $child,   './input[@class="ui-autocomplete-input"]' ) };

  if ( $artist->{"instrument"}->{"id"} ) {
   wait_until { $child1->send_keys( $artist->{"instrument"}->{"id"} ) };
   sleep(WAIT_FOR_MB);
  } else {
   wait_until { $child1->send_keys( $artist->{"instrument"}->{"name"} ) };
   sleep(WAIT_FOR_MB);
   sleep(WAIT_FOR_MB);
   $driver->send_keys_to_active_element( KEYS->{'enter'} );
  }
 }

 # vocal
 if ( $creditType eq "vocal" ) {

  if ( $artist->{"instrument"}->{"keystrokes"} ) {

   my $element = wait_until { $driver->find_element_by_class('multiselect-input') };

   #wait_until { $element->send_keys( lc($recording->{$artistId}->{"instrument"} . " vocals" )) };
   wait_until { $element->send_keys(" ") };
   sleep(WAIT_FOR_MB);
   sleep(WAIT_FOR_MB);
   my $j = $artist->{"instrument"}->{"keystrokes"};
   for ( my $i = 0; $i <= $j; $i++ ) {
    $driver->send_keys_to_active_element( KEYS->{'down_arrow'} );

    #sleep(1);
   }

   $driver->send_keys_to_active_element( KEYS->{'enter'} );

   #sleep(10);

  } else {

   # exit to alert that vocal keystrokes are missing, helps to build the list
   print( "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",      "\n" );
   print( "there are no selection keystrokes for ", $artist->{"instrument"}->{"name"}, " exit.", "\n" );
   print( "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",      "\n" );
   exit(0);
  }    # keystrokes

 }    # end of vocal

 &clickSave( $driver, WAIT_FOR_MB_SAVE );

}

### add credit as, if the same as one from mbid, it's ignored
sub addCreditedAs {
 my ( $driver, $name ) = @_;

 #print Dumper($name);

 my @elements = $driver->find_elements('//div/label');
 foreach my $label (@elements) {

  #my $string=$label->get_text();
  #print ("label text>",$string,"<\n");
  if ( $label->get_text() =~ m/Credited as\:/ ) {

   #	print ("\nfound it\n");
   wait_until { $label->send_keys($name) };
   sleep(WAIT_FOR_MB);
   return "0";    # to exit the loop
  }
 }

 return "1";

}

### select all releavant tracks
sub prepSelection {
 my ( $volumes, $batchAddButton, $recordingsSelectedCheckBox, $trackSelectorRef, $tracksRef ) = @_;

 print Dumper(@tracks);

 my @tracks        = @{$tracksRef};
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
 #print ("select Add button","\n");
 $batchAddButton->click();
 sleep(WAIT_FOR_MB);

}

# offset tracks by volume if any
sub offsetTracks {
 my ( $track, $volumes ) = @_;

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
