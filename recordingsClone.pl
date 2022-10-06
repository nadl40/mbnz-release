#!/usr/bin/env perl
#*******************************************************************************
#
# Purpose:	clone recordings on a Recording tab from source to release to target release
#           this is usefull when new release is a compilation of older recordings
#           requires webdriver.
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
use Text::CSV::Hashify;

use strict;
use warnings;

#for my modules start
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname( dirname abs_path $0) . '/mbnz/lib';
use Rels::Utils qw(clean delExtension dumpToFile  readConfig );

$| = 1;

use constant WAIT_FOR_MB => '1.5';

#how many iterations of above when saving to db
use constant WAIT_FOR_MB_SAVE => '1';

# get user id and pass
#define conf path
my $confPath  = ${HOME} . "/.config/mbnz";
my $confFile  = "mbnz.conf";
my $configRef = &readConfig( $confPath, $confFile );    #read config file

# get base url
our $urlBase = "https://musicbrainz.org";
if ( $configRef->{"local"}->{"local_url"} ) {
 $urlBase = $configRef->{"local"}->{"local_url"};
}
print( "url base ", $urlBase, "\n" );

# get sleep time if local not set
our $sleepTime = $configRef->{"local"}->{"sleep_time_seconds"};
if ( $configRef->{"local"}->{"local_url"} ) {
 $sleepTime = 0;
}

#print Dumper($configRef);exit(0);

# get command line arguments
my ($dataFileName) = "";
GetOptions(
 "clone:s" => \$dataFileName,

);

if ( !$dataFileName ) {
 print( "please provide recordings clone specs  --clone", "\n" );
 exit;
}

if ( -e $dataFileName ) {
} else {
 print( "data file does not exist ", $dataFileName, "\n" );
 exit;
}

# read in csv into a hash
# as aoh which allows for a multiple rows per target release
my $obj = Text::CSV::Hashify->new(
 {
  file     => $dataFileName,
  format   => 'aoh',
  sep_char => ":",
 }
);

# remove cmd and xml files
&delExtension("xml");
&delExtension("cmd");

# reformat into a hash with a primary key and multiple requests
# error out on more than 1 primary key
my ( $cloneRequest, $targetRelease ) = &getRequests($obj);

#print Dumper($cloneRequest);
#print Dumper($targetRelease);
#exit(0);

# expand the request by adding source recordings mbid
my $sourceXML = {};
my ( $counterSource, $counterTarget, $counterTargetTrack ) = 0;

$cloneRequest = &addMbid($cloneRequest);

print Dumper($cloneRequest);

#exit(0);

# start the driver and login
# ./operadriver --url-base=/wd/hub
my $driver = Selenium::Remote::Driver->new(

 #debug        => 1,
 browser_name => 'chrome',

 port => '9515'
);

$driver->maximize_window();

#login
&login( $driver, $configRef->{authentication}->{user}, $configRef->{authentication}->{password} );

#open release edit
my $recordings = "https://musicbrainz.org/release/" . $targetRelease . "/edit#recordings";

# allow js to build elements
$driver->get($recordings);
sleep(WAIT_FOR_MB);

# get all Volume Edit buttons
my $volumeCounter  = 0;
my $volumeSelector = {};
my @volumes        = $driver->find_elements( "edit-recording", "class_name" );
foreach my $volume (@volumes) {

 my $buttons = wait_until { $driver->find_child_element( $volume,  'buttons', "class_name" ) };
 my $edit    = wait_until { $driver->find_child_element( $buttons, './button' ) };

 $volumeCounter++;

 my $volumeRequest = &volumeRequested( $volumeCounter, $cloneRequest );

 if ($volumeRequest) {
  $edit->click();

  # it takes a while to load to expand Media
  sleep( WAIT_FOR_MB * 2 );
 }
}

# find all expanded recordings
my $recordingCounter = 0;
my ( $targetOffset, $sourceOffset ) = 0;
my $found = "";

