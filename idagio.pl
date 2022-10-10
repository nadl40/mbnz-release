#!/usr/bin/perl
#===============================================================
#
# Purpose:	create a MBNZ submission form from Idagio
# 					At the same time create a persistent hash for relationships to be used by selenium webdriver
# 					to add artist credits and work rels
#
#===============================================================

use strict;
use warnings;

use HTTP::Request ();
use JSON::MaybeXS qw(encode_json decode_json);
use Data::Dumper::Simple;
use LWP::UserAgent;
use XML::LibXML;
use URI::Escape;
use Hash::Persistent;
use Getopt::Long;
use String::Util qw(trim);
use Text::Levenshtein qw(distance);
use Mojo::DOM;
use Env;
use Config::General;

#for my modules start
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname( dirname abs_path $0) . '/mbnz/lib';
use Rels::Utils qw(clean delExtension dumpToFile  readConfig );
use Rels::Rels qw(getTrackPositionMbid getPlaceMbid getArtistMbid getWorkMbid);

binmode( STDOUT, "encoding(UTF-8)" );

# constants
use constant SOLOISTS_THRESHOLD => .60;

# autoflush
$| = 1;

# get command line arguments
my ($idagioUrl) = "";
GetOptions( "url:s" => \$idagioUrl, );

if ( !$idagioUrl ) {
 print( "please provide url --url", "\n" );
 exit;
}

# keep track of things that are already looked up, save trips to mbnz
my $lookup = {};

# get config
my $confPath  = ${HOME} . "/.config/mbnz";
my $confFile  = "mbnz.conf";
my $configRef = &readConfig( $confPath, $confFile );    #read config file

#===============================================
# set some from config
#
#===============================================

# auto launch browser
my $launchBrowser = "";
if ( $configRef->{"options"}->{"launch_browser"} ) {
 $launchBrowser = $configRef->{"options"}->{"launch_browser"};
}

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

print Dumper ($idagioUrl);

my ( $cmd, $return ) = "";
my $artistCounter = 0;

$cmd    = 'wget ' . $idagioUrl . " -O current.html";
$return = `$cmd`;

use constant HTML_FILE => 'current.html';

open( my $fh, '<', HTML_FILE )
  or die "Could not open file 'HTML_FILE' $!";

#start the form
my $htmlForm = "";

$htmlForm = $htmlForm . '<!doctype html>' . "\n";
$htmlForm = $htmlForm . '<meta charset="UTF-8">' . "\n";
$htmlForm = $htmlForm . '<title>Add Idagio Album As Release...</title>' . "\n";

#$htmlForm = $htmlForm . '<form action="https://test.musicbrainz.org/release/add" method="post">' . "\n";
$htmlForm = $htmlForm . '<form action="https://musicbrainz.org/release/add" method="post">' . "\n";

my @arr = ();
$cmd = "";
my $dataJson = "";
my $hash     = {};

#cache xml results for main work MBid
my $counter         = 0;
my $counterPosition = 0;
my $counterAlias    = 0;

# remove cmd and xml files
&delExtension("xml");
&delExtension("cmd");

my $mainWorkXML = {};
my $xml         = "";
my $htmlPart    = "";
my %mon         = (
 "January"   => "01",
 "February"  => "02",
 "March"     => "03",
 "April"     => "04",
 "May"       => "05",
 "June"      => "06",
 "July"      => "07",
 "August"    => "08",
 "September" => "09",
 "October"   => "10",
 "November"  => "11",
 "December"  => "12"
);

my %keystrokesMap = (
 "alto"          => 2,
 "bass-baritone" => 3,
 "contralto"     => 4,
 "treble"        => 5,
 "baritone"      => 6,
 "bass"          => 7,
 "countertenor"  => 8,
 "mezzo-soprano" => 9,
 "soprano"       => 10,
 "tenor"         => 11
);

