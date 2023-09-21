use Data::Dumper::Simple;
use Text::Tabs;

use constant DISTANCE_TOLERANCE_ARTIST => 1;     # artist
use constant DISTANCE_TOLERANCE_WORK   => 15;    # work

my $counterArtist      = 0;
my $counterInstruments = 0;
$tabstop = 3;

# export module
use Exporter qw(import);
our @EXPORT_OK = qw( getWorkAliasesMbid getTrackPositionMbid getWorkMbid getPlaceMbid getArtistMbid getInstrumentMbid);

# get track Mbid using Mbid of main work and between within work
sub getTrackPositionMbid {
 my ( $Mbid, $position, $workTitle, $composerMbid ) = @_;

 #print( "\n", $Mbid, ":", $position, ":", $workTitle, ":", $composerMbid, "\n" );
 print( "\nsearching MB for >", $workTitle, "< postion >", $position, "< within work >", $Mbid, "<\n" );

 # what if I do not use position within work ?
 # works for recitals when individual mpvements are played
 # position is better when whole works are played
 # do I need a count how many parts to a main work ?
 # what if I do posiiton lookup only if > 1 ?

 # do not do position if this is first one, it might be single movement performance
 # direct search is more sucessfull
 # sometimes is and sometimes is not...
 #if ( $position == 1 ) {
 # ( $id, $mbTitle ) = &getWorkAliasesMbid( $composerMbid, $workTitle );
 # print( "return >", $id, "< work >", $mbTitle, "<\n" );
 # return ( $id, $mbTitle );
 #}

 #if ( $workTitle =~ m/Fantasias or Caprices, op. 16 2. Scherzo. Presto/ ) {

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

  #print("cache at work-> main work\n");
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

    print( "return >", $id, "< work >", $mbTitle, "<\n" );
    return ( $id, $mbTitle );

    #return ( $id, $mbTitle );

   }    #work
  }    #direction and position
 }    #parts

 # not found, some albums create additional tracks for a movement, for example last movement of Beeth 9th
 if ( !$id ) {
  ( $id, $mbTitle ) = &getWorkAliasesMbid( $composerMbid, $workTitle );
 }

 #}    #debug

 print( "return >", $id, "< work >", $mbTitle, "<\n" );

 return ( $id, $mbTitle );
}

# get MB Id for work using title and aliases, especially the last one is usefull
sub getWorkAliasesMbid {

 my ( $Mbid, $title ) = @_;

 my $firstPrint = "y";

 my $url01 = $urlBase . '/ws/2/work?query=';

 print( "\tsearching MB for title/alias: ", $title );
 my $url02_1 = "work:" . uri_escape_utf8($title);
 my $url02_2 = uri_escape_utf8(" AND ") . "arid:" . $Mbid;

 my $searchUrl = $url01 . $url02_1 . $url02_2;
 my ( $cmd, $xml ) = "";

 #need to pause between api calls, not needed when running local instance;
 sleep($sleepTime);
 $cmd = "curl -s " . $searchUrl;
 $xml = `$cmd`;
 $xml =~ s/xmlns/replaced/;
 $xml =~ s/xmlns:ns2/replaced2/;
 $xml =~ s/ns2:score/score/ig;
 $mainWorkXML->{$title} = $xml;

 #save to file
 $counterAlias = $counterAlias + 1;

 &dumpToFile( "workAlias-" . sprintf( "%03d", $counterAlias ) . ".xml", $xml );    #exit(0);

 &dumpToFile( "workAlias-" . sprintf( "%03d", $counterAlias ) . ".cmd", $cmd );

 my ( $score, $MbidWork, $mbIName, $mbTitle, $titleRet ) = "";
 my $lowScore = '999';

 # ususally the first returned is the most correct.
 # take it as long as it is <= threshold
 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $work ( $dom->findnodes("/metadata/work-list/work") ) {

  foreach my $relationList ( $work->findnodes('relation-list[@target-type="artist"]') ) {

   foreach my $relation ( $relationList->findnodes('relation[@type="composer"]') ) {

    foreach my $artist ( $relation->findnodes('artist') ) {

     my $composerId = $artist->getAttribute("id");

     # does the composer matches $Mbid ?
     if ( $composerId eq $Mbid ) {

      $mbTitle = $work->findvalue("title");

      # let's try to  forget aboutt calculating distance and aliases
      # just grab the first one
      $MbidWork = $work->getAttribute("id");
      $titleRet = $mbTitle;
      return ( $MbidWork, $titleRet );

      #my $distance = distance( $title, $mbTitle, { ignore_diacritics => 1 } );

      #if ($firstPrint) {
      # $firstPrint = "";
      # print expand ( "\n\t\ttitle ", sprintf( "%03d", $distance ), "\t", sprintf( "%03d", $lowScore ), "\t", $title, "<--->", $mbTitle, "\n" );
      #} else {
      # print expand ( "\t\ttitle ", sprintf( "%03d", $distance ), "\t", sprintf( "%03d", $lowScore ), "\t", $title, "<--->", $mbTitle, "\n" );
      #}

      #if ( $lowScore > $distance && $distance <= DISTANCE_TOLERANCE_WORK ) {
      # $lowScore = $distance;
      # $MbidWork = $work->getAttribute("id");
      # $titleRet = $mbTitle;
      # return ( $MbidWork, $titleRet );

      #}

      # if not found, check aliases
      #if ($MbidWork) { next; }

      #foreach my $alias ( $work->findnodes("alias-list") ) {

      #my $names = join "%", map { $_->to_literal(); } $alias->findnodes('./alias');
      #my @arr   = split( "%", $names );
      #foreach my $alias (@arr) {
      #$distance = distance( $title, $alias, { ignore_diacritics => 1 } );

      #print expand( "\t\talias ", sprintf( "%03d", $distance ), "\t", sprintf( "%03d", $lowScore ), "\t", $title, "<--->", $alias, "\n" );

      #if ( $lowScore > $distance && $distance <= DISTANCE_TOLERANCE_WORK ) {
      #$lowScore = $distance;
      #$MbidWork = $work->getAttribute("id");
      #$titleRet = $alias;
      #return ( $MbidWork, $titleRet );

      #}    # tolerance

      #}    # alias array
      #}    # alias

     }    # composer
    }    # artist
   }    # relation
  }    # relation list
 }    # work

 return ( $MbidWork, $titleRet );
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
 my $lowScore = '999';

 my $dom = XML::LibXML->load_xml( string => $xml );

 foreach my $work ( $dom->findnodes("/metadata/work-list/work") ) {

  foreach my $relationList ( $work->findnodes('relation-list[@target-type="artist"]') ) {

   foreach my $relation ( $relationList->findnodes('relation[@type="composer"]') ) {

    foreach my $artistName ( $relation->findnodes("artist") ) {
     my $composerId = $artistName->getAttribute("id");

     #print Dumper($mbId,$composerId);
     if ( $composerId eq $mbId ) {

      # disambiguation have special editions and arrangements etc., skip it
      if ( !$work->findvalue("disambiguation") ) {

       my $mbTitle = $work->findvalue("title");

       $mbIdWork = $work->getAttribute("id");
       print( " : ", $mbIdWork, "\n" );
       return ($mbIdWork);

       # forget about calculating distance
       # let's grab first returned

       #my $distance = distance( $title, $mbTitle, { ignore_diacritics => 1 } );

       #print( " ", $distance, " ", $lowScore, " between ", $title, " <---> ", $mbTitle, "\n" );
       #if ( $lowScore > $distance ) {
       # $lowScore = $distance;
       # $mbIdWork = $work->getAttribute("id");

       # if ( $lowScore <= DISTANCE_TOLERANCE_WORK ) {
       #  print( " : ", $mbIdWork, "\n" );
       #  return ($mbIdWork);
       # }

       #}
      }    # disambiguation
     }
    }
   }
  }

 }

 #} #debug

 print( " : ", $mbIdWork, "\n" );

 #exit;
 return $mbIdWork;
}