my @recordings = $driver->find_elements( "edit-track-recording", "class_name" );
foreach my $recording (@recordings) {
 $recordingCounter++;
 $targetOffset = 0;
 $found        = "";

 print( "\nrecordingCounter ", $recordingCounter, "\n" );

 # testing
 if ( $recordingCounter > 0 ) {

  # loop thru sorted requests and tracks
  foreach my $targetRelease ( keys %{$cloneRequest} ) {

   foreach my $volume ( sort { $a cmp $b } keys %{ $cloneRequest->{$targetRelease}->{"volume"} } ) {

    print( "\tvolume ", $volume, "\n" );

    my $requestCount = $targetOffset;

     foreach my $track ( sort { $a cmp $b } keys %{ $cloneRequest->{$targetRelease}->{"volume"}->{$volume}->{"allTracks"} } ) {

      my $mbid = $cloneRequest->{$targetRelease}->{"volume"}->{$volume}->{"allTracks"}->{$track};

      $requestCount++;

      if ( $requestCount == $recordingCounter && $mbid ) {
       print( "\t\t\ttrack match ", $track, ":", $mbid, "\n" );

       $recording->click();
       sleep( WAIT_FOR_MB / 2 );

       # pop up search
       my $mbidInput = $driver->get_active_element();
       $mbidInput->send_keys($mbid);
       sleep(WAIT_FOR_MB);

       # done button )
       my $done = "";
       wait_until { $done = $driver->find_element_by_xpath('//button[normalize-space()="Done"]') }->click();
       sleep( WAIT_FOR_MB / 2 );

      }

     }    # all tracks sorted


    $targetOffset = $targetOffset + $cloneRequest->{$targetRelease}->{"volume"}->{$volume}->{"noOfTracks"};

   }    # volume

  }    # target release

 }    #testing

}    # recordings on page

# wait for review and manual note add
sleep(3000);


#************************************************
#
# Subs
#
#************************************************

# check if this media volume was requested
sub volumeRequested {
 my ( $volume, $cloneRequest ) = @_;

 my $request = "";

 foreach my $targetRelease ( keys %{$cloneRequest} ) {

  foreach my $volumeReq ( keys %{ $cloneRequest->{$targetRelease}->{"volume"} } ) {

   # $volume is an integer
   if ( $volumeReq && int($volumeReq) == $volume ) {
    $request = "y";
   }

   # if not defined, always click
   if ( !$volumeReq ) {
    $request = "y";
   }

  }    # request
 }    # release

 return $request;

}

# add mbid to source tracks
# add number of tracks to target volume
sub addMbid {
 my ($request) = @_;

 my ( $trackNos, $sourceRelease, $sourceTracks, $targetTracks, $sourceVolume ) = "";

 foreach my $target ( keys %{$request} ) {

  foreach my $volume ( keys %{ $request->{$target}->{"volume"} } ) {

   # expand tracks for a volume
   $request->{$target}->{"volume"}->{$volume}->{"allTracks"} = &addTargetTracks( $target, $volume );
   $request->{$target}->{"volume"}->{$volume}->{"noOfTracks"} = &getTargetVolumeTrackCount( $target, $volume );

   # combine multiple requests per volume into one
   foreach my $requestNo ( keys %{ $request->{$target}->{"volume"}->{$volume}->{"request"} } ) {

    # expand requested target tracks
    $targetTracks = $request->{$target}->{"volume"}->{$volume}->{"request"}->{$requestNo}->{"target"}->{"tracks"};

    # if not defined
    if ( !$targetTracks ) {
     $targetTracks = &serializeRange( $request->{$target}->{"volume"}->{$volume}->{"noOfTracks"} );
    }

    # if it contains a range
    if ( $targetTracks =~ m/-/i ) {
     $targetTracks = &expandRange($targetTracks);
    }

    $request->{$target}->{"volume"}->{$volume}->{"request"}->{$requestNo}->{"target"}->{"tracks"} = $targetTracks;

    # expand source tracks
    my $sourceTracks = $request->{$target}->{"volume"}->{$volume}->{"request"}->{$requestNo}->{"target"}->{"source"}->{"tracks"};
    if ( $sourceTracks =~ m/-/i ) {
     $sourceTracks = &expandRange($sourceTracks);
    }
    $sourceRelease = $request->{$target}->{"volume"}->{$volume}->{"request"}->{$requestNo}->{"target"}->{"source"}->{"release"};
    $sourceVolume  = $request->{$target}->{"volume"}->{$volume}->{"request"}->{$requestNo}->{"target"}->{"source"}->{"volume"};

    my @arr = &getMBRecordingsID( $sourceRelease, $sourceVolume, $sourceTracks );

    # create array from a list of target tracks as source tracks are just indexes
    my @arr1 = split( ",", $request->{$target}->{"volume"}->{$volume}->{"request"}->{$requestNo}->{"target"}->{"tracks"} );


    my $counter = 0;
    foreach my $targetTrack (@arr1) {

     if ( $arr[$counter] ) {
      my $mbid = $arr[$counter];

      # now loop thru all tracks and attach mbid
      foreach my $requestTrackNo ( keys %{ $request->{$target}->{"volume"}->{$volume}->{"allTracks"} } ) {

       if ( $requestTrackNo == $targetTrack ) {

        $request->{$target}->{"volume"}->{$volume}->{"allTracks"}->{$requestTrackNo} = $mbid;
       }

      }

     }
     $counter++;

    }

   }    # request number

  }    # volume

 }    # target

 #print Dumper($request);
 #exit(0);

 return $request;
}

