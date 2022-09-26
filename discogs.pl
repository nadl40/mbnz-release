#!/usr/bin/perl
#===============================================================
#
# Purpose:	create a MBNZ submission form from discogs
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
use File::Basename;
use Mojo::DOM;

#for my modules start
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname( dirname abs_path $0) . '/mbnz/lib';
use Rels::Utils qw(clean delExtension dumpToFile delExtension);
use Rels::Rels qw(getTrackPositionMbid getPlaceMbid getArtistMbid getWorkMbid);

# autoflush
$| = 1;
binmode( STDOUT, "encoding(UTF-8)" );

#get url from options
# get command line arguments
my ($discogsUrl) = "";
GetOptions( "release:s" => \$discogsUrl, );

#get last node form path
my ( $base, $dir1, $ext ) = fileparse( $discogsUrl, '\.*' );

#base has the release
my @arr        = split( "-", $base );
my $urlForForm = $discogsUrl;
$discogsUrl = $arr[0];
print( "discogs release for API call ", $discogsUrl, "\n" );

if ( !$discogsUrl ) {
 print( "please provide release id --release", "\n" );
 exit;
}

my ( $counterWork, $counterPosition, $counterAlias ) = 0;
my $mainWorkXML = {};

my %keystrokesMap = (
 "alto vocals"          => 2,
 "baritone vocals"      => 3,
 "contralto vocals"     => 4,
 "treble vocals"        => 5,
 "baritone vocals"      => 6,
 "bass vocals"          => 7,
 "countertenor vocals"  => 8,
 "mezzo-soprano vocals" => 9,
 "soprano vocals"       => 10,
 "tenor vocals"         => 11
);

#print Dumper ($discogsUrl);

# first call get discogs same as mbnz.pl so the hash is ready for use
# its problematic to create a pm, maybe later, for now just do an exec and read in the release hash
# remove files created by discogs
unlink "artist.txt";
unlink "artistSort.txt";
unlink "metadata.txt";
unlink "metadataSort.txt";
my $cmd = "./get_discogs.pl --get" . " " . $discogsUrl . " " . "--set /dev/null";

my $return = `$cmd`;

my $discogs = {};

if ( -e "metadata.txt" ) {
 print( "\tgot metadata.txt", "\n" );

 # add to release artists
 #read this file into a hash ...
 $discogs = &readHash("metadata.txt");

} else {
 print Dumper( $cmd, $return );
}

#we've got the hash, let's do the release add form first
#first fixed stuff
use constant HTML_FILE               => 'current.html';
use constant MB_URL                  => 'https://musicbrainz.org/ws/2/';
use constant DISTANCE_TOLERANCE      => 3;
use constant PART_THRESHOLD          => 0.60;
use constant DISTANCE_TOLERANCE_WORK => 15;

#start the form
my $htmlForm = "";

$htmlForm = $htmlForm . '<!doctype html>' . "\n";
$htmlForm = $htmlForm . '<meta charset="UTF-8">' . "\n";
$htmlForm = $htmlForm . '<title>Add Discogs Album As Release...</title>' . "\n";

#$htmlForm = $htmlForm . '<form action="https://test.musicbrainz.org/release/add" method="post">' . "\n";
$htmlForm = $htmlForm . '<form action="https://musicbrainz.org/release/add" method="post">' . "\n";

my $xml      = "";
my $htmlPart = "";

#print Dumper($discogs);exit;
#populate simple form elements
$htmlPart = "";
$htmlPart = &albumTitle( $discogs->{"title"} );
if ($htmlPart) {
 $htmlForm = $htmlForm . $htmlPart;
}

$htmlPart = "";
$htmlPart = &albumUPC( $discogs->{"upc"} );
if ($htmlPart) {
 $htmlForm = $htmlForm . $htmlPart;
}

$htmlForm = $htmlForm . '<input type="hidden" name="type" value="' . 'Album' . '">' . "\n";
$htmlForm = $htmlForm . '<input type="hidden" name="status" value="' . 'Official' . '">' . "\n";
$htmlForm = $htmlForm . '<input type="hidden" name="script" value="' . 'Latn' . '">' . "\n";

