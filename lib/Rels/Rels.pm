use Data::Dumper::Simple;

use constant DISTANCE_TOLERANCE      => 3;
use constant DISTANCE_TOLERANCE_WORK => 15;

# export module
use Exporter qw(import);
our @EXPORT_OK = qw( getWorkAliasesMbid getTrackPositionMbid getWorkMbid, getPlaceMbid, getArtistMbid getInstrumentMbid);

# get track Mbid using Mbid of main work and between within work
sub getTrackPositionMbid {
 my ( $Mbid, $position, $workTitle, $composerMbid ) = @_;

 #if ( $workTitle =~ m/Corrente Quinta/ ) {

 my ( $id,     $orderingKey, $mbTitle ) = "";
 my ( $mbzUrl, $cmd,         $xml )     = "";
 my $args = "?inc=work-rels";

 # set up the command
 # https://musicbrainz.org/ws/2/work/60e1dcf6-e728-35be-8948-ba74500b6c6e?inc=work-rels
 $mbzUrl = $urlBase . "/ws/2/work/";
 $cmd    = "curl -s " . $mbzUrl . $Mbid . $args;

 $counterPosition = $counterPosition + 1;
 &dumpToFile( "workTrackPosition-" . $counterPosition . ".cmd", $cmd );    #exit(0);

 # cache xml for main work
 if ( !$mainWorkXML->{$Mbid} ) {

  #need to pause between api calls, not needed when running local instance;
  sleep($sleepTime);

  $xml = `$cmd`;
  $xml =~ s/xmlns/replaced/ig;
  $mainWorkXML->{$Mbid} = $xml;
 } else {
  $xml = $mainWorkXML->{$Mbid};
 }

 # replace xmlns with something, can't read it with namespace
 my $dom = XML::LibXML->load_xml( string => $xml );

 &dumpToFile( "workTrackPosition-" . $counterPosition . ".xml", $xml );    #exit(0);

 # match on position - use forward parts only
 foreach my $parts ( $dom->findnodes('/metadata/work/relation-list[@target-type="work"]/relation[@type="parts"]') ) {

  if ( ( $parts->findvalue("direction") eq 'forward' ) and ( $parts->findvalue("ordering-key") == $position ) ) {

   foreach my $work ( $parts->findnodes('work') ) {

    $id      = $work->getAttribute("id");
    $mbTitle = $work->findvalue("title");

    #print( "position ", $position, " returned value: ", $id, " title: ", $mbTitle, "\n" );

    return ( $id, $mbTitle );

   }    #work
  }    #direction and position
 }    #parts

 # not found, some albums create additional tracks for a movement, for example last movement of Beeth 9th
 if ( !$id ) {
  ( $id, $mbTitle ) = &getWorkAliasesMbid( $composerMbid, $workTitle );

 }

 #}    #debug

 #print( "position ", $position, " returned value: ", $id, " title: ", $mbTitle, "\n" );
 return ( $id, $mbTitle );
}