# expand request by target tracks
sub addTargetTracks {
 my ( $mbid, $volume ) = @_;

 my $tracks = {};

 my ( $mbzUrl, $cmd, $xml ) = "";
 my $args       = "?inc=recordings";
 my $trackCount = 0;

 # set up the command
 # https://musicbrainz.org/ws/2/release/9840615c-86a0-495b-a717-1d605e6d7c10?inc=recordings
 $mbzUrl = $urlBase . "/ws/2/release/";
 $cmd    = "curl -s " . $mbzUrl . $mbid . $args;
 $counterTargetTrack++;
 &dumpToFile( "target-" . $counterTargetTrack . ".cmd", $cmd );    #exit(0);

 # get source recording, cache in case needed more than once
 if ( !$sourceXML->{$mbid} ) {

  #need to pause between api calls, not needed when running local instance;
  print( "looking up release: ", $mbid, "\n" );
  sleep($sleepTime);

  $xml = `$cmd`;
  $xml =~ s/xmlns/replaced/ig;
  &dumpToFile( "target-" . $counterTargetTrack . ".xml", $xml );    #exit(0);
  $sourceXML->{$mbid} = $xml;
 } else {
  $xml = $sourceXML->{$mbid};
 }

 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $medium ( $dom->findnodes('/metadata/release/medium-list/medium') ) {

  my $volumeMB = $medium->findvalue('position');

  # not defined volume means all
  if ( !$volume || $volume == $volumeMB ) {

   # we have volume, find the track count
   foreach my $trackList ( $medium->findnodes('track-list') ) {

    my $count = $trackList->getAttribute("count");
    $trackCount = $trackCount + $count;
   }    # tarck list
  }    # matching volume
 }    # mediums

 # we have track countr per volume, let's build a track hash

 for ( my $i = 1; $i <= $trackCount; $i++ ) {
  $tracks->{ sprintf( "%02d", $i ) } = "";
 }

 #print Dumper($tracks);exit(0);
 return $tracks;

}

# number to a sequence of tracks
sub serializeRange {
 my ($noOfTracks) = @_;

 my $trackList = "";

 my $counter = 0;
 for ( my $i = 0; $i < $noOfTracks; $i++ ) {
  $counter++;
  $trackList = $trackList . $counter . ",";
 }

 $trackList = substr( $trackList, 0, length($trackList) - 1 );

 #print Dumper($trackList);
 #exit(0);

 return $trackList;
}

### get mbid for source recordings
sub getTargetVolumeTrackCount {
 my ( $mbid, $volume ) = @_;

 my ( $mbzUrl, $cmd, $xml ) = "";
 my $args       = "?inc=recordings";
 my $trackCount = 0;

 # set up the command
 # https://musicbrainz.org/ws/2/release/9840615c-86a0-495b-a717-1d605e6d7c10?inc=recordings
 $mbzUrl = $urlBase . "/ws/2/release/";
 $cmd    = "curl -s " . $mbzUrl . $mbid . $args;
 $counterTarget++;
 &dumpToFile( "target-" . $counterTarget . ".cmd", $cmd );    #exit(0);

 # get source recording, cache in case needed more than once
 if ( !$sourceXML->{$mbid} ) {

  #need to pause between api calls, not needed when running local instance;
  print( "looking up release: ", $mbid, "\n" );
  sleep($sleepTime);

  $xml = `$cmd`;
  $xml =~ s/xmlns/replaced/ig;
  &dumpToFile( "target-" . $counterTarget . ".xml", $xml );    #exit(0);
  $sourceXML->{$mbid} = $xml;
 } else {
  $xml = $sourceXML->{$mbid};
 }

 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $medium ( $dom->findnodes('/metadata/release/medium-list/medium') ) {

  my $volumeMB = $medium->findvalue('position');

  # not defined volume means all
  if ( !$volume || $volume == $volumeMB ) {

   # we have volume, find the track count
   foreach my $trackList ( $medium->findnodes('track-list') ) {

    my $count = $trackList->getAttribute("count");
    $trackCount = $trackCount + $count;
   }    # tarck list
  }    # matching volume
 }    # mediums

 return $trackCount;
}