# Label credit, use search ?
$htmlPart = "";
$htmlPart = &albumLabel( $discogs->{"label"} );
if ($htmlPart) {
 $htmlForm = $htmlForm . $htmlPart;
}

# release event
$htmlPart = "";
$htmlPart = &albumRelease( $discogs->{"released"} );
if ($htmlPart) {
 $htmlForm = $htmlForm . $htmlPart;
}

# url
$htmlPart = "";
$htmlPart = &albumURL( $discogs->{"url"} );
if ($htmlPart) {
 $htmlForm = $htmlForm . $htmlPart;
}

# release artists
# before recreatig idagio mess, think how rearrange release hash so it contains all what's needed form and relationships
# use more comlpex example https://www.discogs.com/release/7527637-Richter-Rarities-With-Orchestra
my $data = &setArtists( $discogs->{"tracks"} );

# add release works
&setWorks( $discogs->{"tracks"}, $data );

$htmlPart = "";
my @releaseCredit = &setReleaseCredits($data);
$htmlPart = &addRCRToForm(@releaseCredit);
if ($htmlPart) {

 # last credit has comma as join phrase, need to replace it value=", ">
 $htmlPart = substr( $htmlPart, 0, length($htmlPart) - 5 );
 $htmlPart = $htmlPart . '">' . "\n";
 $htmlForm = $htmlForm . $htmlPart;

}

# let's do tracks
$htmlPart = "";
$htmlPart = &albumTracks( $discogs->{"tracks"}, $data->{"composer"}, $discogs->{"media"}, );
if ($htmlPart) {
 $htmlForm = $htmlForm . $htmlPart;
}

# edit note and redirect perhaps ?
$htmlPart = "";
$htmlPart = &editNote($urlForForm);
if ($htmlPart) {
 $htmlForm = $htmlForm . $htmlPart;
}

$htmlForm = $htmlForm . '</form>' . "\n";
$htmlForm = $htmlForm . '<script>document.forms[0].submit()</script>' . "\n";

#print $htmlForm;
&dumpToFile( "form.html", $htmlForm );

#need to write a file for relationship add
&writeRelationshipPersistentSerialHash( 'relationshipsSerial.txt', $data );

#open in default browser
$cmd = "xdg-open form.html";

#print("not adding \n");

$return = `$cmd`;

#======================================= subs ======================================
#
#
#===================================================================================

# write a serial relationship hash in the order of tracks, in an array of hashes.
sub writeRelationshipPersistentSerialHash {
 my ( $fileName, $recordings ) = @_;

 #print Dumper($recordings);exit;

 &writeHash( $fileName, $recordings );

}

# do edit note plus maybe redirect
sub editNote {
 my ($albumUrl) = @_;

 my $editNote = $albumUrl . " --- " . "discogs.pl Classical Music Uploader" . " --- " . "https://github.com/nadl40/mbnz-release";

 $htmlPart = '<input type="hidden" name="edit_note" value="' . "from " . $editNote . '">' . "\n";

 return $htmlPart;

}