while ( my $line = <$fh> ) {
 chomp $line;

 if ( $line =~ m/window.__data__/i ) {
  my @arr  = split( " = ", $line );
  my $data = substr( $arr[1], 0, length( $arr[1] ) - 1 );

  # print to file
  #&dumpToFile( "data.json", $data );exit;

  my $idagio = JSON->new->utf8->decode($data);
  &writeHash( "release.txt", $idagio );

  $htmlPart = "";
  $htmlPart = &albumTitle( $idagio->{"entities"}->{"albums"} );
  if ($htmlPart) {
   $htmlForm = $htmlForm . $htmlPart;
  }

  $htmlPart = "";
  $htmlPart = &albumUPC( $idagio->{"entities"}->{"albums"} );
  if ($htmlPart) {
   $htmlForm = $htmlForm . $htmlPart;
  }

  $htmlForm = $htmlForm . '<input type="hidden" name="type" value="' . 'Album' . '">' . "\n";
  $htmlForm = $htmlForm . '<input type="hidden" name="status" value="' . 'Official' . '">' . "\n";
  $htmlForm = $htmlForm . '<input type="hidden" name="script" value="' . 'Latn' . '">' . "\n";

  # Label credit, use search
  $htmlPart = "";
  $htmlPart = &albumLabel( $idagio->{"entities"}->{"albums"} );
  if ($htmlPart) {
   $htmlForm = $htmlForm . $htmlPart;
  }

  # release event
  $htmlPart = "";
  $htmlPart = &albumRelease( $idagio->{"entities"}->{"albums"} );
  if ($htmlPart) {
   $htmlForm = $htmlForm . $htmlPart;
  }

  # url from argument
  $htmlPart = "";
  $htmlPart = &albumURL($idagioUrl);
  if ($htmlPart) {
   $htmlForm = $htmlForm . $htmlPart;
  }

  # release artists
  $htmlPart = "";
  my $releaseArtists = &getMainArtist( $idagio->{"entities"}->{"albums"} );
  my @releaseCredit  = &setReleaseCredits($releaseArtists);
  $htmlPart = &addRCRToForm(@releaseCredit);
  if ($htmlPart) {

   # last credit has comma as join phrase, need to replace its value=", ">
   $htmlPart = substr( $htmlPart, 0, length($htmlPart) - 5 );
   $htmlPart = $htmlPart . '">' . "\n";
   $htmlForm = $htmlForm . $htmlPart;
  }

  # let's do tracks
  $htmlPart = "";
  my ( $trackHash, $htmlPart, $trackSeq ) = &albumTracks( $idagio->{"entities"}, @releaseCredit );
  if ($htmlPart) {
   $htmlForm = $htmlForm . $htmlPart;
  }

  # edit note and redirect perhaps ?
  $htmlPart = "";
  $htmlPart = &editNote($idagioUrl);
  if ($htmlPart) {
   $htmlForm = $htmlForm . $htmlPart;
  }

  # get image urls
  my ( $bookletUrl, $imageUrl ) = &getImages( $idagio->{"entities"}->{"albums"} );

  #print("\n");
  if ($bookletUrl) {

   print( "booklet ", $bookletUrl, "\n" );
  }
  if ($imageUrl) {

   print( "cover   ", $imageUrl, "\n" );
  }

  # create a diff persistent hash for a relationship webdriver
  my $relationshipHashSerial = &getRelationshipsByTracks( $trackHash, $trackSeq, $idagio->{"entities"}, @releaseCredit );
  &writeRelationshipPersistentSerialHash( 'relationshipsSerial.txt', $relationshipHashSerial );

 }    # end of json data

}    # end of page data

$htmlForm = $htmlForm . '</form>' . "\n";
$htmlForm = $htmlForm . '<script>document.forms[0].submit()</script>' . "\n";

#print $htmlForm;
&dumpToFile( "form.html", $htmlForm );

#open in default browser
$cmd = "xdg-open form.html";

if ( $launchBrowser eq 'y' ) {
 $return = `$cmd`;
} else {
 print("not launching a browser \n");
}

############################# subs ############################################

# write a serial relationship hash in the order of tracks, in an array of hashes.
sub writeRelationshipPersistentSerialHash {
 my ( $fileName, $recordings ) = @_;

 &writeHash( $fileName, $recordings );

}