### get mbid for source recordings
sub getMBRecordingsID {
 my ( $mbid, $sourceVolume, $sourceTracks ) = @_;

 my ( $mbzUrl, $cmd, $xml ) = "";
 my $args         = "?inc=recordings";
 my @recordings   = ();
 my $trackCounter = 0;

 # track list to a hash
 my $tracks = {};
 my @arr    = split( ",", $sourceTracks );
 foreach my $track (@arr) {
  $tracks->{$track} = " ";

 }

 # set up the command
 # https://musicbrainz.org/ws/2/release/9840615c-86a0-495b-a717-1d605e6d7c10?inc=recordings
 $mbzUrl = $urlBase . "/ws/2/release/";
 $cmd    = "curl -s " . $mbzUrl . $mbid . $args;
 $counterSource++;
 &dumpToFile( "source-" . $counterSource . ".cmd", $cmd );    #exit(0);

 # get source recording, cache in case needed more than once
 if ( !$sourceXML->{$mbid} ) {

  #need to pause between api calls, not needed when running local instance;
  print( "looking up release: ", $mbid, "\n" );
  sleep($sleepTime);

  $xml = `$cmd`;
  $xml =~ s/xmlns/replaced/ig;
  &dumpToFile( "source-" . $counterSource . ".xml", $xml );    #exit(0);
  $sourceXML->{$mbid} = $xml;
 } else {
  $xml = $sourceXML->{$mbid};
 }

 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $medium ( $dom->findnodes('/metadata/release/medium-list/medium') ) {

  my $volume = $medium->findvalue('position');

  # not defined volume means all
  if ( $sourceVolume && $volume ne $sourceVolume ) {
   next;
  }

  # we have volume, let's do tracks
  foreach my $track ( $medium->findnodes('track-list/track') ) {

   # not defined track means all
   my $trackNo = $track->findvalue('position');

   if ( $sourceTracks && !$tracks->{$trackNo} ) {
    next;
   }

   # track we want, grab recording id
   foreach my $recording ( $track->findnodes('recording') ) {

    my $mbid = $recording->getAttribute("id");

    # track number is just a counter
    $trackCounter++;

    #$recordings->{ sprintf( "%02d", $trackCounter ) } = $mbid;
    push @recordings, $mbid;
   }    # recording
  }    #tracks
 }    # mediums

 #print Dumper(@recordings);exit(0);
 return @recordings;

}

### expand hyphenated range into a sequence list
sub expandRange {
 my ($range) = @_;

 # first split by coma and see if splits have ranges
 my $rangeList = "";
 my @arr       = split( ",", $range );

 foreach my $element (@arr) {

  # if a range
  if ( $element =~ m/-/i ) {

   my @arr1 = split( "-", $element );

   for ( my $i = $arr1[0]; $i <= $arr1[1]; $i++ ) {
    $rangeList = $rangeList . $i . ",";
   }

  } else {
   $rangeList = $rangeList . $element . ",";
  }

 }
 $rangeList = substr( $rangeList, 0, length($rangeList) - 1 );

 return $rangeList;

}

### format csv requests into a hash of requests ###
sub getRequests {
 my ($requests) = @_;

 #print Dumper($requests);

 my ( $counterStr, $targetRelease ) = "";
 my $hash         = {};
 my $cloneRequest = {};
 my ( $volume, $counter ) = 0;

 foreach my $request ( keys @{ $requests->{"all"} } ) {
  $hash          = $requests->{"all"}[$request];
  $targetRelease = $hash->{"target release"};

  # use targe volume as request number for later sort
  # add a counter as this will allow for multiple instances of the same target volume
  $counter++;
  if ( $hash->{"target volume"} ) {
   $volume     = sprintf( "%02d", $hash->{"target volume"} );
   $counterStr = sprintf( "%02d", $counter );
   $hash->{"target volume"} = $volume;

  } else {
   print( "your target volume is blank, 1 volume", " cloning can be handled when creating a release. ", $hash->{"target volume"}, "\n" );
   exit(0);
  }

  my $sourceRelease = $hash->{"source release"};

  $cloneRequest->{$targetRelease}->{"volume"}->{$volume}->{"request"}->{$counterStr}->{"target"}->{"tracks"}              = $hash->{"target tracks"};
  $cloneRequest->{$targetRelease}->{"volume"}->{$volume}->{"request"}->{$counterStr}->{"target"}->{"source"}->{"volume"}  = $hash->{"source volume"};
  $cloneRequest->{$targetRelease}->{"volume"}->{$volume}->{"request"}->{$counterStr}->{"target"}->{"source"}->{"tracks"}  = $hash->{"source tracks"};
  $cloneRequest->{$targetRelease}->{"volume"}->{$volume}->{"request"}->{$counterStr}->{"target"}->{"source"}->{"release"} = $hash->{"source release"};

 }

 my $targetReleaseKeys = keys %{$cloneRequest};
 if ( $targetReleaseKeys > 1 ) {
  print( "your clone request has ", $targetReleaseKeys, " release targets, only 1 is allowed.", "\n" );
  print Dumper($cloneRequest);
  exit(0);
 }

 #print Dumper($cloneRequest);exit;
 return ( $cloneRequest, $targetRelease );

}

#### log in ###
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
