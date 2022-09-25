# perl scripts to add classical releases to Musicbrainx

This repo contains few perl scripts to add classical music to Musicbrainz.org and populate arrtist and work relationships. 

## Table of contents

<!-- toc -->

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
  * [idagio](#idagio)
  * [discogs](#discogs)
  * [artist and work relationships](#artist and work relationships)
- [Limitations](#limitations)

<!-- tocstop -->

## Prerequisites
* perl knowledge
* developed and tested on Ubuntu 20.04.4 LTS, perl -v v5.30.0
* webdriver https://www.selenium.dev/documentation/webdriver/

## Installation

Download this repository and change current working directory to repository

```bash
git clone https://github.com/metabrainz/musicbrainz-docker.git
git clone https://github.com/nadl40/mbnz-release.git
cd mbnz-release.git
```

There is a model config file mbnz.conf for your Musicbrainz.org id/password.
Edit it and copy to $HOME/.config/mbnz directory. 


## Usage

### idagio

Uses idagio url of an album to create and submit html release add form to musicbrainz.org.
It also creates relationshipsSerial.txt file that can be used to add release relationships using a webdriver.

```bash
./idagio.pl --url IdagioAlbumUrl
```

There will be nummber of displays to stdout and at the end your default browser should open Musicbrainz release add form. You might have to provide userid/pass as I did not automate this in this sctipt.

### discogs

Uses discogs url of a rlease (not master) of an album to create and submit html release add form to musicbrainz.org.
It also creates relationshipsSerial.txt file that can be used to add release relationships using a webdriver.

```bash
./discogs.pl --url DiscogsAlbumUrl
```

There will be nummber of displays to stdout and at the end your default browser should open Musicbrainz release add form. You might have to provide userid/pass as I did not automate this in this sctipt.

Discogs release must be of good quality, it needs to provide composer and artist per tracks. Also the formatting of main wok and movement must adgere to latest guidelines.
For example, this is an example of a good release:

https://www.discogs.com/release/14903602-Mendelssohn-Budapest-Festival-Orchestra-Ivan-Fischer-Anna-Lucia-Richter-Barbara-Kozelj-Pro-Musica-Gi

Most recent Ivan Fisher releases do not follow standards and will generate warnings and incomplete html form

### artist and work relationships

Both above scripts generate relationshipsSerial.txt file that is used by script addRelationships.pl to add artist credits and works in the Musicbrainz Relationshi tab.

First, you have to have webdriver up and running. I'm using Opera diver

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
   
A new instance if the default browser should open, log you into musicbrain.org and start adding data.
This process is relativelly slow to account of page javascript completion.

Once all the data has been entered, the script will exit but the Browser window will remain open till you close it. Please don't forget to verify the data entered and save. I do n ot save automatically as this would place the scrit into bot territory.

## limitations
There are plenty.
Firstly, I'm not a professional perl programmer, there are plenty of areas for improvements.
Secondly, the quality and consistency of source metadate must be good, if you try an odly formatted entry in discogs, you will not get much done.
Thirdly, creating Work Relationships is challenging at best of times, so your success ratio will vary. Please verify all entries for correction, especially work rels, and edit or remove as required.  

Most of my time as an editor is spend on Classical Music and Jazz. I find this sets of scripts time saving and hope that others will have similar experience.
