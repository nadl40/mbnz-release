#!/usr/bin/perl
#===============================================================
#
# Purpose:	extract and format metadata from discogs release
#         	to use in MBNZ uploader for discogs.
#         	this script has it's origin in tagging effort
#         	from discogs so not all code is relevant to its
#         	current purpose.
#
#===============================================================

use Data::Dumper::Simple;
use JSON::XS::VersionOneAndTwo;
use String::Util qw(trim);
use String::Unquotemeta;
use Text::CSV;
use Getopt::Long;
use File::Find::Rule;
use List::MoreUtils qw(uniq);
use Mojo::UserAgent;
use Storable 'dclone';
use File::Copy;
use Hash::Persistent;
use URI::Escape;

use warnings;
use strict;

use open ':std', ':encoding(UTF-8)';

#for my modules start
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname( dirname abs_path $0) . '/mbnz/lib';
use Tag::ArtistToTracks qw(addArtistToTracks);

#define hash for metadata
my ( $releaseHash, $artistHash, $artistHashSort, $releaseHashSort, $droppedRoleHash ) = {};

#load valid roles
my @validRoles = loadValidRoles();

my ( $discogsReleaseId, $albumDirectory, $genreForce, $help, $composerForce, $recordedForce, $workForce, $albumTitleForce ) = "";
my ($artistForce) = "";
my $update = "no";

### get command line arguments
GetOptions(
 "get:s"      => \$discogsReleaseId,
 "set:s"      => \$albumDirectory,
 "update:s"   => \$update,
 "genre:s"    => \$genreForce,
 "recorded:s" => \$recordedForce,
 "composer:s" => \$composerForce,
 "artist:s"   => \$artistForce,
 "work:s"     => \$workForce,
 "title:s"    => \$albumTitleForce,
 "help:s"     => \$help,

);

# display usage
if ($help) { dispUsage() }

# display help anyway
if ( !$discogsReleaseId && !$albumDirectory && !$help ) {
 dispUsage();
 exit(0);
}

my $discogsResult = &getDisocgs($discogsReleaseId);
my $result        = decode_json($discogsResult);

#print Dumper($result); exit(0);

#fix the track numbering from 1.1 to 1-1 etc
foreach my $item ( keys %{$result} ) {

 if ( $item eq "tracklist" ) {

  foreach my $hash ( @{ $result->{$item} } ) {

   foreach my $key ( keys %{$hash} ) {

    if ( $key eq "position" ) {
     $hash->{$key} =~ s/\./-/g;
    }
   }
  }
 }
}

# write to file
&dumpToFile( "release.txt", \$result );

#exit(0);

# create $releaseHash;
&buildMetaDataHashes();

#print Dumper($releaseHash);exit;

#clone it
$releaseHashSort = dclone $releaseHash;

&dumpToFile( "artist.txt",     \$artistHash );
&dumpToFile( "artistSort.txt", \$artistHashSort );

# expand track info for regular
&addArtistToTracks( $artistHash, $releaseHash );

#&dumpToFile( "metadata.txt", \$releaseHash );
# write hash to read later
my $obj = Hash::Persistent->new( "metadata.txt", { format => "dumper" } );    # Dumper format, easy to read
$obj->{string} = $releaseHash;                                                # make sure this is a proper hash reference, watch out for "\"
$obj->commit;                                                                 # save
undef $obj;

# expand track info for sorted
&addArtistToTracks( $artistHashSort, $releaseHashSort );

#&dumpToFile( "metadataSort.txt", \$releaseHashSort );
# write hash toprint Dumper($releaseHashSort); exit(0);

$obj = Hash::Persistent->new( "metadataSort.txt", { format => "dumper" } );              # Dumper format, easy to read
$obj->{string} = $releaseHashSort;                                                       # make sure this is a proper hash reference, watch out for "\"
$obj->commit;                                                                            # save
undef $obj;

# get Discogs release
sub getDisocgs {
 my ($releaseId) = @_;

 # get last node after /
 # get first instance of splitted by -
 my @arr              = split( "\/", $releaseId, );
 my $releaseNumberAll = pop @arr;
 @arr = split( "-", $releaseNumberAll );
 my $releaseNumber = shift @arr;

 # try not cache on server
 my $int = int( rand(100000) );
 my $cmd = "curl -s https://api.discogs.com/releases/";
 $cmd = $cmd . $releaseNumber . "?" . $int . " --user-agent FooBarApp/3.0";

 #print Dumper($cmd);exit(0);
 my $release = `$cmd`;

 return $release;
}