# main driver to return track data, this should be much easier than idagio
sub albumTracks {
 my ( $discogs, $data, $media ) = @_;

 #print Dumper($discogs);
 my $trackNo = 0;

 my $tracks = {};

 # sort by track
 #foreach my $track ( sort { $a <=> $b } keys %{$discogs} ) {
 foreach my $track ( sort { $a cmp $b } keys %{$discogs} ) {

  #print Dumper($discogs->{$track});
  my @arr = @{ $discogs->{$track}->{"artist"} };
  my ( $composer, $mbid ) = "";
  foreach my $artist (@arr) {

   #print Dumper($artist);
   if ( $artist =~ m/composer/i ) {
    $composer = trim( substr( $artist, 0, index( $artist, "\(" ) ) );

    #print Dumper($composer);
    #get mbid
    $mbid = getComposerMBID( $composer, $data );

    #print Dumper($mbid);
   }
  }

  # title
  # title contains most likely work
  if ( $discogs->{$track}->{"work"} ne $discogs->{$track}->{"title"} ) {
   my $len      = length( $discogs->{$track}->{"work"} );
   my $titleNew = &clean( substr( $discogs->{$track}->{"title"}, 0, $len ) . ":" . substr( $discogs->{$track}->{"title"}, $len + 1 ) );
   $tracks->{$track}->{"title"} = $titleNew;
  } else {
   my $titleNew = &clean( $discogs->{$track}->{"work"} );
   $tracks->{$track}->{"title"} = $titleNew;
  }

  # need track duration
  if ( $discogs->{$track}->{"duration"} ) {
   $tracks->{$track}->{"duration"} = $discogs->{$track}->{"duration"};

  } else {
   print( "there is no duration for track ", $track, " this might be due to the fact that there is no duration code for non index entries", "\n" );

   #  exit(1);
  }

  if ($composer) {
   $tracks->{$track}->{"composer"}->{"id"}   = $mbid;
   $tracks->{$track}->{"composer"}->{"name"} = $composer;

  }

  #exit;

 }    # end of track

 #print Dumper($tracks);#exit;
 my $html = &formatTracksForm( $tracks, $media );

 #print Dumper($htmlForm);

 #exit;
 return $html;

}

# format html for tracks
sub formatTracksForm {
 my ( $trackHash, $media ) = @_;

 my $htmlForm = '<input type="hidden" name="mediums.0.format" value="' . $media . '">' . "\n";

 my $mediaCount = 0;
 my $trackCount = 0;

 my $arr = ();

 # sort and print
 my $list = "";

 foreach my $track ( sort { $a cmp $b } keys %{$trackHash} ) {

  @arr = split( "-", $track );

  if ( $arr[1] ) {

   if ( $mediaCount != $arr[0] - 1 ) {
    $trackCount = $arr[1] - 1;
    $mediaCount = $arr[0] - 1;
    $htmlForm   = $htmlForm . '<input type="hidden" name="mediums.' . $mediaCount . '.format' . '" ' . 'value="' . $media . '">' . "\n";

   } else {

    $trackCount = $arr[1] - 1;

   }

  } else {    # no volume

   $trackCount = $arr[0] - 1;

  }

  #print Dumper($trackCount);

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
    . $trackHash->{$track}->{"composer"}->{"name"} . '">' . "\n";
  $htmlForm =
      $htmlForm
    . '<input type="hidden" name="mediums.'
    . $mediaCount
    . '.track.'
    . $trackCount
    . '.artist_credit.names.0.mbid" value="'
    . $trackHash->{$track}->{"composer"}->{"id"} . '">' . "\n";
  $htmlForm =
      $htmlForm
    . '<input type="hidden" name="mediums.'
    . $mediaCount
    . '.track.'
    . $trackCount
    . '.length" value="'
    . $trackHash->{$track}->{"duration"} . '">' . "\n";

  #$trackCount++;

  $list = $list . $trackHash->{$track}->{"title"} . "\n";

 }

 &dumpToFile( "track list.txt", $list );
 return $htmlForm;
}

#get mb id from data
sub getComposerMBID {
 my ( $composerLookup, $data ) = @_;

 my $mbid = "";

 foreach my $composer ( keys %{$data} ) {
  if ( $composer eq $composerLookup ) {
   $mbid = $data->{$composer}->{"id"};
   return $mbid;
  }
 }

 return $mbid;
}

sub addRCRToForm {
 my (@releaseCredit) = @_;

 #print Dumper(@releaseCredit);exit;

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

 #print($htmlForm);
 return $htmlForm;
}