# diff order, by type, by element, track count
sub getRelationshipsByTracks {
 my ( $trackHash, $trackSeq, $idagio, @releaseCredit ) = @_;

 my $hash        = {};
 my $recordings  = &loadRecordings($idagio);
 my $persons     = &loadPersons( $idagio, @releaseCredit );
 my $ensembles   = &loadEnsembles( $idagio, @releaseCredit );
 my $instruments = &loadInstruments($idagio);

 my $places = {};
 my ( $recording, $personId, $instrumentId, $year, $month, $day ) = "";
 my @arr = ();

 #get the tracks
 foreach my $entity ( keys %{$idagio} ) {
  if ( $entity eq "tracks" ) {
   foreach my $track ( keys %{ $idagio->{$entity} } ) {

    $recording = $idagio->{$entity}->{$track}->{"recording"};

    # get recording date as it belongs to venue IMHO
    ( $month, $year, $day ) = "";
    foreach my $entity ( keys %{ $recordings->{$recording} } ) {

     if ( $entity eq "recordingDate" ) {

      $year  = $recordings->{$recording}->{$entity}->{"from"};
      $month = $recordings->{$recording}->{$entity}->{"fromKeyword"};

      if ($month) {
       $month = $mon{$month};
      }

     }
    }    # end of recording date lookup for a track

    ##### loop again, skip recording date
    foreach my $entity ( keys %{ $recordings->{$recording} } ) {

     ### venue ###
     if ( $entity eq "venue" ) {

      my $venueId   = $recordings->{$recording}->{$entity}->{"id"};
      my $venueName = $recordings->{$recording}->{$entity}->{"name"};
      if ( $recordings->{$recording}->{$entity}->{"location"}->{"name"} ) {
       $venueName = $venueName . " " . $recordings->{$recording}->{$entity}->{"location"}->{"name"};
      }
      my $track = $trackSeq->{$track};

      if ($venueId) {
       $hash->{$entity}->{$venueId}->{"name"} = $venueName;
       push @{ $hash->{$entity}->{$venueId}->{"venue"}->{"venue"}->{"tracks"} }, $track;

       my $placeName = $hash->{$entity}->{$venueId}->{"name"};

       # build lookup whith each new value
       if ( !$places->{$placeName} ) {
        $hash->{$entity}->{$venueId}->{"id"} = &getPlaceMbid($placeName);
        $places->{$placeName} = $hash->{$entity}->{$venueId}->{"id"};
       } else {
        $hash->{$entity}->{$venueId}->{"id"} = $places->{$placeName};
       }
      }

      # add recording date
      if ($venueId) {
       $hash->{$entity}->{$venueId}->{"recording_date"}->{"year"}  = $year;
       $hash->{$entity}->{$venueId}->{"recording_date"}->{"month"} = $month;
       $hash->{$entity}->{$venueId}->{"recording_date"}->{"day"}   = $day;
      }

     }    # end of venue

     ### conductor ###
     if ( $entity eq "conductor" ) {

      my $personId = $recordings->{$recording}->{$entity};
      my $track    = $trackSeq->{$track};
      if ($personId) {
       $hash->{$entity}->{$personId}->{"name"} = $persons->{$personId}->{"name"};
       $hash->{$entity}->{$personId}->{"id"}   = $persons->{$personId}->{"id"};
       push @{ $hash->{$entity}->{$personId}->{"venue"}->{"n/a"}->{"tracks"} }, $track;

      }

     }

     ### ensembles ###
     # choirs should go to artists as their instrument is choir vocals
     if ( $entity eq "ensembles" ) {
      @arr = @{ $recordings->{$recording}->{$entity} };

      foreach my $ensembleId (@arr) {

       my $personId = $ensembleId;
       my $track    = $trackSeq->{$track};

       if ( $ensembles->{$ensembleId}->{"chorus"} ) {

        $hash->{"soloists"}->{$personId}->{"name"} = $ensembles->{$ensembleId}->{"name"};
        $hash->{"soloists"}->{$personId}->{"id"}   = $ensembles->{$ensembleId}->{"id"};

        my $instrument = $ensembles->{$ensembleId}->{"chorus"};
        $hash->{"soloists"}->{$personId}->{"instrument"}->{$instrument}->{"name"}         = $ensembles->{$ensembleId}->{"chorus"};
        $hash->{"soloists"}->{$personId}->{"instrument"}->{$instrument}->{"keystrokes"}   = $ensembles->{$ensembleId}->{"keystrokes"};
        $hash->{"soloists"}->{$personId}->{"instrument"}->{$instrument}->{"instrumentId"} = '';

        push @{ $hash->{"soloists"}->{$personId}->{"instrument"}->{"n/a"}->{"tracks"} }, $track;

       } else {

        my $instrument = $ensembles->{$ensembleId}->{"chorus"};
        $hash->{$entity}->{$ensembleId}->{"name"} = $ensembles->{$ensembleId}->{"name"};
        $hash->{$entity}->{$ensembleId}->{"id"}   = $ensembles->{$ensembleId}->{"id"};
        push @{ $hash->{$entity}->{$personId}->{"instrument"}->{"n/a"}->{"tracks"} }, $track;
       }
      }

     }

     ### soloists ###
     if ( $entity eq "soloists" ) {

      @arr = @{ $recordings->{$recording}->{$entity} };

      foreach my $performerId (@arr) {

       my $personId = $performerId->{"person"};

       my $instrumentId = $performerId->{"instrument"};
       my $track        = $trackSeq->{$track};

       $hash->{$entity}->{$personId}->{"name"} = $persons->{$personId}->{"name"};
       $hash->{$entity}->{$personId}->{"id"}   = $persons->{$personId}->{"id"};

       my $instrument = $instruments->{$instrumentId}->{"name"};
       $hash->{$entity}->{$personId}->{"instrument"}->{$instrument}->{"id"}         = $instruments->{$instrumentId}->{"id"};
       $hash->{$entity}->{$personId}->{"instrument"}->{$instrument}->{"name"}       = $instruments->{$instrumentId}->{"name"};
       $hash->{$entity}->{$personId}->{"instrument"}->{$instrument}->{"keystrokes"} = $instruments->{$instrumentId}->{"keystrokes"};

       push @{ $hash->{$entity}->{$personId}->{"instrument"}->{$instrument}->{"tracks"} }, $track;

      }
     }
    }
   }
  }
 }

 #now lets add work mbid by tracks
 foreach my $track ( keys %{$trackHash} ) {
  $hash->{"works"}->{$track} = $trackHash->{$track}->{"work_mbid"};
 }

 # loop over the hash and print the ones without an mbid, don't create a release till all found ?
 my $exit = "";
 print "\n";
 foreach my $type ( keys %{$hash} ) {
  if ( $type ne "works" ) {
   foreach my $artist ( keys %{ $hash->{$type} } ) {
    if ( !$hash->{$type}->{$artist}->{"id"} ) {
     print( "missing mbid for ", $hash->{$type}->{$artist}->{"name"}, "\n" );

    }
   }
  }
 }

 if ($exit) {
  print("please add missing artists to MB and rerun the script \n");

 }

 return $hash;
}

# little late, but loop and match on name to find mbid
sub matchMbidPersons {
 my ( $name, @releaseCredit ) = @_;

 my ( $mbid, $joinphrase ) = "";
 my $artist = {};
 foreach my $credit (@releaseCredit) {

  foreach my $type ( keys %{$credit} ) {
   if ( $credit->{$type}->{"credited"} eq $name ) {
    $mbid       = $credit->{$type}->{"artistId"};
    $joinphrase = $credit->{$type}->{"joinPhrase"};
    return ( $mbid, $joinphrase );
   }
  }
 }

 return ( "", "" );
}