# returns digits from a string
sub findDigits {
 my ($lastDir) = @_;

 if ( $lastDir =~ m/(vol|cd)/i ) {

  #print ($lastDir,"\n");
  my ($digits) = $lastDir =~ /(\d+)/;
  $digits =~ s/^0+//;
  return $digits;
  next;
 }
 return "";
}

# get all direcotries
sub getFilesModule {
 my ( $sourcePath, $validExtension ) = @_;

 my @filesNotSorted =
   File::Find::Rule->file()->name( '*' . $validExtension )->in($sourcePath);

 #sort it
 my @files = sort @filesNotSorted;

 return @files;

}

# build metadata hashes
sub buildMetaDataHashes {

 foreach my $item ( keys %{$result} ) {

  my $itemList = $result->{$item};

  if ( $item eq "artists_sort" ) {

   $releaseHash->{$item} = $itemList;
  }

  # release year
  if ( $item eq "year" ) {

   $releaseHash->{$item} = $itemList;
  }

  # genres
  if ( $item eq "genres" ) {
   foreach (@$itemList) {
   }
   $releaseHash->{$item} = $itemList;
  }

  # styles - Opera etc
  if ( $item eq "styles" ) {
   foreach (@$itemList) {
   }
   $releaseHash->{$item} = $itemList;
  }

  #data_quality
  if ( $item eq "data_quality" ) {

  }

  #released
  if ( $item eq "released" ) {
   $releaseHash->{"released"} = $result->{$item};
  }

  # release uri
  if ( $item eq "uri" ) {
   $releaseHash->{"url"} = $result->{$item};
  }

  #title
  if ( $item eq "title" ) {

   $releaseHash->{$item} = $itemList;
  }

  #extraartists
  if ( $item eq "extraartists" ) {
   &trackArtists($itemList);
  }

  #list of tracks
  if ( $item eq "tracklist" ) {
   &trackList($itemList);
  }

  #list of labels
  if ( $item eq "labels" ) {
   &labels($itemList);
  }

  #list of identifiers
  if ( $item eq "identifiers" ) {
   &identifiers($itemList);
  }

  #media
  if ( $item eq "formats" ) {
   &formats($itemList);
  }

 }

}

# formats include media
sub formats {
 my ($itemRef) = @_;
 foreach my $item (@$itemRef) {
  if ( $item->{"name"} ) {
   $releaseHash->{"media"} = $item->{"name"};
  }
 }
}

# identifiers include UPC
sub identifiers {
 my ($itemRef) = @_;
 foreach my $item (@$itemRef) {
  if ( $item->{"type"} eq "Barcode" ) {
   $releaseHash->{"upc"} = $item->{"value"};

   #print Dumper($releaseHash);
  }

 }

}

# labels include label and cat number
# it will pick up last label listed, good enough
sub labels {
 my ($itemRef) = @_;
 foreach my $item (@$itemRef) {
  if ( $item->{entity_type_name} eq "Label" ) {
   $releaseHash->{"label"} = $item->{name};
   $releaseHash->{"catno"} = $item->{catno};
  }
 }

}

#discogs extra artist - involved with track assignments
#---------------------------------------------------------------
# need to drop extra artist and other people involved
#
#---------------------------------------------------------------
sub trackArtists {
 my ($itemRef) = @_;

 foreach my $item (@$itemRef) {

  # drop the subroles between [ ] aquare brackets
  $item->{role} =~ s/\[([^\[\]]|(?0))*]//g;
  my @roles = split( ",", $item->{role} );

  for my $role (@roles) {

   my $roleSaved = $role;
   $role = &mapRoles($role);

   if ( $role !~ /drop/ ) {

    # wrap in parenthesis
    #$role = "(" . $role . ")";
    $role = "(" . $role . ")";

    my $artistName = $item->{name};

    # drop text between round braces ()
    $artistName =~ s/\s*\([^)]*\)//g;

    # keep original names
    my $artistNameSort = $artistName;

    # do not flip names
    #if ( $role !~ m/(orch|ens|coro)/i ) {
    #
    #   $artistName = &formatName($artistName);
    #}

    # artist can have multiple roles on tracks
    push( @{ $artistHash->{$artistName}->{ trim($role) }->{"tracks"} },         $item->{tracks} );
    push( @{ $artistHashSort->{$artistNameSort}->{ trim($role) }->{"tracks"} }, $item->{tracks} );
   } else {

    # add dropped roles to hash and print at the end
    $droppedRoleHash->{$roleSaved} = "";
   }
  }
 }
}