# format html strings for Album Main Credits
sub formatHtmlForCredit {
 my ( $i, $type, @releaseCredit ) = @_;

 #print Dumper(@releaseCredit);exit;

 my ( $htmlString, $htmlForm ) = "";

 foreach my $credit (@releaseCredit) {

  #print Dumper($credit);exit;
  #foreach my $creditType ( keys %{$credit} ) {

  if ( $credit->{"role"} eq $type ) {

   $htmlString = '<input type="hidden" name="artist_credit.names.' . $i . '.name" value="' . $credit->{"credited"} . '">' . "\n";
   $htmlString = $htmlString . '<input type="hidden" name="artist_credit.names.' . $i . '.mbid" value="' . $credit->{"artistId"} . '">' . "\n";
   $htmlString = $htmlString . '<input type="hidden" name="artist_credit.names.' . $i . '.join_phrase" value="' . ", " . '">' . "\n";

   if ( !$htmlForm ) {
    $htmlForm = $htmlString;
   } else {
    $htmlForm = $htmlForm . $htmlString;
   }
   $i++;    # keep counter running for number of credit entries
  }    # end of specific type
       #}    # end of types
 }    # end of credits

 # if composer, replace last joinphrase
 #my $htmlWork=$htmlFom;
 #print Dumper($htmlForm);exit;
 if ( $type eq "composer" && $htmlForm ) {
  $htmlForm = substr( $htmlForm, 0, length($htmlForm) - 5 ) . "; " . '">' . "\n";
 }

 #print Dumper($htmlForm);exit;
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

 # composers first
 if ( $releaseArtists->{"composer"} ) {

  # sort it
  foreach my $artist ( sort { $a cmp $b } keys %{ $releaseArtists->{"composer"} } ) {

   #printDumper($artist);
   my $hash = {};

   # don't use discogs credited, lot's of cyrylics
   $hash->{"role"}       = "composer";
   $hash->{"credited"}   = $releaseArtists->{"composer"}->{$artist}->{"name"};
   $hash->{"artistId"}   = $releaseArtists->{"composer"}->{$artist}->{"id"};
   $hash->{"artistName"} = $releaseArtists->{"composer"}->{$artist}->{"name"};
   push @releaseCredit, $hash;
  }
 }

 # soloist second only after threshold is met
 if ( $releaseArtists->{"soloist"} ) {

  #sort it
  foreach my $artist ( sort { $a cmp $b } keys %{ $releaseArtists->{"soloist"} } ) {

   #printDumper($artist);
   my $hash = {};

   # don't use discogs credited, lot's of cyrylics
   # only after PART_THRESHOLD threshold
   if ( $releaseArtists->{"soloist"}->{$artist}->{"participation"} >= PART_THRESHOLD ) {
    $hash->{"role"}       = "soloist";
    $hash->{"credited"}   = $releaseArtists->{"soloist"}->{$artist}->{"name"};
    $hash->{"artistId"}   = $releaseArtists->{"soloist"}->{$artist}->{"id"};
    $hash->{"artistName"} = $releaseArtists->{"soloist"}->{$artist}->{"name"};
    push @releaseCredit, $hash;
   }
  }
 }

 # ensemble thirds only after threshold is met
 if ( $releaseArtists->{"ensemble"} ) {

  #sort it
  foreach my $artist ( sort { $a cmp $b } keys %{ $releaseArtists->{"ensemble"} } ) {

   #printDumper($artist);
   my $hash = {};

   # don't use discogs credited, lot's of cyrylics
   # only after PART_THRESHOLD threshold
   if ( $releaseArtists->{"ensemble"}->{$artist}->{"participation"} >= PART_THRESHOLD ) {
    $hash->{"role"}       = "ensemble";
    $hash->{"credited"}   = $releaseArtists->{"ensemble"}->{$artist}->{"name"};
    $hash->{"artistId"}   = $releaseArtists->{"ensemble"}->{$artist}->{"id"};
    $hash->{"artistName"} = $releaseArtists->{"ensemble"}->{$artist}->{"name"};
    push @releaseCredit, $hash;
   }
  }
 }

 # conductor fourth only after threshold is met
 if ( $releaseArtists->{"conductor"} ) {

  #sort it
  foreach my $artist ( sort { $a cmp $b } keys %{ $releaseArtists->{"conductor"} } ) {

   #printDumper($artist);
   my $hash = {};

   # don't use discogs credited, lot's of cyrylics
   # only after PART_THRESHOLD threshold
   if ( $releaseArtists->{"conductor"}->{$artist}->{"participation"} >= PART_THRESHOLD ) {
    $hash->{"role"}       = "conductor";
    $hash->{"credited"}   = $releaseArtists->{"conductor"}->{$artist}->{"name"};
    $hash->{"artistId"}   = $releaseArtists->{"conductor"}->{$artist}->{"id"};
    $hash->{"artistName"} = $releaseArtists->{"conductor"}->{$artist}->{"name"};
    push @releaseCredit, $hash;
   }
  }
 }

 #print Dumper(@releaseCredit);

 #exit;

 return @releaseCredit;

}

