package IRail::PSGI::Liveboard;
use strict;
use warnings;
use Carp;
use Date::Format;
use Encode;
use HTML::Entities;
use HTTP::Request;
use IRail::PSGI::Stations qw/get_station_id/;
use JSON::XS;
use List::Util qw/max reduce/;
use LWP::UserAgent;
use Plack::Request;
use WebHive::Log;
use XML::Twig;

use encoding 'utf-8';

# ABSTRACT: PSGI interface for IRail API
# AUTHOR: Tim Esselens <tim.esselens@gmail.com>

our $VERSION = 0.001;

# external API ##############################################################################
our $API = sub {
    my $env = shift;

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my ($station) = (($param->{station} || '') =~ m/^([\w\'\-\ ]+)$/io);

    croak "station not defined" unless $station;

    my ($lang) = (($param->{lang} || 'nl') =~ m/^(fr|de|en|nl)$/io);
    my ($time) = (($param->{'time'} || time2str('%H%M',time)) =~ m/^(\d+\W?\d+)$/io); # hh-mm
    my ($sid) = get_station_id($station);
    my ($format) = ($param->{format} || 'xml' =~ m/^(xml|json|jsonp)$/io);
    my ($timesel) = map { /^a/ && 'A' or /^d/ && 'D' } (($param->{timesel} || 'a') =~ m/^(a(?:rrive)?|d(?:epart)?)/io); # a(rrive) or d(epart)

    my $ua = new LWP::UserAgent;
       $ua->agent("IRail::PSGI/$VERSION");
       $ua->timeout(10);

    croak "sid not found" unless $sid;

    my $http_req = new HTTP::Request(GET => "http://www.railtime.be/mobile/SearchStation.aspx?l=$lang&tr=$time&sid=$sid&da=$timesel&p=2");
    my $res = $ua->request($http_req);

    croak "was unsuccessful in POSTing data" unless $res->is_success;

    my @liveboard;

    for (split /[\r\n]/, $res->decoded_content) {
        next unless /^\s*<td/;
        next if /Geen halte in gevraagd station/;

        my $line = $_;
        my %train = ( delay => 0, left => 0, work => 0, platform => 'NA', changedplatform => 0 );
        my ($epoch) = 86400 * int ( time / 86400 );

        if ( $line =~ m#(\d+):(\d+)</a>#)                           { $train{epoch} = $epoch + (3600 * $1) + (60 * $2); 
                                                                      $train{departs} = time2str("%Y-%m-%dT%H:%M:%SZ",$train{epoch},"ZULU"); }
        if ( $line =~ m#&nbsp;([\w'][^>]+?)&nbsp;#)                 { $train{station} = decode('iso-latin-1',decode_entities($1)); 
                                                                      $train{stationid} = get_station_id($train{station}) || 'NULL' };
        if ( $line =~ m#&tid=(\d+)#)                                { $train{tid} = $1 };
        if ( $line =~ m#<font color="DarkGray">#)                   { $train{left} = 1 };
        if ( $line =~ m#<font color="Red">\s*\+(\d+)'\s*</font>#)   { $train{delay} = int($1 * 60) };
        if ( $line =~ m#<img src="/mobile/images/Work.png"#)        { $train{work} = 1 }
        if ( $line =~ m#\[([\w]+)&nbsp;Spoor&nbsp;(\d+)\]# )        { $train{vehicle} = $1; $train{platform} = int($2); }
        if ( $line =~ m#Spoor&nbsp;<[bf][^>]+>(\d+)</[^>]+>\]# )    { $train{changedplatform} = 1; $train{platform} = int($2); }

        push @liveboard, \%train;
    }

    my ($xml) = map { '<?xml version="1.0" encoding="UTF-8"?>'."\n".
                      '<liveboard version="1.0" timestamp="'.time.'">'."\n".$_.'</liveboard>' }
                map { '<station stationid="'.$sid.'">'.$station.'</station>'."\n".
                      '<departures number="'.scalar @liveboard.'">'.$_.'</departures>' } 
                reduce { $a.$b}  
                map { qq#<departure delay="$_->{delay}" left="$_->{left}">
                              <time formatted="$_->{departs}">$_->{epoch}</time>
                              <vehicle>$_->{vehicle}</vehicle>
                              <platform changed="$_->{changedplatform}">$_->{platform}</platform>
                              <station stationid="$_->{stationid}">$_->{station}</station>
                         </departure># 
                } @liveboard;

    return [ 200, [ 'Content-Type' => 'text/xml; charset=UTF-8' ], [ encode("UTF-8",$xml) ] ];

};

42;