#---------------------------------------------------------------
# discogs extra artist - involved with index assignments
#---------------------------------------------------------------
sub indexArtists {
 my ( $itemRef, $position ) = @_;

 #print "sub indexArtists\n";
 #print Dumper($itemRef);
 #print Dumper($position);
 #exit;

 # drop the subroles between [ ]
 $itemRef->{role} =~ s/\[([^\[\]]|(?0))*]//g;
 my $role       = $itemRef->{role};
 my $artistName = $itemRef->{name};

 # big assumption for Classical Boxes, see https://www.discogs.com/release/9352705-Vladimir-Horowitz-The-Unreleased-Live-Recordings-1966-1983-
 #print Dumper ($role);
 # here
 if ( $role eq "" ) {
  $role = "Composed by";
 }

 #print Dumper ($role);
 #exit;
 # multiple roles might be separated by ,
 my @roles = split( ",", $role );
 for my $role (@roles) {

  my $roleSaved = $role;
  $role = &mapRoles($role);

  # drop unmapped roles
  if ( $role !~ /drop/ ) {

   # wrap in parenthesis
   $role = "(" . $role . ")";

   # drop text between ()
   $artistName =~ s/\s*\([^)]*\)//g;

   # keep original names
   my $artistNameSort = $artistName;

   #if ( $role !~ m/(orch|ens|coro)/i ) {
   #   $artistName = &formatName($artistName);
   #}

   # artist can have multiple roles on tracks
   push( @{ $artistHash->{$artistName}->{ trim($role) }->{"tracks"} },         $position );
   push( @{ $artistHashSort->{$artistNameSort}->{ trim($role) }->{"tracks"} }, $position );
  } else {

   # add dropped roles to hash and print at the end
   $droppedRoleHash->{$roleSaved} = "";
  }

 }

 #print Dumper($artistHashSort); exit;
}    # ens sub

# map discogs roles to mine, always work in progress
sub mapRoles {
 my ($role) = @_;

 $role = trim($role);

 # exact lookp
 foreach my $roles (@validRoles) {

  if ( lc($role) eq lc( $roles->[0] ) ) {
   $roles->[1] = trim( $roles->[1] );
   return $roles->[1];

   #exit;
  }
 }

 # if not found
 #print( "role drop ", $role, "\n" );
 $role = "drop";

 return $role;
}