# get MB Id for work using title and aliases, especially the last one is usefull
sub getWorkAliasesMbid {

 my ( $Mbid, $title ) = @_;

 my $url01 = $urlBase . '/ws/2/work?query=';

 print( "\tsearching MB for title and alias: ", $title );
 my $url02_1 = "work:" . uri_escape_utf8($title);
 my $url02_2 = uri_escape_utf8(" AND ") . "arid:" . $Mbid;

 my $searchUrl = $url01 . $url02_1 . $url02_2;

 sleep($sleepTime);
 my $cmd = "curl -s " . $searchUrl;

 my $xml = `$cmd`;

 $xml =~ s/xmlns/replaced/;
 $xml =~ s/xmlns:ns2/replaced2/;
 $xml =~ s/ns2:score/score/ig;

 #save to file
 $counterAlias = $counterAlias + 1;

 &dumpToFile( "workAlias-" . $counterAlias . ".xml", $xml );    #exit(0);
 &dumpToFile( "workAlias-" . $counterAlias . ".cmd", $cmd );

 my ( $score, $MbidWork, $mbIName, $mbTitle ) = "";
 my $lowScore = '99999';

 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $work ( $dom->findnodes("/metadata/work-list/work") ) {

  foreach my $relationList ( $work->findnodes('relation-list[@target-type="artist"]') ) {

   foreach my $relation ( $relationList->findnodes('relation[@type="composer"]') ) {

    foreach my $artist ( $relation->findnodes('artist') ) {

     my $composerId = $artist->getAttribute("id");

     # does the composer matches $Mbid ?
     if ( $composerId eq $Mbid ) {

      $mbTitle = $work->findvalue("title");
      my $distance = distance( $title, $mbTitle, { ignore_diacritics => 1 } );

      #print( " a ", $distance, " ", $lowScore, " between ", $title, " <---> ", $mbTitle, "\n" );
      if ( $lowScore > $distance ) {
       $lowScore = $distance;
       $MbidWork = $work->getAttribute("id");
       if ( $lowScore <= DISTANCE_TOLERANCE_WORK ) {
        print( " : ", $MbidWork, "\n" );
        return ( $MbidWork, $mbTitle );
       }
      }

      # if not found, check aliases
      foreach my $alias ( $work->findnodes("alias-list") ) {

       my $names = join "%", map { $_->to_literal(); } $alias->findnodes('./alias');
       my @arr   = split( "%", $names );
       foreach my $alias (@arr) {
        $distance = distance( $title, $alias, { ignore_diacritics => 1 } );

        #print( " b ", $distance, " ", $lowScore, " between ", $title, " <---> ", $alias, "\n" );

        if ( $lowScore > $distance ) {
         $lowScore = $distance;
         $MbidWork = $work->getAttribute("id");
         if ( $lowScore <= DISTANCE_TOLERANCE_WORK ) {
          print( " : ", $MbidWork, "\n" );
          $mbTitle = $alias;
          return ( $MbidWork, $mbTitle );
         }    # tolerance
        }    #score
       }    # alias array
      }    # alias
     }    # composer
    }    # artist
   }    # relation
  }    # relation list
 }    # work

 print( " : ", $MbidWork, "\n" );
 return ( $MbidWork, $mbTitle );
}

# get MB Id for main work
sub getWorkMbid {
 my ( $mbId, $title ) = @_;

 my $mbIdWork = "";

 #if ($title =~ m/Corrente Quinta/) {

 my $url01 = $urlBase . '/ws/2/work?query=';

 print( "searching MB for: ", $title );
 my $url02_1 = "work:" . uri_escape_utf8($title);
 my $url02_2 = uri_escape_utf8(" AND ") . "arid:" . $mbId;

 my $searchUrl = $url01 . $url02_1 . $url02_2;

 my $cmd = "curl -s " . $searchUrl;

 my $xml = `$cmd`;

 $xml =~ s/xmlns/replaced/;
 $xml =~ s/xmlns:ns2/replaced2/;
 $xml =~ s/ns2:score/score/ig;

 #save to file
 $counter = $counter + 1;

 &dumpToFile( "work-" . $counter . ".xml", $xml );    #exit(0);
 &dumpToFile( "work-" . $counter . ".cmd", $cmd );

 my ( $score, $mbIName ) = "";
 my $lowScore = '99999';

 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $work ( $dom->findnodes("/metadata/work-list/work") ) {

  foreach my $relationList ( $work->findnodes('relation-list[@target-type="artist"]') ) {

   foreach my $relation ( $relationList->findnodes('relation[@type="composer"]') ) {

    foreach my $artistName ( $relation->findnodes("artist") ) {
     my $composerId = $artistName->getAttribute("id");
     if ( $composerId eq $mbId ) {

      # disambiguation have special editions and arrangements etc.
      if ( !$work->findvalue("disambiguation") ) {

       my $mbTitle = $work->findvalue("title");

       my $distance = distance( $title, $mbTitle, { ignore_diacritics => 1 } );

       #print( " ", $distance, " ", $lowScore, " between ", $title, " <---> ", $mbTitle, "\n" );
       if ( $lowScore > $distance ) {
        $lowScore = $distance;
        $mbIdWork = $work->getAttribute("id");

        if ( $lowScore <= DISTANCE_TOLERANCE_WORK ) {
         print( " : ", $mbIdWork, "\n" );
         return ($mbIdWork);
        }

       }
      } # disambiguation
     }
    }
   }
  }

 }

 #} #debug

 print( " : ", $mbIdWork, "\n" );
 return $mbIdWork;
}

