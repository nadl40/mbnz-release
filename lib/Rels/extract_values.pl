#!/usr/bin/perl
use strict;
use warnings;

my $infile  = 'trackList01.txt';
my $outfile = 'trackList01.nomozart.txt';

open my $in,  '<', $infile  or die "Cannot open $infile: $!";
open my $out, '>', $outfile or die "Cannot open $outfile: $!";

while (<$in>) {
    s/- Wolfgang Amadeus Mozart\s*//g;
    print $out $_;
}

close $in;
close $out;

print "Done. Output written to $outfile\n";
