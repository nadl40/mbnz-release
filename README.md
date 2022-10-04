# perl scripts to add classical releases to Musicbrainz

This repo contains few perl scripts to add Classical and Jazz releases to Musicbrainz.org and populate artist and work relationships. 

## Table of contents

<!-- toc -->

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
  * [idagio](#idagio)
  * [discogs](#discogs)
  * [relationships](#relationships)
  * [recordings clone](#recordings clone)
- [Limitations](#limitations)
- [Performance](#performance)

<!-- tocstop -->

## Prerequisites
* basic perl knowledge
* developed and tested on Ubuntu 20.04.4 LTS, perl -v v5.30.0
* webdriver https://www.selenium.dev/documentation/webdriver/
* following perl modules (and more likelly more)
```
Config::General
Cwd
Data::Dumper::Simple
Encode
Env
Exporter
File::Basename
File::Copy
File::Find::Rule
Getopt::Long
HTTP::Request
Hash::Persistent
JSON::MaybeXS
JSON::XS::VersionOneAndTwo
LWP::UserAgent
List::MoreUtils
Mojo::DOM
Mojo::UserAgent
Selenium::Remote::Driver
Selenium::Remote::WDKeys
Selenium::Waiter
Storable
String::Unquotemeta
String::Util
Text::CSV
Text::Levenshtein
URI::Escape
XML::LibXML
```

## Installation

Download this repository and change current working directory to repository

```bash
git clone https://github.com/nadl40/mbnz-release.git
cd mbnz-release
```

There is a model config file `mbnz.conf` for your Musicbrainz.org id/password and script options.
Edit and copy it to $HOME/.config/mbnz directory. 


## Usage

### idagio

Uses idagio url of an album to create and submit html release add form to musicbrainz.org.
It also creates a `relationshipsSerial.txt` file that can be used to add release relationships using a webdriver.

```bash
./idagio.pl --url IdagioAlbumUrl
```

There will be a number of displays to stdout and at the end your default browser should open Musicbrainz release add form. You might have to provide userid/pass as I did not automate.

### discogs

Uses discogs url of a release (not master) of an album to create and submit html release add form to musicbrainz.org.
It also creates a `relationshipsSerial.txt` file that can be used to add release relationships using a webdriver.

```bash
./discogs.pl --url DiscogsAlbumUrl
```

There will be a number of displays to stdout and at the end, your default browser should open Musicbrainz release add form. You might have to provide userid/pass as I did not automate.

Discogs release must be of a good quality, it needs to provide composer and artist per tracks. Also the formatting of main wok and movement must adhere to latest guidelines.
For example, this is an example of a good release:

https://www.discogs.com/release/14903602-Mendelssohn-Budapest-Festival-Orchestra-Ivan-Fischer-Anna-Lucia-Richter-Barbara-Kozelj-Pro-Musica-Gi

Most recent Ivan Fisher releases do not follow standards and will generate warnings and incomplete html form.

### artist and work relationships

Both above scripts generate `relationshipsSerial.txt` file that is used by the script addRelationships.pl to add artist credits and works in the Musicbrainz Relationship tab.

First, you have to have webdriver up and running. I'm using Opera driver

```bash
./operadriver --url-base=/wd/hub
```
   
You should see output similar to this

```bash
Starting OperaDriver 105.0.5195.102 (4c16f5ffcc2da70ee2600d5db77bed423ac03a5a-refs/branch-heads/5195_55@{#4}) on port 9515
Only local connections are allowed.
Please see https://chromedriver.chromium.org/security-considerations for suggestions on keeping OperaDriver safe.
OperaDriver was started successfully.
```

Next we can start main script 
```bash
./addRelationships.pl --data relationshipsSerial.txt --release mb_release_id
```
   
A new instance of the default browser should open, log you into musicbrainz.org and start adding data.
This process is relativelly slow to account for page javascript completion.

Once all the data has been entered, the script will exit but the browser window will remain open till you close it. Please don't forget to verify data entered and save. I do not save automatically as this would place the script into a bot territory.

You can also add relationships to an existing Musicbrainz release:

* find the release in either idagio or discogs
* run idagio or discogs release add but cancel adding release
* you might text edit `realtionshipsSerial.txt` and remove the artist or works
* run addRelatioships.pl

This is especially usefull for adding new work rels, any existing work rels will not be ovverwritten. Existing artist credits will be marked as a change unfortunatelly. 

### recordings clone

This script use case is when a new release is a compilation of previous releases, including multivolume souurce.
For example https://musicbrainz.org/release/5cebdc6c-cdc5-41b5-a09b-73e34c245d90 is just a repackaging of precious releases.
Linking original recordings will also link artist and work relaitonships from the original recordings.

First, you have to have webdriver up and running (see above).

Next we can start main script 
```bash
/recordingsClone.pl --clone clone.csv
```

`clone.csv` sample is provided in the script folder. It's a csv delimited with `:` to allow for usage of comma to specify track list. Track list can be comma delimited or have a range (for example 2-5) or both.
Empty tracklist means all tracks.
Empty source volume means all volumes but in reality it means volume 1.
Empty target volume is not allowed as we can clone 1 to 1 releases when creating a new release.
Multiple rows can be specifed but only 1 unique target release.

After all data has been entered, the script will pause so there is a chance to review the linked recordings and enter an Edit Note.
After save, terminate the script manually.

## Limitations
There are plenty.
* Firstly, I'm not an experienced perl programmer, there are plenty of areas for improvement.
* Secondly, the quality and consistency of source metadata must be good, if you try an odly formatted entry in discogs, you will not get much done.
* Thirdly, creating Work Relationships is challenging at best of times, so your success ratio will vary. Please verify all entries for correction, especially work rels, and edit or remove as required.  

Most of my time as an editor is spend entering Classical and Jazz releases. I find this sets of scripts time saving and hope that others will have similar experience.

## Performance
One of my goals was to provide mbid on a form or rels webdriver. So I do a lot of lookups.

Artist or Places do not require many multiple lookups, things get complicated when trying to identify work relationships.

The first step is to identify main work, for example a Symphony, when this is accomplished, I'm using a movement position to derive individual recording work relationshop. This works if the source follows standard main work breakdown into movements, it breaks down if the source has non standard movements. This is often hapenning with Betthoven 9th Symphony for example.

If I can't determine main work, I'm searching within a composer for the movement by itself. There are many api calls and that requires multiple cals that need to be timed otherwise Musicbrainz complains and does not return data. There is a sleep parameter in the config file, please adjust as required.

A much better solution is to run the scripts against a mirror database, in this case there are no limits how often you can query the database and sleep parm is ignored. 

