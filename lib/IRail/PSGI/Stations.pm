package IRail::PSGI::Stations;
use strict;
use warnings;
use Plack::Request;
use WebHive::Log;
use List::Util qw/max/;
use JSON::XS;
use Encode;

# ABSTRACT: PSGI Station interface for IRail API

# station loading ###########################################################################

our $timestamp;

sub read_csv_files {

    my %stationlist;

    for (qw/BE FR NL INT/) {
        open my $fh, '<:encoding(UTF-8)', "db/$_.csv" or die $!; 
        while(my $line = readline $fh) {
            chomp $line;
            my ($id, $name, $lat, $long, $region, $lang, $usr01) = split /\s*;\s*/, $line;
            $stationlist{$id} = { id => $id, name => $name, lang => $lang, lat => $lat, long => $long, region => $region };
        }
        close $fh;
    }
    
    ($timestamp) = max (map { (stat("db/$_.csv"))[9] } (qw/BE FR NL INT/));
    
    return \%stationlist;

}

# station helpers ##########################################################################

sub construct_xml {
    my ($stationlist,$lang) = @_;
    return join("\n",(
          '<?xml version="1.0" encoding="UTF-8"?>',
          '<stations xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="stations.xsd" version="1.0" timestamp="'.$timestamp.'">',
            (map { '<station id="'.$_->{id}.'" location="'.$_->{lat}.' '.$_->{long}.'" locationY="'.$_->{lat}.'" locationX="'.$_->{long}.'">'. $_->{name}.'</station>' }
             sort { $a->{name} cmp $b->{name} } 
             #FIXME: grep { if($lang) { $_->{lang} =~ m/$lang/ } else { $_->{lang} =~ m/\*/ } }
             values (%$stationlist)),
          '</stations>',
    ));
}

sub construct_json {
    my ($stationlist,$lang) = @_;
    return encode_json { station => [ map { { id => $_->{id}, 
                                              name => $_->{name}, 
                                              locationX => $_->{long}, 
                                              locationY => $_->{lat}  } } 
                                      sort { $a->{name} cmp $b->{name} } 
                                      #FIXME: grep { if($lang) { $_->{lang} =~ m/$lang/ } else { $_->{lang} =~ m/\*/ } }
                                      values %$stationlist ] };
}

# external API ##############################################################################
our $API= sub {
    my $env = shift;
    my $req = new Plack::Request($env);
    my $param = $req->parameters();
    my $cache = $env->{cache};

    # try to get the list of stations from the cache
    my $stationlist = $cache->get('stationlist');

    # if there is no cache, build the values from the csv files
    unless ($stationlist)  { $stationlist = read_csv_files(); $cache->set('stationlist', $stationlist, '1 week') }

    # untaint the incoming variables (think XSS)
    my ($lang) = ($param->{lang} || 'nl' =~ m/^(nl|fr|en|de)$/io); 
    my ($format) = ($param->{format} || 'xml' =~ m/^(xml|json|jsonp)$/io);

    # dispatch table depending on format, defaults to XML
    my $export = {
        xml => sub {   
            my $xml = $cache->get("stations_xml_$lang");
            unless ($xml) { $xml = construct_xml($stationlist,$lang); 
                            $cache->set("stations_xml_$lang", $xml, '1 week') } 

            return [ 200, [ 'Content-Type' => 'text/xml' ], [ encode('UTF-8',$cache->get("stations_xml_$lang")) ] ];
        },
        json => sub {
            my $json = $cache->get("stations_json_$lang");
            unless ($json) { $json = construct_json($stationlist,$lang); 
                             $cache->set("stations_json_$lang", $json, '1 week') } 

            return  [ 200, [ 'Content-Type' => 'application/json; charset=UTF-8' ], [ encode('UTF-8',$cache->get("stations_json_$lang")) ] ];
        },
        jsonp => sub {
            my ($callback) = ($param->{callback} || 'callback' =~ m/^([\w_]+)$/);
            my $json = $cache->get("stations_json_$lang");
            unless ($json) { $json = construct_json($stationlist,$lang); 
                             $cache->set("stations_json_$lang", $json, '1 week') } 

            return  [ 200, [ 'Content-Type' => 'application/javascript; charset=UTF-8' ], [ encode('UTF-8',"$callback(" . $cache->get("stations_json_$lang") . ");") ] ];
        }

    };

    return $export->{$format}() || [ 500, [ 'Content-Type' => 'text/plain' ], [ 'error' ] ];

    
};


42;
