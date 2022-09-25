# export module
use Exporter qw(import);
our @EXPORT_OK = qw(clean delExtension dumpToFile delExtension);

# stadard title cleanup after loujine
sub clean {
 my ($title) = @_;

 if ($title) {

  $title =~ s/ In / in /;
  $title =~ s/Minor/minor/;
  $title =~ s/Major/major/;
  $title =~ s/Op\./op\. /;
  $title =~ s/ op\. /, op\. /;
  $title =~ s/No\. /no\. /;
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

  # emebeded double quotes are not good
  $title =~ s/\"/\'/g;

  # "/" in title is really "no."
  $title =~ s/\// no. /g;

  $title =~ s/\([^)]*\)//g;
  $title =~ s/  / /g;
  $title = trim($title);

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

# delete files by exension
sub delExtension {
 my ($ext) = @_;

 foreach my $file ( glob("./*.$ext") ) {
  unlink($file);
 }

}

1;
