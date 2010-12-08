package IRail::PSGI;
use strict;
use warnings;
use Plack::Request;
use WebHive::Log;
use List::Util qw/max/;
use JSON::XS;

# station loading ###########################################################################

our %searchlist;
our %stationlist;
our $timestamp;
our $xml; 
our $json;

sub read_csv_files {
    for (qw/BE FR NL INT/) {
        open my $fh, '<:encoding(UTF-8)', "db/$_.csv" or die $!; 
        while(my $line = readline $fh) {
            chomp $line;
            my ($id, $name, $lat, $long, $region, $lang, $usr01) = split /;/, $line;
            $searchlist{$name} = { lang => $lang };
            $stationlist{$id} = { id => $id, name => $name, lang => $lang, lat => $lat, long => $long, region => $region };
        }
        close $fh;
    }
    
    ($timestamp) = max map { (stat("db/$_.csv"))[9] } (qw/BE FR NL INT/);
}

# external API ##############################################################################
our $stations = sub {
    my $env = shift;
    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    unless (scalar %stationlist) { read_csv_files() }

    my ($lang) = ($param->{lang} || '' =~ m/^(nl|fr|en|de)$/io);
    my ($format) = ($param->{format} || '' =~ m/^(xml|json|jsonp)$/io);

    if (!$format || $format =~ m/xml/io) {
        
        $xml ||= join("\n",(
          '<?xml version="1.0" encoding="UTF-8"?>',
          '<stations xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="stations.xsd" version="1.0" timestamp="',$timestamp,'">',
            (map { '<station id="'.$_->{id}.'" location="'.$_->{lat}.' '.$_->{long}.'" locationY="'.$_->{lat}.'" locationX="'.$_->{long}.'">'. $_->{name}.'</station>'."\n" }
             grep { if(defined $lang) { $_->{lang} =~ m/$lang/ } else {1}; }
             sort { $a->{name} cmp $b->{name} } 
             values (%stationlist)),
          '</stations>',
        ));
    
        return [ 200, [ 'Content-Type' => 'text/xml' ], [ $xml ] ];

    } elsif ($format =~ m/json$/i) {

        $json ||= encode_json { station => [ map { { id => $_->{id}, 
                                                     name => $_->{name}, 
                                                     locationX => $_->{long}, 
                                                     locationY => $_->{lat}  } } 
                                             sort { $a->{name} cmp $b->{name} } 
                                             values %stationlist ] };

        return  [ 200, [ 'Content-Type' => 'application/json; charset=UTF-8' ], [ $json ] ];

    } elsif ($format =~ m/jsonp$/i ) {

        my ($callback) = ($param->{callback} || 'callback' =~ m/^([\w_]+)$/);

        $json ||= encode_json { station => [ map { { id => $_->{id}, 
                                                     name => $_->{name}, 
                                                     locationX => $_->{long}, 
                                                     locationY => $_->{lat}  } } 
                                             sort { $a->{name} cmp $b->{name} } 
                                             values %stationlist ] };
        return  [ 200, [ 'Content-Type' => 'application/javascript; charset=UTF-8' ], [ "$callback($json);" ] ];
    }

    return  [ 500, [ 'Content-Type' => 'text/plain' ], [ 'error' ] ];

    
};

42;