#load ensembles
sub loadEnsembles {
 my ( $idagio, @releaseCredit ) = @_;

 my ( $artistName, $mbid ) = "";
 my $chorus     = "";
 my $keystrokes = "";
 my $joinphrase = "";

 my $hash = {};
 foreach my $entity ( keys %{$idagio} ) {
  if ( $entity eq "ensembles" ) {
   foreach my $ensemble ( keys %{ $idagio->{$entity} } ) {

    undef $chorus;
    undef $keystrokes;

    # change if it does not match mb
    $hash->{$ensemble}->{"name"} = $idagio->{$entity}->{$ensemble}->{"name"};

    if ( $idagio->{$entity}->{$ensemble}->{"name"} =~ m/choir|chorus/i ) {
     $chorus     = "chorus";
     $keystrokes = "13";
    }

    ( $mbid, $joinphrase ) = &matchMbidPersons( $idagio->{$entity}->{$ensemble}->{"name"}, @releaseCredit );
    if ($mbid) {
     $hash->{$ensemble}->{"id"} = $mbid;
    } else {

     if ( !$joinphrase ) {
      print( "looking up: ", $idagio->{$entity}->{$ensemble}->{"name"}, "\n" );
      ( $mbid, $artistName ) = &getArtistMbid( $idagio->{$entity}->{$ensemble}->{"name"} );
     }

     if ($mbid) {
      $hash->{$ensemble}->{"id"} = $mbid;
     }
    }    #end of mbid

    # always add chorus indicator
    $hash->{$ensemble}->{"chorus"}     = $chorus;
    $hash->{$ensemble}->{"keystrokes"} = $keystrokes;

   }
  }
 }

 return $hash;

}

#load Instruments
sub loadInstruments {
 my ($idagio) = @_;

 my ( $searchUrl, $url02, $instrumentName, $mbid ) = "";

 my $keystrokes = "";
 my $voice      = "";

 my $hash = {};
 foreach my $entity ( keys %{$idagio} ) {
  if ( $entity eq "instruments" ) {
   foreach my $instrument ( keys %{ $idagio->{$entity} } ) {

    $keystrokes = "";
    $voice      = "";

    # change if it does not match mb
    $hash->{$instrument}->{"name"} = lc( $idagio->{$entity}->{$instrument}->{"title"} );

    if ( $idagio->{$entity}->{$instrument}->{"title"} =~ m/soprano|tenor|bass|baritone/i ) {

     $voice = $idagio->{$entity}->{$instrument}->{"title"};
     print( "looking up ", $idagio->{$entity}->{$instrument}->{"title"}, " skipped \n" );

     $keystrokes = $keystrokesMap{ lc($voice) };
     if ( !$keystrokes ) {
      print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
      print( "voice keystrokes not found ", $voice, " exit.", "\n" );
      print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
      exit(0);
     }

     print Dumper($voice);
     print Dumper($keystrokes);

     $hash->{$instrument}->{"id"}         = "";
     $hash->{$instrument}->{"keystrokes"} = $keystrokes;

    } else {

     ( $mbid, $instrumentName ) = &getInstrumentMbid( lc( $idagio->{$entity}->{$instrument}->{"title"} ) );

     if ($mbid) {
      $hash->{$instrument}->{"id"}         = $mbid;
      $hash->{$instrument}->{"name"}       = $instrumentName;
      $hash->{$instrument}->{"keystrokes"} = $keystrokes;
     }
    }

   }
  }
 }

 return $hash;

}

# load persons
sub loadPersons {
 my ( $idagio, @releaseCredit ) = @_;

 my ( $artistName, $mbid ) = "";
 my $joinphrase = "";

 # @arrCredits constains mbid for conductors, soloists and ensembles that are credited on the Release
 # for the ones that are not, need to do a mb search

 my $hash = {};
 foreach my $entity ( keys %{$idagio} ) {
  if ( $entity eq "persons" ) {
   foreach my $person ( keys %{ $idagio->{$entity} } ) {

    $hash->{$person}->{"name"} = $idagio->{$entity}->{$person}->{"name"};

    ( $mbid, $joinphrase ) = &matchMbidPersons( $idagio->{$entity}->{$person}->{"name"}, @releaseCredit );
    if ($mbid) {
     $hash->{$person}->{"id"} = $mbid;
    } else {

     if ( !$joinphrase ) {
      ( $mbid, $artistName ) = &getArtistMbid( $idagio->{$entity}->{$person}->{"name"} );
     }

     if ($mbid) {
      $hash->{$person}->{"id"} = $mbid;
     }
    }    #end of mbid

   }
  }
 }

 return $hash;
}

# load recordins
sub loadRecordings {
 my ($idagio) = @_;

 my $hash = {};
 foreach my $entity ( keys %{$idagio} ) {
  if ( $entity eq "recordings" ) {
   foreach my $recording ( keys %{ $idagio->{$entity} } ) {

    $hash->{$recording}->{"conductor"}     = $idagio->{$entity}->{$recording}->{"conductor"};
    $hash->{$recording}->{"ensembles"}     = $idagio->{$entity}->{$recording}->{"ensembles"};
    $hash->{$recording}->{"recordingDate"} = $idagio->{$entity}->{$recording}->{"recordingDate"};
    $hash->{$recording}->{"recordingDate"} = $idagio->{$entity}->{$recording}->{"recordingDate"};
    $hash->{$recording}->{"soloists"}      = $idagio->{$entity}->{$recording}->{"soloists"};
    $hash->{$recording}->{"venue"}         = $idagio->{$entity}->{$recording}->{"venue"};

   }
  }
 }

 return $hash;
}

# get cover url and print to stdout
sub getImages {
 my ($idagio) = @_;

 my ( $bookletUrl, $imageUrl ) = "";

 foreach my $id ( keys %{$idagio} ) {
  foreach my $type ( keys %{ $idagio->{$id} } ) {

   if ( $type eq "bookletUrl" ) {
    if ( $idagio->{$id}->{"bookletUrl"} ) {
     $bookletUrl = $idagio->{$id}->{"bookletUrl"};
    }
   }

   if ( $type eq "imageUrl" ) {
    if ( $idagio->{$id}->{"imageUrl"} ) {
     $imageUrl = $idagio->{$id}->{"imageUrl"};
    }
   }

  }
 }

 return ( $bookletUrl, $imageUrl );
}