# set mbnz id for works
sub setWorks {
 my ( $tracks, $data ) = @_;

 my $mainWorks = {};

 foreach my $track ( keys %{$tracks} ) {

  #print Dumper( $tracks->{$track}->{"work"} );
  my $work = $tracks->{$track}->{"work"};

  # get a composer

  if ( !$mainWorks->{$work}->{"composer"} ) {
   foreach my $artist ( @{ $tracks->{"$track"}->{"artist"} } ) {
    if ( $artist =~ m/(\(composer\))/i ) {

     #print Dumper($artist);

     #remove the role
     my @arr      = split( "\\(", $artist );
     my $composer = trim( $arr[0] );
     $mainWorks->{$work}->{"composer"} = $composer;

     # get mbid for a composer, this is already avaliable
     #print Dumper($data);#exit(0);
     foreach my $type ( keys %{$data} ) {

      if ( $type eq "composer" ) {

       foreach my $composerLookup ( keys %{ $data->{$type} } ) {
        if ( $composerLookup eq $composer ) {

         #print Dumper($data->{$type}->{$composerLookup}->{"id"});exit;
         $mainWorks->{$work}->{"composerId"} = $data->{$type}->{$composerLookup}->{"id"};
        }
       }

      }

     }

    }
   }
  }

 }    # tracks

 #print Dumper($mainWorks);
 #exit(0);

 # get MBID
 foreach my $work ( keys %{$mainWorks} ) {

  $mainWorks->{$work}->{"workId"} = &getWorkMbid( $mainWorks->{$work}->{"composerId"}, $work );
 }    # work

 my $prevWork = "";
 my $position = 0;

 # loop thru tracks and get track works, sort it
 #print "\n";

 foreach my $track ( sort { $a cmp $b } keys %{$tracks} ) {

  my $work         = $tracks->{$track}->{"work"};
  my $title        = $tracks->{$track}->{"title"};
  my $workMBid     = $mainWorks->{$work}->{"workId"};
  my $composerMBid = $mainWorks->{$work}->{"composerId"};

  if ( $position == 0 ) {
   $position = 1;
   $prevWork = $work;
  } else {
   if ( $prevWork eq $work ) {
    $position++;
   } else {
    $position = 1;
    $prevWork = $work;
   }
  }

  #print( $work, ":", $title, ":", $position, "\n" );
  my ( $trackMBid, $mbTitle ) = "";
  if ( $workMBid && $position ) {
   ( $trackMBid, $mbTitle ) = &getTrackPositionMbid( $workMBid, $position, $title, $composerMBid );
  }
  $data->{"works"}->{$track} = $trackMBid;
 }

 #print Dumper($data);exit(0);

}