# get MB instrument atttributes
sub getInstrumentMbid {
 my ($name) = @_;

 if ( $lookup->{$name} ) {

  #print( "\tfound in lookup", "\n" );
  return ( $lookup->{$name}->{"instrumentId"}, $lookup->{$name}->{"instrumentName"} );
 }

 print( "looking up: ", $name, "\n" );
 sleep(0.5);

 my $url01 = $urlBase . '/ws/2/instrument/?query=';

 my $url02 = $name;
 $url02     = uri_escape_utf8($url02);
 $searchUrl = $url01 . $url02;

 $cmd = "curl -s " . $searchUrl;

 my $xml = `$cmd`;

 $xml =~ s/xmlns/replaced/;
 $xml =~ s/xmlns:ns2/replaced2/;
 $xml =~ s/ns2:score/score/ig;

 #save to file
 &dumpToFile( "instrument.xml", $xml );    #exit(0);
 &dumpToFile( "instrument.cmd", $cmd );    #exit(0);
                                           #exit;
 my $dom = XML::LibXML->load_xml( string => $xml );

 my ( $instrumentId, $instrumentName, $distance ) = "";

 foreach my $instrument ( $dom->findnodes("/metadata/instrument-list/instrument") ) {

  $instrumentName = $instrument->findvalue("name");
  $distance       = distance( $name, $instrumentName, { ignore_diacritics => 1 } );

  #print( $distance, " between ", $name, '<-->', $instrumentName, "\n" );

  if ( $distance <= 1 ) {
   $instrumentId   = $instrument->getAttribute("id");
   $instrumentName = $instrument->findvalue("name");

   $lookup->{$name}->{"instrumentId"}   = $instrumentId;
   $lookup->{$name}->{"instrumentName"} = $instrumentName;

   return ( $instrumentId, $instrumentName );
  }

  #also check aliases
  my $names = "";
  foreach my $alias ( $instrument->findnodes("alias-list") ) {

   $names = join "%", map { $_->to_literal(); } $alias->findnodes('./alias');
   my @arr = split( "%", $names );
   foreach my $alias (@arr) {
    $distance = distance( $name, $alias, { ignore_diacritics => 1 } );

    #print( "\talias ", $distance, " between ", $name, '<-->', $alias, "\n" );

    if ( $distance <= 1 ) {
     $instrumentId   = $instrument->getAttribute("id");
     $instrumentName = $instrument->findvalue("name");

     $lookup->{$name}->{"instrumentId"}   = $instrumentId;
     $lookup->{$name}->{"instrumentName"} = $instrumentName;

     return ( $instrumentId, $instrumentName );
    }

   }
  }    # end of aliases

 }

 return ( $instrumentId, $instrumentName );

}

### get soloist, conductor, ensemble
### use Text::Levenshtein qw(distance) to compare names and aliases
sub getArtistMbid {
 my ($name) = @_;

 #print Dumper($lookup);
 if ( $lookup->{$name} ) {
  return ( $lookup->{$name}->{"artistId"}, $lookup->{$name}->{"mbArtistName"} );
 }

 print( "looking up: ", $name, "\n" );
 sleep(0.5);

 # try both AND and OR
 my ( $artistId, $mbArtistName, $url02 ) = "";
 $url02 = 'artist:' . $name . ' AND alias:' . $name;

 ( $artistId, $mbArtistName ) = &getMBArtist( $url02, $name );

 if ($artistId) {
  $lookup->{$name}->{"artistId"}     = $artistId;
  $lookup->{$name}->{"mbArtistName"} = $mbArtistName;
  return ( $artistId, $mbArtistName );
 }

 $url02 = 'artist:' . $name . ' OR alias:' . $name;
 ( $artistId, $mbArtistName ) = &getMBArtist( $url02, $name );

 $lookup->{$name}->{"artistId"}     = $artistId;
 $lookup->{$name}->{"mbArtistName"} = $mbArtistName;

 return ( $artistId, $mbArtistName );

}