# main driver to return track data
sub albumTracks {
 my ( $idagio, @releaseCredit ) = @_;

 # print to a file
 my $debug = Dumper($idagio);
 &dumpToFile( "idagio.txt", $debug );    #exit(0);

 my $pieceData     = &loadPieces($idagio);       #print Dumper($pieceData);
 my $workPartsData = &loadWorkParts($idagio);    #print Dumper($workPartsData);
 my $workData      = &loadWork($idagio);         #print Dumper($workData);exit;
 my $composers     = &loadComposers($idagio);
 my $tracks        = &loadTracks($idagio);
 my $trackNo       = 0;

 # add mbid to $workData
 foreach my $workId ( keys %{$workData} ) {

  my $composerId = $workData->{$workId}->{"composer"};

  # get composer name
  my $composerName = $composers->{$composerId};

  # need mbnz id for composers
  my $mbId = &getMbid( "composer", $composerName, @releaseCredit );

  $workData->{$workId}->{"mbid"} = &getWorkMbid( $mbId, &clean( $workData->{$workId}->{"title"} ) );

 }

 my $trackHash = {};
 foreach my $type ( keys %{$idagio} ) {

  if ( $type eq "tracks" ) {

   #print Dumper($idagio->{$type});exit(0);

   my $positionCalc = 0;
   foreach my $track ( sort { $a cmp $b } keys %{ $idagio->{$type} } ) {

    # get track id
    my $trackId  = $idagio->{$type}->{$track}->{"id"};
    my $duration = $idagio->{$type}->{$track}->{"duration"} * 1000;
    my $piece    = $idagio->{$type}->{$track}->{"piece"};

    # assign own position as idagio skips
    if ( $idagio->{$type}->{$track}->{"position"} == 1 ) {
     $positionCalc = 1;
    } else {
     $positionCalc++;
    }
    my $position = $positionCalc;

    # work or movement title contains position
    my $title1 = &clean( $pieceData->{$piece}->{"title"} );
    my @arr    = split( " ", $title1 );
    shift @arr;
    $title1 = join( " ", @arr );

    # how you get data from piece up
    # 1. pieces=>{"workpart"}
    # 2. workpart=>{"work"}
    # 3. work
    my $workPart = $pieceData->{$piece}->{"workpart"};

    # workpart gives me work
    my $workId   = $workPartsData->{$workPart}->{"work"};
    my $workMbid = $workData->{$workId}->{"mbid"};

    my $title2 = &clean( $workPartsData->{$workPart}->{"title"} );

    # work give me title and composer id
    my $title3 = &clean( $workData->{$workId}->{"title"} );    #exit;

    my $composerId = $workData->{$workId}->{"composer"};

    # now get composer name
    my $composerName = $composers->{$composerId};

    # need mbnz id for composers
    my $composerMbid = &getMbid( "composer", $composerName, @releaseCredit );

    # track number
    my $trackNo = sprintf( "%02d", $tracks->{$trackId} );

    $trackHash->{$trackNo}->{"duration"} = $duration;

    # single movements have the title twice
    # sometimes $title1 and $title2 are main titles but diff spelling... no can do
    #print( $title3, "--->", $title2, "--->", $title1, "\n" );

    if ( $title3 eq $title1 and !$title2 ) {
     $trackHash->{$trackNo}->{"title"} = $title3;
    }

    if ( $title3 eq $title1 and $title2 ) {
     $trackHash->{$trackNo}->{"title"} = $title3 . ", " . $title2;
    }

    if ( $title3 ne $title1 and !$title2 ) {
     $trackHash->{$trackNo}->{"title"} = $title3 . ": " . $title1;
    }

    if ( $title3 ne $title1 and $title2 ) {
     $trackHash->{$trackNo}->{"title"} = $title3 . ", " . $title2 . ": " . $title1;
    }

    # get MB workid, use a composer mbid, perhaps only part of catalogue
    # $workMbid contains main work id
    # $position contains position within work
    if ( $workMbid && $position ) {
     ( $trackHash->{$trackNo}->{"work_mbid"}, $trackHash->{$trackNo}->{"mbTitle"} ) =
       &getTrackPositionMbid( $workMbid, $position, $trackHash->{$trackNo}->{"title"}, $composerMbid );
    } else {
     ( $trackHash->{$trackNo}->{"work_mbid"}, $trackHash->{$trackNo}->{"mbTitle"} ) =
       &getWorkAliasesMbid( $composerMbid, $trackHash->{$trackNo}->{"title"} );
    }
    $trackHash->{$trackNo}->{"composer"} = $composerName;
    $trackHash->{$trackNo}->{"mbid"}     = $composerMbid;

   }
  }
 }

 my $htmlForm = &formatTracksForm($trackHash);

 return ( $trackHash, $htmlForm, $tracks );

}

