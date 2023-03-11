# export module
use Exporter qw(import);
our @EXPORT_OK = qw(clean delExtension dumpToFile delExtension readConfig);

# read and parse config file
sub readConfig {
 my ( $confPath, $confFile ) = @_;
 my $conf = Config::General->new(
  -ConfigFile  => $confPath . "/" . $confFile,
  -SplitPolicy => 'equalsign'
 );
 my %config = $conf->getall;    #get all config

 return \%config;
}

# stadard title cleanup after loujine
sub clean {
 my ($title) = @_;

 if ($title) {

  $title =~ s/ In / in /;
  $title =~ s/Minor/minor/;
  $title =~ s/Major/major/;
  $title =~ s/Op\ /op\. /g;
  $title =~ s/Op\./op\. /g;
  $title =~ s/ op\. /, op\. /;
  $title =~ s/No\. /no\. /;

  # this might missfire
  $title =~ s/ No / no\. /;
  $title =~ s/-Flat/-flat/;
  $title =~ s/ Flat/-flat/;
  $title =~ s/ flat/-flat/;
  $title =~ s/-Sharp/-sharp/;
  $title =~ s/ Sharp/-sharp/;
  $title =~ s/ sharp/-sharp/;
  $title =~ s/ K /, K /;
  $title =~ s/ KV /, K\. /;
  $title =~ s/ FWV /, FWV /;
  $title =~ s/ Hob\. /, Hob\. /;
  $title =~ s/ BWV /, BWV /;
  $title =~ s/ S /, S\. /;

  #$title =~ s/,,/,\. /;
  $title =~ s/,,/, /;

  # emebeded double quotes are not good
  #$title =~ s/\"/\'/g;

  # "/" in title is really "no."
  $title =~ s/\// no. /g;

  # remove brackets and content
  $title =~ s/\([^)]*\)//g;
  $title =~ s/  / /g;
  $title =~ s/ :/:/g;

  $title = trim($title);

  # make sure that first letter of title is capital, for example op. should be Op.
  $title =~ s/^([a-z])/\U$1/;

 }

 return $title;
}

# dump to file
sub dumpToFile {
 my ( $fileName, $hashRef ) = @_;

 #>:encoding(utf-8)
 open( my $fh, '>:encoding(utf-8)', $fileName ) or die "Could not open file '$fileName' $!";
 print $fh $hashRef;
 close $fh;
}

# write hash to a file
sub writeHash {
 my ( $fileName, $hash ) = @_;

 unlink($fileName);

 # crete in current directory
 my $obj = Hash::Persistent->new( $fileName, { format => "dumper" } );    # Dumper format, easy to read
 $obj->{string} = $hash;                                                  # make sure this is a proper hash reference, watch out for "\"
 $obj->commit;                                                            # save
 undef $obj;

}

# delete files by extension
sub delExtension {
 my ($ext) = @_;

 foreach my $file ( glob("./*.$ext") ) {
  unlink($file);
 }

}

1;
