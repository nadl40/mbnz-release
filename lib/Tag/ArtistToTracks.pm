package Tag::ArtistToTracks;

#use warnings;
#use strict;

use Data::Dumper::Simple;
use String::Util qw(trim);
use File::Find::Rule;

#for my modules start
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname( dirname abs_path $0) . '/parse/lib';

use Exporter qw(import);
our @EXPORT_OK = qw(addArtistToTracks addVolume);

# add artist to tracks
sub addArtistToTracks {
 my ( $hashRef, $hashReleaseRef ) = @_;

 # loop thru artist hash and add to each track
 # each artist migth have multiple roles
 #print Dumper($hashRef); exit(0);

 foreach my $artist ( keys %{$hashRef} ) {

  #print Dumper($artist); exit(0);
  foreach my $role ( keys %{ $hashRef->{$artist} } ) {

   my $tracksString =
     join( ",", @{ $hashRef->{$artist}->{$role}->{tracks} } );

   if ($tracksString) {
    my @ranges = split( ',', $tracksString );

    foreach my $rangeValue (@ranges) {

     my @startAndEnd = split( 'to', $rangeValue );

     if ( @startAndEnd[1] ) {
      &addArtistToIndividualTracks( @startAndEnd[0], @startAndEnd[1], $artist, $role, $hashReleaseRef );
     } else {
      &addArtistToIndividualTracks( @startAndEnd[0], @startAndEnd[0], $artist, $role, $hashReleaseRef );
     }
    }

    # on all tracks
   } else {
    &addArtistToIndividualTracks( '1-1', '99-100', $artist, $role, $hashReleaseRef );
   }
  }
 }
}

# each iteration specifies a unique artist and track credits
# null in tracks means credit on all tracks
# track credits are passed as an array of strings in the following format
# trackfrom to trackto
# for example, 2 row array spanning 2 track ranges
# 1-1 to 1-6
# 2-5 to 2-9
sub addArtistToIndividualTracks {
 my ( $start, $end, $artist, $role, $hashRef1 ) = @_;

 $start = addVolume( trim($start) );
 $end   = addVolume( trim($end) );

 #loop thru release hash and add artist and role
 foreach my $item ( keys %{$hashRef1} ) {
  if ( $item eq "tracks" ) {
   foreach my $track ( keys %{ $hashRef1->{$item} } ) {
    my $expandedTrack = &addVolume($track);
    if ( $expandedTrack >= $start and $expandedTrack <= $end ) {

     # composer goes to separate label
     if ( $role eq "composer" ) {
      $hashRef1->{$item}->{$track}->{"composer"} = $artist;
     } else {

      # push into artist array
      # role can be empty
      push( @{ $hashRef1->{$item}->{$track}->{"artist"} }, trim( $artist . " " . $role ) );
     }
    }
   }
  }
 }
}

# add volume of 1 if range has only track
# convert to 10+ number
# 8-1,8-10,György Pauk,Violin
# 1, Artist, Drums
# good till 199 tracks
sub addVolume {
 my ($rangeStr) = @_;

 my $expandedRange = '';

 my @range = split( '-', $rangeStr );
 if ( @range[1] ) {
  $expandedRange = ( @range[0] * 100 ) + @range[1];
 } else {
  $expandedRange = '100' + @range[0];
 }

 return $expandedRange;
}

1;