# format html for tracks
sub formatTracksForm {
 my ($trackHash) = @_;

 my $htmlForm = '<input type="hidden" name="mediums.0.format" value="Digital Media">' . "\n";

 my $mediaCount = 0;
 my $trackCount = 0;

 # sort and print
 my $list = "";
 foreach my $track ( sort { $a cmp $b } keys %{$trackHash} ) {

  $htmlForm =
      $htmlForm
    . '<input type="hidden" name="mediums.'
    . $mediaCount
    . '.track.'
    . $trackCount
    . '.name" value="'
    . $trackHash->{$track}->{"title"} . '">' . "\n";
  $htmlForm =
      $htmlForm
    . '<input type="hidden" name="mediums.'
    . $mediaCount
    . '.track.'
    . $trackCount
    . '.artist_credit.names.0.name" value="'
    . $trackHash->{$track}->{"composer"} . '">' . "\n";
  $htmlForm =
      $htmlForm
    . '<input type="hidden" name="mediums.'
    . $mediaCount
    . '.track.'
    . $trackCount
    . '.artist_credit.names.0.mbid" value="'
    . $trackHash->{$track}->{"mbid"} . '">' . "\n";
  $htmlForm =
      $htmlForm
    . '<input type="hidden" name="mediums.'
    . $mediaCount
    . '.track.'
    . $trackCount
    . '.length" value="'
    . $trackHash->{$track}->{"duration"} . '">' . "\n";
  $trackCount++;

  $list = $list . $trackHash->{$track}->{"title"} . "\n";

 }

 &dumpToFile( "track list.txt", $list );
 return $htmlForm;
}

# load tracks for track sequence
sub loadTracks {
 my ($idagio) = @_;

 my $i      = 0;
 my $tracks = {};
 foreach my $id ( keys %{ $idagio->{"albums"} } ) {

  foreach my $type ( keys %{ $idagio->{"albums"}->{$id} } ) {

   if ( $type eq "tracks" ) {

    my @arr = @{ $idagio->{"albums"}->{$id}->{$type} };

    foreach my $track (@arr) {
     $i++;
     $tracks->{$track} = $i;
    }
   }

  }

 }

 return $tracks;
}

# load composers
sub loadComposers {
 my ($idagio) = @_;

 my $composers = {};
 foreach my $id ( keys %{ $idagio->{"albums"} } ) {

  foreach my $type ( keys %{ $idagio->{"albums"}->{$id} } ) {

   if ( $type eq "participants" ) {

    my @arr = @{ $idagio->{"albums"}->{$id}->{$type} };

    foreach my $artist (@arr) {
     my $type = $artist->{"type"};
     if ( $type eq 'composer' ) {
      my $id   = $artist->{"id"};
      my $name = $artist->{"name"};
      $composers->{$id} = $name;
     }
    }

   }
  }
 }
 return $composers;
}

#load works
sub loadWork {
 my ($idagio) = @_;

 my $workData = {};
 foreach my $type ( keys %{$idagio} ) {

  if ( $type eq "works" ) {

   foreach my $pieceId ( keys %{ $idagio->{$type} } ) {

    my $title    = $idagio->{$type}->{$pieceId}->{"title"};
    my $composer = $idagio->{$type}->{$pieceId}->{"composer"};

    $workData->{$pieceId}->{"title"}    = $title;
    $workData->{$pieceId}->{"composer"} = $composer;

   }
  }
 }
 return $workData;
}

# load work parts
sub loadWorkParts {
 my ($idagio) = @_;

 my $workPartsData = {};
 foreach my $type ( keys %{$idagio} ) {

  if ( $type eq "workparts" ) {

   foreach my $pieceId ( keys %{ $idagio->{$type} } ) {

    my $work  = $idagio->{$type}->{$pieceId}->{"work"};
    my $title = $idagio->{$type}->{$pieceId}->{"title"};

    $workPartsData->{$pieceId}->{"work"}  = $work;
    $workPartsData->{$pieceId}->{"title"} = $title;

   }
  }
 }

 return $workPartsData;
}

# load pieces
sub loadPieces {
 my ($idagio) = @_;

 my $pieceData = {};
 foreach my $type ( keys %{$idagio} ) {

  if ( $type eq "pieces" ) {

   foreach my $pieceId ( keys %{ $idagio->{$type} } ) {

    my $title    = $idagio->{$type}->{$pieceId}->{"title"};
    my $workPart = $idagio->{$type}->{$pieceId}->{"workpart"};

    $pieceData->{$pieceId}->{"title"}    = $title;
    $pieceData->{$pieceId}->{"workpart"} = $workPart;

   }
  }
 }

 return $pieceData;
}

# get MB Id from release credits
sub getMbid {
 my ( $type, $aristCreditName, @releaseCredit ) = @_;

 my $Mbid = "";
 foreach my $credit (@releaseCredit) {

  foreach my $crediType ( keys %{$credit} ) {

   if ( $crediType eq $type ) {

    if ( $credit->{$crediType}->{"credited"} eq $aristCreditName ) {

     $Mbid = $credit->{$crediType}->{"artistId"};
    }

   }

  }

 }

 return $Mbid;
}

# info stored in a piece
sub getPieceData {
 my ( $piece, $idagio ) = @_;

 my ( $title, $workPart ) = "";

 foreach my $type ( keys %{$idagio} ) {

  if ( $type eq "pieces" ) {

   foreach my $pieceId ( keys %{ $idagio->{$type} } ) {

    if ( $pieceId eq $piece ) {

     # get piece id's
     $title    = $idagio->{$type}->{$pieceId}->{"title"};
     $workPart = $idagio->{$type}->{$pieceId}->{"workpart"};
     last;

    }

   }

  }

 }

 return ( $title, $workPart );

}

# do edit note plus maybe redirect
sub editNote {
 my ($albumUrl) = @_;

 my $crlf     = chr(10) . chr(13);
 my $editNote = $albumUrl . $crlf . "idagio.pl Classical Music Uploader" . $crlf . "https://github.com/nadl40/mbnz-release";

 $htmlPart = '<input type="hidden" name="edit_note" value="' . "from " . $editNote . '">' . "\n";

 return $htmlPart;

}