# get MB instrument atttributes
sub getInstrumentMbid {
 my ($name) = @_;

 my ( $instrumentId, $instrumentName, $distance ) = ( "", "", "" );

 if ( $lookup->{$name} ) {
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
 $counterInstruments++;
 &dumpToFile( "instrument-" . sprintf( "%03d", $counterInstruments ) . ".xml", $xml );    #exit(0);
 &dumpToFile( "instrument-" . sprintf( "%03d", $counterInstruments ) . ".cmd", $cmd );    #exit(0);
                                                                                          #exit;
 my $dom = XML::LibXML->load_xml( string => $xml );

 my $i = 0;
 foreach my $instrument ( $dom->findnodes("/metadata/instrument-list/instrument") ) {

  my $instrumentNameMB = $instrument->findvalue("name");

  # don't do distance, first returned is usually correct
  #$distance = distance( $name, $instrumentNameMB, { ignore_diacritics => 1 } );

  #$i++;

  #if ( $i > 1 ) { print "\n" } ;   print( $distance, " between ", $name, '<-->', $instrumentNameMB, "\n" );

  #if ( $distance == 0 ) {
   $instrumentId   = $instrument->getAttribute("id");
   $instrumentName = $instrumentNameMB;

   $lookup->{$name}->{"instrumentId"}   = $instrumentId;
   $lookup->{$name}->{"instrumentName"} = $instrumentName;

   return ( $instrumentId, $instrumentName );
   next;
  #}

  #do not check aliases

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
 $url02 = 'artist:' . $name . ' OR alias:' . $name;

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
 $counterArtist++;
 &dumpToFile( "artist-" . $counterArtist . ".xml", $xml );    #exit(0);
 &dumpToFile( "artist-" . $counterArtist . ".cmd", $cmd );    #exit(0);

 my ( $artistId, $mbArtistName, $distance ) = "";

 my $dom = XML::LibXML->load_xml( string => $xml );

 # multiple records including aliases
 # try string similiarity on name and aliases
 foreach my $artist ( $dom->findnodes("/metadata/artist-list/artist") ) {

  $mbArtistName = $artist->findvalue("name");
  $distance     = distance( $name, $mbArtistName, { ignore_diacritics => 1 } );

  #print( $distance, " between ", $name, '<-->', $mbArtistName, "\n" );

  if ( $distance <= DISTANCE_TOLERANCE_ARTIST ) {
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

    #print ( "\talias ", $distance, " between ", $name, '<-->', $alias, "\n" );

    if ( $distance <= DISTANCE_TOLERANCE_ARTIST ) {
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