sub setArtists {
 my ($tracks) = @_;

 #print Dumper($tracks);exit;

 #loop thru tracks and get artist array
 #we have 4 groups for relationship add
 # conductor
 # ensembles
 # soloist
 # venue	I don't think Discogs has it as a db field, free text only ?
 # composer
 # work

 #  foreach my $track ( keys %{$tracks}) {
 #  	     my $work = $tracks->{$track}->{"work"};
 #         $works->{$work}="";
 #}
 # print Dumper($works);
 # exit;

 # create a hash with each, add tracks
 my $artistWork = "";
 my $foundIt    = "";
 my ( $mbid, $artistName, $work ) = "";
 my $numberOfTracks = 0;
 my ( $volumeHash, $data ) = {};

 foreach my $track ( keys %{$tracks} ) {

  my @arr = split( "-", $track );
  if ( $arr[1] ) {
   if ( $volumeHash->{ $arr[0] } ) {
    $volumeHash->{ $arr[0] } = $volumeHash->{ $arr[0] } + 1;
   } else {
    $volumeHash->{ $arr[0] } = 1;
   }
  }

  $numberOfTracks++;

  foreach my $artist ( @{ $tracks->{"$track"}->{"artist"} } ) {

   $foundIt = "";

   #print( $track, " ", $artist, "\n" );

   # look for composer
   if ( $artist =~ m/(\(composer\))/i ) {
    $foundIt = "y";
    $data    = &populateHash( "composer", $artist, $track, $data );
   }

   # look for ensemble
   if ( $artist =~ m/(\(orch\))/i ) {
    $foundIt = "y";
    $data    = &populateHash( "ensemble", $artist, $track, $data );
   }

   # look for conductor
   if ( $artist =~ m/(\(con\))/i ) {
    $foundIt = "y";
    $data    = &populateHash( "conductor", $artist, $track, $data );
   }

   # default soloist
   if ( !$foundIt ) {
    $data = &populateHash( "soloist", $artist, $track, $data );
   }

  }
 }

 # get main works mbnz id

 # score participation of all execept composers
 #print Dumper($numberOfTracks);
 my $size = 0;
 foreach my $type ( keys %{$data} ) {
  if ( $type ne "composer" ) {
   foreach my $artist ( keys %{ $data->{$type} } ) {
    $size = @{ $data->{$type}->{$artist}->{"tracks"} };

    #print Dumper($size);
    $data->{$type}->{$artist}->{"participation"} = $size / $numberOfTracks;
   }
  }
 }

 #add volume and track stats
 $data->{"volumes"} = $volumeHash;

 #print Dumper($data); exit;

 return $data;

}

# populate hash with artists
sub populateHash {
 my ( $type, $artist, $track, $data ) = @_;

 my ( $mbid, $artistName, $instrumentName ) = "";
 my $artistWork = trim( substr( $artist, 0, index( $artist, "\(" ) ) );

 if ( !$data->{$type}->{$artistWork}->{"name"} ) {
  print( "looking up: ", $artistWork, "\n" );
  ( $mbid, $artistName ) = &getArtistMbid($artistWork);

  # don't use mb name
  $data->{$type}->{$artistWork}->{"name"} = $artistWork;
  $data->{$type}->{$artistWork}->{"id"}   = $mbid;

  #if soloist, need to look for instrument
  if ( $type eq "soloist" ) {

   #print Dumper($artist);
   my $start      = index( $artist, "\(" ) + 1;
   my $end        = index( $artist, "\)" );
   my $instrument = trim( substr( $artist, $start, $end - $start ) );
   print( "looking up: ", $instrument, "\n" );

   #print Dumper($instrument);
   #get the mb id if not vocals
   if ( $instrument !~ m/(vocals|choir)/i ) {

    ( $mbid, $instrumentName ) = &getInstrumentMbid( lc($instrument) );
    if ($mbid) {
     $data->{$type}->{$artistWork}->{"instrument"}->{"id"}         = $mbid;
     $data->{$type}->{$artistWork}->{"instrument"}->{"name"}       = $instrumentName;
     $data->{$type}->{$artistWork}->{"instrument"}->{"keystrokes"} = "";
    }
   } else {

    if ( $instrument =~ m/(vocals)/i ) {
     my $keystrokes = $keystrokesMap{ lc($instrument) };
     if ( !$keystrokes ) {
      print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
      print( "voice keystrokes not found ", $instrument, " exit.", "\n" );
      print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
      exit(0);
     } else {
      $data->{$type}->{$artistWork}->{"instrument"}->{"id"}         = "";
      $data->{$type}->{$artistWork}->{"instrument"}->{"name"}       = $instrumentName;
      $data->{$type}->{$artistWork}->{"instrument"}->{"keystrokes"} = $keystrokes;

     }
    } else {

     #choir
     $data->{$type}->{$artistWork}->{"instrument"}->{"id"}         = "";
     $data->{$type}->{$artistWork}->{"instrument"}->{"name"}       = "chorus";
     $data->{$type}->{$artistWork}->{"instrument"}->{"keystrokes"} = 13;

    }

   }

   #exit;
  }

 }

 push @{ $data->{$type}->{$artistWork}->{"tracks"} }, $track;

 return $data;

}