sub albumURL {
 my ($albumUrl) = @_;

 if ($albumUrl) {

  $htmlPart = '<input type="hidden" name="urls.0.url" value="' . $albumUrl . '">' . "\n";
  $htmlPart = $htmlPart . '<input type="hidden" name="urls.0.link_type" value="' . '980' . '">' . "\n";

 }

 return $htmlPart;

}

sub albumRelease {
 my ($idagio) = @_;

 my ( $albumRelease, $htmlPart ) = "";

 foreach my $id ( keys %{$idagio} ) {
  $albumRelease = $idagio->{$id}->{"publishDate"};
 }

 if ($albumRelease) {

  my @arr = split( "-", $albumRelease );

  $htmlPart = '<input type="hidden" name="events.0.date.year" value="' . $arr[0] . '">' . "\n";
  $htmlPart = $htmlPart . '<input type="hidden" name="events.0.date.month" value="' . $arr[1] . '">' . "\n";
  $htmlPart = $htmlPart . '<input type="hidden" name="events.0.date.day" value="' . $arr[2] . '">' . "\n";

 }

 return $htmlPart;

}

sub albumUPC {
 my ($idagio) = @_;

 my ( $albumUPC, $htmlPart ) = "";

 foreach my $id ( keys %{$idagio} ) {
  $albumUPC = $idagio->{$id}->{"upc"};

 }

 # album title
 #<input type="hidden" name="barcode" value="00028944555127">
 if ($albumUPC) {
  $htmlPart = '<input type="hidden" name="barcode" value="' . $albumUPC . '">' . "\n";

 }

 return $htmlPart;
}

# search for id of a Label
sub albumLabel {
 my ($idagio) = @_;

 my ( $labelId, $albumLabel, $htmlPart ) = "";

 foreach my $id ( keys %{$idagio} ) {
  $albumLabel = $idagio->{$id}->{"copyright"};
  print( "looking up: ", $albumLabel, "\n" );

  my $url01     = $urlBase . '/ws/2/label?query=';
  my $url03     = '&limit=1';
  my $url02     = "label:" . uri_escape_utf8($albumLabel);
  my $searchUrl = $url01 . $url02 . $url03;

  $cmd = "curl -s " . $searchUrl;

  sleep($sleepTime);
  my $xml = `$cmd`;

  $xml =~ s/xmlns/replaced/;
  $xml =~ s/xmlns:ns2/replaced2/;
  $xml =~ s/ns2:score/score/ig;

  #save to file
  &dumpToFile( "label.xml", $xml );    #exit(0);
  &dumpToFile( "label.cmd", $cmd );

  my ($score) = "";

  my $dom = XML::LibXML->load_xml( string => $xml );

  foreach my $label ( $dom->findnodes("/metadata/label-list/label") ) {

   $score = $label->getAttribute("score");
   if ( $score eq '100' ) {
    $labelId = $label->getAttribute("id");
   }
  }

 }

 #<input type="hidden" name="labels.0.name" value="Deutsche Grammophon (DG)">
 if ($labelId) {
  $htmlPart = '<input type="hidden" name="labels.0.mbid" value="' . $labelId . '">' . "\n";
 }

 return $htmlPart;

}

sub albumTitle {
 my ($idagio) = @_;

 my ( $albumTitle, $htmlPart ) = "";

 foreach my $id ( keys %{$idagio} ) {
  $albumTitle = &clean( $idagio->{$id}->{"title"} );
 }

 # album title
 #<input type="hidden" name="name" value="Dvor�k / Tchaikovsky / Borodin: String Quartets">
 if ($albumTitle) {
  $htmlPart = '<input type="hidden" name="name" value="' . $albumTitle . '">' . "\n";
 }

 return $htmlPart;
}

sub addRCRToForm {
 my (@releaseCredit) = @_;

 my ( $htmlString, $htmlForm ) = "";
 my $i = 0;

 ( $htmlString, $i ) = &formatHtmlForCredit( $i, "composer", @releaseCredit );
 if ($htmlString) {
  if   ( !$htmlForm ) { $htmlForm = $htmlString; }
  else                { $htmlForm = $htmlForm . $htmlString; }
 }

 ( $htmlString, $i ) = &formatHtmlForCredit( $i, "soloist", @releaseCredit );
 if ($htmlString) {
  if   ( !$htmlForm ) { $htmlForm = $htmlString; }
  else                { $htmlForm = $htmlForm . $htmlString; }
 }

 ( $htmlString, $i ) = &formatHtmlForCredit( $i, "ensemble", @releaseCredit );
 if ($htmlString) {
  if   ( !$htmlForm ) { $htmlForm = $htmlString; }
  else                { $htmlForm = $htmlForm . $htmlString; }
 }

 ( $htmlString, $i ) = &formatHtmlForCredit( $i, "conductor", @releaseCredit );
 if ($htmlString) {
  if   ( !$htmlForm ) { $htmlForm = $htmlString; }
  else                { $htmlForm = $htmlForm . $htmlString; }
 }

 return $htmlForm;
}

# format html strings for Album Main Credits
sub formatHtmlForCredit {
 my ( $i, $type, @releaseCredit ) = @_;

 my ( $htmlString, $htmlForm ) = "";

 foreach my $credit (@releaseCredit) {

  foreach my $creditType ( keys %{$credit} ) {

   if ( $creditType eq $type ) {

    $htmlString = '<input type="hidden" name="artist_credit.names.' . $i . '.name" value="' . $credit->{$creditType}->{"credited"} . '">' . "\n";
    $htmlString = $htmlString . '<input type="hidden" name="artist_credit.names.' . $i . '.mbid" value="' . $credit->{$creditType}->{"artistId"} . '">' . "\n";
    $htmlString =
      $htmlString . '<input type="hidden" name="artist_credit.names.' . $i . '.join_phrase" value="' . $credit->{$creditType}->{"joinPhrase"} . '">' . "\n";

    if ( !$htmlForm ) {
     $htmlForm = $htmlString;
    } else {
     $htmlForm = $htmlForm . $htmlString;
    }
    $i++;    # keep counter running for number of credit entries
   }    # end of specific type
  }    # end of types
 }    # end of credits

 return ( $htmlForm, $i );

}