sub getMBArtist {
 my ( $url02, $name ) = @_;

 $url02 = uri_escape_utf8($url02);

 # https://musicbrainz.org/ws/2/artist?query=artist%3ABernard%20Richter'
 my $cmd = "curl -s " . $urlBase . "/ws/2/artist?query=" . $url02;
 
 my $xml = `$cmd`;

 $xml =~ s/xmlns/replaced/;
 $xml =~ s/xmlns:ns2/replaced2/;
 $xml =~ s/ns2:score/score/ig;

 #save to file
 &dumpToFile( "artist.xml", $xml );    #exit(0);
 &dumpToFile( "artist.cmd", $cmd );    #exit(0);

 my ( $artistId, $mbArtistName, $distance ) = "";

 my $dom = XML::LibXML->load_xml( string => $xml );

 # multiple records including aliases
 # try string similiarity on name and aliases
 foreach my $artist ( $dom->findnodes("/metadata/artist-list/artist") ) {

  $mbArtistName = $artist->findvalue("name");
  $distance     = distance( $name, $mbArtistName, { ignore_diacritics => 1 } );

  #print( $distance, " between ", $name, '<-->', $mbArtistName, "\n" );

  if ( $distance <= DISTANCE_TOLERANCE ) {
   $artistId     = $artist->getAttribute("id");
   $mbArtistName = $artist->findvalue("name");
   return ( $artistId, $mbArtistName );
  }

  #also check aliases
  my $names = "";
  foreach my $alias ( $artist->findnodes("alias-list") ) {

   $names = join "%", map { $_->to_literal(); } $alias->findnodes('./alias');
   my @arr = split( "%", $names );
   foreach my $alias (@arr) {
    $distance = distance( $name, $alias, { ignore_diacritics => 1 } );

    #print( "\talias ", $distance, " between ", $name, '<-->', $alias, "\n" );

    if ( $distance <= DISTANCE_TOLERANCE ) {
     $artistId     = $artist->getAttribute("id");
     $mbArtistName = $artist->findvalue("name");

     return ( $artistId, $mbArtistName );
    }

   }
  }

 }

 return ( "", "" );

}

#find MB id for a place
sub getPlaceMbid {
 my ($placeName) = @_;

 my ( $searchUrl, $url02, $placeId, $mbid, $score ) = "";
 if ($placeName) {

  #http://musicbrainz.org/ws/2/place/?query=chipping
  my $url01 = $urlBase . '/ws/2/place?query=';
  my $url03 = '&limit=1';

  print( "looking up: ", $placeName, "\n" );

  # get MB place atttributes
  $url02     = $placeName;
  $url02     = uri_escape_utf8($url02);
  $searchUrl = $url01 . $url02 . $url03;

  my $cmd = "curl -s " . $searchUrl;

  my $xml = `$cmd`;

  $xml =~ s/xmlns/replaced/;
  $xml =~ s/xmlns:ns2/replaced2/;
  $xml =~ s/ns2:score/score/ig;

  #save to file
  &dumpToFile( "place.xml", $xml );    #exit(0);
  &dumpToFile( "place.cmd", $cmd );

  my $dom = XML::LibXML->load_xml( string => $xml );

  foreach my $place ( $dom->findnodes("/metadata/place-list/place") ) {

   $score = $place->getAttribute("score");
   if ( $score eq '100' ) {
    $placeId   = $place->getAttribute("id");
    $placeName = $place->findvalue("name");
    next;
   }
  }
 }
 return ($placeId);

}

1;