#discogs tracklist
#---------------------------------------------------------------
#
#---------------------------------------------------------------
sub trackList {
 my ($itemRef) = @_;

 my $work  = "";
 my $title = "";

 # to handle clasical compositions like Opera
 # the above does not work, fix it ?
 # Figarro->ActI->aria see	 11463187
 # properly structured releas will have heading->index->track
 #                                   do $comp  ->$part->$mov
 my $comp = "";
 my $part = "";
 my $mov  = "";

 my $i = 0;
 foreach my $item (@$itemRef) {

  #$i++; if ($i > 5) {exit(0);}
  #print Dumper($item);

  # handle composition with part and movement
  # but drop "volume"
  if ( $item->{type_} eq "heading" ) {
   if ( $item->{title} !~ m/(volume)/i ) {
    $comp = $item->{title};
    $part = "";
   }
  }

  if ( $item->{type_} eq "index" ) {
   $part = $item->{title};
  }

  if ( $item->{type_} eq "track" ) {
   $mov = $item->{title};

   #$comp = "";
   $part = "";
  }

  # use argument value
  if ($workForce) {
   $comp = $workForce;
  }

  # set work and title for non index
  if ( $item->{type_} eq "track" ) {

   ( $work, $title ) = &setWorkTitle( $comp, $part, $mov );

   #print Dumper($item);

   # in case this is vol-track
   my $trackNo = &formatTrack( $item->{"position"} );

   $releaseHash->{"tracks"}->{$trackNo}->{"title"}    = $title;
   $releaseHash->{"tracks"}->{$trackNo}->{"work"}     = $work;
   $releaseHash->{"tracks"}->{$trackNo}->{"duration"} = $item->{"duration"};
   foreach my $artist ( @{ $item->{extraartists} } ) {
    &indexArtists( $artist, $trackNo );
   }

   # artists are also attached as arttists, for example composer, usually without a role
   # here
   for my $artists ( @{ $item->{"artists"} } ) {
    &indexArtists( $artists, $trackNo );
   }

  }

  # for index
  # here
  # name is often a composer without a role see https://www.discogs.com/release/9352705-Vladimir-Horowitz-The-Unreleased-Live-Recordings-1966-1983-
  if ( $item->{type_} eq "index" ) {

   #print Dumper($item->{"artists"});

   for my $subtrack ( @{ $item->{"sub_tracks"} } ) {

    $mov = $subtrack->{"title"};

    ( $work, $title ) = &setWorkTitle( $comp, $part, $mov );

    my $trackNo = &formatTrack( $subtrack->{"position"} );

    $releaseHash->{"tracks"}->{$trackNo}->{"title"}    = $title;
    $releaseHash->{"tracks"}->{$trackNo}->{"work"}     = $work;
    $releaseHash->{"tracks"}->{$trackNo}->{"duration"} = $subtrack->{"duration"};

    #print Dumper($releaseHash->{"tracks"});
    # if this is index, artists can be attached to all sub_tracks from index
    # for now assume that they are on all tracks of an index, see Brahms Chamber 10107843
    for my $artists ( @{ $item->{extraartists} } ) {
     &indexArtists( $artists, $trackNo );
    }

    # artists are also attached as arttists, for example composer, usually without a role
    # here
    for my $artists ( @{ $item->{"artists"} } ) {
     &indexArtists( $artists, $trackNo );
    }

   }    # each subtrack
  }    # index

 }
}

# sprintf track no
sub formatTrack {
 my ($track) = @_;

 my $trackNo = "";
 my @arr     = split( "-", $track );
 if ( $arr[0] ) {
  $trackNo = sprintf( "%02d", $arr[0] );
 }
 if ( $arr[1] ) {
  $trackNo = $trackNo . "-" . sprintf( "%02d", $arr[1] );
 }

 return $trackNo;

}

# determine work and title from $comp, $part, $mov
sub setWorkTitle {
 my ( $comp, $part, $mov ) = @_;

 my $work  = "";
 my $title = "";

 # determine work
 if ( $comp ne "" ) {
  $work = $comp;
 } else {
  if ( $part ne "" ) {
   $work = $part;
  } else {
   $work = $mov;
  }
 }

 # build title
 if ( $comp ne "" ) {
  $title = $comp . ":";
 }

 if ( $part ne "" ) {
  $title = $title . " " . $part . ",";
 }

 if ( $mov ne "" ) {
  $title = $title . " " . $mov;
 }

 # remove double space from title if any
 $title =~ s/  / /;

 # trim spaces
 $title = trim($title);

 return ( $work, $title );
}

# load valid roles from csv file
sub loadValidRoles {
 my @validRoles;
 my $rolesFile = "roles.csv";
 my $csvRoles  = Text::CSV->new;
 open my $fh, '<', $rolesFile or die "Could not open $rolesFile: $!";
 while ( my $row = $csvRoles->getline($fh) ) {
  push @validRoles, $row;
 }
 return @validRoles;
}

# dump to file
sub dumpToFile {
 my ( $fileName, $hashRef ) = @_;

 open( my $fh, '>', $fileName ) or die "Could not open file '$fileName' $!";
 print $fh Dumper($hashRef);
 close $fh;
}

# display usage on help
sub dispUsage {
 print( " Usage:",                                                                         "\n" );
 print( " ==============================================================================", "\n" );
 print( "               :",                                                                " get_discogs.pl --get [discogs release id] ", "\n" );
 print( " help          :",                                                                " get_discogs.pl --help",                      "\n" );
 print( "                ",                                                                " \tdisplays this help",                       "\n" );

}

#=======================================
# Delete later