# set artists ready for form
sub setReleaseCredits {
 my ($releaseArtists) = @_;

 my @arr                    = ();
 my $joinPhrase             = ", ";
 my $joinPhraseLastComposer = "; ";
 my $joinPhraseLast         = "";
 my @releaseCredit          = ();
 my $hash                   = {};

 my $size = "";
 my $i    = 0;

 # composers first
 if ( $releaseArtists->{"composer"} ) {
  @arr  = split( ",", $releaseArtists->{"composer"} );
  $size = @arr;
  foreach my $composer (@arr) {

   $i++;

   my ( $artistId, $artistName ) = &getArtistMbid($composer);
   $hash                               = {};
   $hash->{"composer"}->{"credited"}   = $composer;
   $hash->{"composer"}->{"artistId"}   = $artistId;
   $hash->{"composer"}->{"artistName"} = $artistName;
   if ( $size == $i ) {
    $hash->{"composer"}->{"joinPhrase"} = $joinPhraseLastComposer;
   } else {
    $hash->{"composer"}->{"joinPhrase"} = $joinPhrase;
   }

   push @releaseCredit, $hash;

  }    # end of composer array
 }

 if ( $releaseArtists->{"soloist"} ) {

  # soloists second
  @arr  = split( ",", $releaseArtists->{"soloist"} );
  $size = @arr;
  $i    = 0;
  foreach my $soloist (@arr) {
   $i++;

   my ( $artistId, $artistName ) = &getArtistMbid($soloist);
   $hash                              = {};
   $hash->{"soloist"}->{"credited"}   = $soloist;
   $hash->{"soloist"}->{"artistId"}   = $artistId;
   $hash->{"soloist"}->{"artistName"} = $artistName;
   $hash->{"soloist"}->{"joinPhrase"} = $joinPhrase;

   push @releaseCredit, $hash;

  }    # end of soloist array
 }

 # ensembles third
 if ( $releaseArtists->{"ensemble"} ) {
  @arr  = split( ",", $releaseArtists->{"ensemble"} );
  $size = @arr;
  $i    = 0;
  foreach my $ensemble (@arr) {
   $i++;

   my ( $artistId, $artistName ) = &getArtistMbid($ensemble);
   $hash                               = {};
   $hash->{"ensemble"}->{"credited"}   = $ensemble;
   $hash->{"ensemble"}->{"artistId"}   = $artistId;
   $hash->{"ensemble"}->{"artistName"} = $artistName;
   $hash->{"ensemble"}->{"joinPhrase"} = $joinPhrase;

   push @releaseCredit, $hash;

  }    # end of ensemble array
 }

 # conductors fourth
 if ( $releaseArtists->{"conductor"} ) {
  @arr  = split( ",", $releaseArtists->{"conductor"} );
  $size = @arr;
  $i    = 0;
  foreach my $conductor (@arr) {
   $i++;

   my ( $artistId, $artistName ) = &getArtistMbid($conductor);
   $hash                                = {};
   $hash->{"conductor"}->{"credited"}   = $conductor;
   $hash->{"conductor"}->{"artistId"}   = $artistId;
   $hash->{"conductor"}->{"artistName"} = $artistName;
   $hash->{"conductor"}->{"joinPhrase"} = $joinPhrase;

   push @releaseCredit, $hash;

  }    # end of conductor array
 }

 return @releaseCredit;

}

# get main artist for the MB main artists part
sub getMainArtist {
 my ($hash) = @_;

 my $mainArtistHash = {};
 my $i              = 0;

 foreach my $albumId ( keys %{$hash} ) {
  foreach my $dataType ( keys %{ $hash->{$albumId} } ) {

   # its an array of hashes #
   if ( $dataType eq "participants" ) {

    my @arr = @{ $hash->{$albumId}->{$dataType} };

    foreach my $artist (@arr) {
     my $type          = $artist->{"type"};
     my $participation = $artist->{"participation"};
     my $artisName     = $artist->{"name"};
     $i++;

     #if ( $type eq 'soloist' and $participation >= .90 ) {
     if ( $type eq 'soloist' and $participation >= SOLOISTS_THRESHOLD ) {
      $mainArtistHash->{$type}->{$artisName} = $participation;
     }

     if ( $type ne 'soloist' ) {
      $mainArtistHash->{$type}->{$artisName} = $participation;
     }

    }

   }

  }

 }

 # sort by a counter in descending, on tie sort the keys ascending, swap b with a, exit on some occurence
 my ( $sortHash, $sortedHash ) = {};
 my $sorted = "";
 foreach my $type ( keys %{$mainArtistHash} ) {

  $sortHash = $mainArtistHash->{$type};

  $sorted = "";
  foreach my $soloist ( sort { $sortHash->{$b} <=> $sortHash->{$a} or $a cmp $b } keys %{$sortHash} ) {

   $sorted = $sorted . $soloist . ",";
  }
  $sorted = substr( $sorted, 0, length($sorted) - 1 );

  $sortedHash->{$type} = $sorted;
 }

 return $sortedHash;

}

__END__