sub albumURL {
 my ($albumUrl) = @_;

 if ($albumUrl) {

  #<input type="hidden" name="urls.0.url" value="https://open.spotify.com/album/5YskZbV3lsAF66MfzfaI9J">
  #<input type="hidden" name="urls.0.link_type" value="85">

  $htmlPart = '<input type="hidden" name="urls.0.url" value="' . $albumUrl . '">' . "\n";
  $htmlPart = $htmlPart . '<input type="hidden" name="urls.0.link_type" value="' . '76' . '">' . "\n";

 }

 return $htmlPart;

}

sub albumRelease {
 my ($discogs) = @_;

 my ( $albumRelease, $htmlPart ) = "";

 $albumRelease = $discogs;

 if ($albumRelease) {

  my @arr = split( "-", $albumRelease );
  if ( $arr[0] ) {
   if ( $arr[0] != 0 ) { $htmlPart = '<input type="hidden" name="events.0.date.year" value="' . $arr[0] . '">' . "\n"; }
  }
  if ( $arr[1] ) {
   if ( $arr[1] != 0 ) { $htmlPart = $htmlPart . '<input type="hidden" name="events.0.date.month" value="' . $arr[1] . '">' . "\n"; }
  }
  if ( $arr[2] ) {
   if ( $arr[2] != 0 ) { $htmlPart = $htmlPart . '<input type="hidden" name="events.0.date.day" value="' . $arr[2] . '">' . "\n"; }
  }

 }

 return $htmlPart;

}

sub albumLabel {
 my ($discogs) = @_;

 my ( $labelId, $albumLabel, $htmlPart ) = "";

 print( "looking up: ", $discogs, "\n" );

 $albumLabel = uri_escape_utf8($discogs);

 my $url01     = 'https://musicbrainz.org/ws/2/label?query=';
 my $url02     = "label:" . $albumLabel . uri_escape_utf8(" and alias") . ":" . $albumLabel;
 my $searchUrl = $url01 . $url02;

 $cmd = "curl -s " . $searchUrl;

 my $xml = `$cmd`;

 $xml =~ s/xmlns/replaced/;
 $xml =~ s/xmlns:ns2/replaced2/;
 $xml =~ s/ns2:score/score/ig;

 #save to file
 &dumpToFile( "label.xml", $xml );    #exit(0);
 &dumpToFile( "label.cmd", $cmd );

 #exit(0);

 my ($score) = "";

 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $label ( $dom->findnodes("/metadata/label-list/label") ) {

  $score = $label->getAttribute("score");
  if ( $score eq '100' ) {
   $labelId = $label->getAttribute("id");
  }
 }

 #<input type="hidden" name="labels.0.name" value="Deutsche Grammophon (DG)">
 if ($labelId) {
  $htmlPart = '<input type="hidden" name="labels.0.mbid" value="' . $labelId . '">' . "\n";
 }

 return $htmlPart;

}

sub albumUPC {
 my ($discogs) = @_;

 #print Dumper($discogs);exit;

 my ( $albumUPC, $htmlPart ) = "";

 $albumUPC = $discogs;

 # album upc
 #<input type="hidden" name="barcode" value="00028944555127">
 if ($albumUPC) {
  $htmlPart = '<input type="hidden" name="barcode" value="' . $albumUPC . '">' . "\n";

 }

 return $htmlPart;
}

sub albumTitle {
 my ($discogs) = @_;

 #print Dumper($discogs);exit;

 my ( $albumTitle, $htmlPart ) = "";

 $albumTitle = &clean($discogs);

 # album title
 #<input type="hidden" name="name" value="Dvor�k / Tchaikovsky / Borodin: String Quartets">
 if ($albumTitle) {
  $htmlPart = '<input type="hidden" name="name" value="' . $albumTitle . '">' . "\n";
 }

 return $htmlPart;
}

# read in hash with metadata
sub readHash {
 my ($hashFile) = @_;
 my $hashMeta = {};

 my $obj = Hash::Persistent->new($hashFile);
 $hashMeta = $obj->{string};    # make sure this is a proper hash reference, watch out for "\"
 undef $obj;

 return $hashMeta;
}

