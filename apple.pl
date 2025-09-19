#!/usr/bin/env perl
#*******************************************************************************
#
# scrap apple music for classical music metadata, especially opera
# - use for track assignment for soloists, ensembles, conductors only
# - requires selenium server running with chromedriver
#
#*******************************************************************************
use strict;
use warnings;
use Selenium::Remote::Driver;
use Selenium::Waiter qw/ wait_until /;
use Hash::Persistent;
use Getopt::Long;
use Config::General;
use Env;
use Clipboard;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

use lib dirname(dirname abs_path $0) . '/mbnz/lib';
use Rels::Utils qw(clean delExtension dumpToFile readConfig writeHash);
use Rels::Rels qw(getArtistMbid);

$| = 1;
binmode(STDOUT, "encoding(UTF-8)");

# Constants
use constant WAIT_FOR_APPLE => 1;

# Config path
my $confPath  = $ENV{HOME} . "/.config/mbnz";
my $confFile  = "mbnz.conf";
my $configRef = readConfig($confPath, $confFile);

# Get base url
our $urlBase = $configRef->{local}{local_url} // "https://musicbrainz.org";
print("url base $urlBase\n");

# Get command-line arguments
my ($url, $fileName);

$fileName = "relationshipsSerial.txt";

GetOptions(
    "url=s"  => \$url,
);

die "Please provide Apple Music URL using --url\n" unless $url;

# Read in relationship hash
my $obj     = Hash::Persistent->new($fileName);
my $hashRel = $obj->{string};
undef $obj;

# Start Selenium driver
my $driver = Selenium::Remote::Driver->new(
    browser_name => 'chrome',
    port         => 9515
);
$driver->maximize_window();

# Open Apple Music page
$driver->get($url);
sleep(WAIT_FOR_APPLE);

# Find album title
my $element = wait_until { $driver->find_element('headings__title', 'class_name') };
my $title   = wait_until { $driver->find_child_element($element, './span') }->get_text();
print "Album Title: $title\n";

# Find all track elements
print "Gathering track links...\n";
my @tracks = $driver->find_elements('//div[@data-testid="track-list-item"]', 'xpath');
print "Number of tracks found: ", scalar(@tracks), "\n";

# Get track URLs
my @trackSelector;
for my $i (0 .. $#tracks) {
    eval {
        wait_until { $driver->find_child_element($tracks[$i], 'contextual-menu__trigger', 'class_name') }->click();
        sleep(WAIT_FOR_APPLE);
        wait_until { $driver->find_element('//button[@title="Copy Link"]', 'xpath') }->click();
        sleep(WAIT_FOR_APPLE);
        my $trackUrl = Clipboard->paste();
        print "Track ", $i+1, " URL: $trackUrl\n";
        push @trackSelector, $trackUrl;
    };
    warn "Failed to process track ", $i+1, ": $@\n" if $@;
    #last if $i == 2; # Uncomment for testing only some tracks
}

# Build credits hash
my %creditsHash;
for my $i (0 .. $#trackSelector) {
    my $trackPage = $trackSelector[$i];
    print "Processing track ", $i+1, " URL: $trackPage\n";
    $driver->get($trackPage);
    sleep(WAIT_FOR_APPLE);
    my $artistNames = wait_until { $driver->find_elements('artist-name', 'class_name') };
    for my $artist (@$artistNames) {
        my $name = $artist->get_text();
        push @{ $creditsHash{$name}{tracks} }, $i+1;
    }
}

# Add MBIDs to creditsHash
for my $name (keys %creditsHash) {
    my ($mbid) = getArtistMbid($name);
    $creditsHash{$name}{mbid} = $mbid if $mbid;
    print "\tNo MBID found for $name\n" unless $mbid;
}

# Match ids in $hashRel to mbid in %creditsHash and replace track numbers
for my $type (qw(soloists ensembles conductor)) {
    next unless exists $hashRel->{$type};
    for my $artistId (keys %{ $hashRel->{$type} }) {
        my $mbid = $hashRel->{$type}{$artistId}{id} or next;
        for my $name (keys %creditsHash) {
            next unless $creditsHash{$name}{mbid} && $creditsHash{$name}{mbid} eq $mbid;
            for my $instrument (keys %{ $hashRel->{$type}{$artistId}{instrument} }) {
                $hashRel->{$type}{$artistId}{instrument}{$instrument}{tracks} = $creditsHash{$name}{tracks};
            }
        }
    }
}

# Write updated relationship hash to a file
writeHash($fileName, $hashRel);

# Quit the driver
$driver->quit();