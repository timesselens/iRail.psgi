package IRail::PSGI::Stations;
use strict;
use warnings;
use Plack::Request;
use WebHive::Log;
use List::Util qw/max/;
use JSON::XS;
use Google::ProtocolBuffers;
use Encode;
use encoding 'utf-8';
use parent 'Exporter';
our @EXPORT = qw/&get_station_id &get_station_sid/;

# ABSTRACT: PSGI interface for IRail API

# station loading ###########################################################################

our %searchlist_l1;
our %searchlist;
our %stationlist;
our $timestamp;
our %xml; 
our %json;

sub normalized_station_re {
    my $name = shift;

    my $re = lc $name;
    $re =~ s/(^\s*|\s*$)//go;
    $re =~ s/\s*\([^)]+\)$//go;
    $re =~ s/\s*\[[^]]+\]$//go;
    $re =~ s/\W/\\W\?/gio;
    $re =~ s/([äâ])/\[a$1\]/gio;
    $re =~ s/([ç])/\[c$1\]/gio;
    $re =~ s/([éè])/\[e$1\]/gio;
    $re =~ s/([ïî])/\[i$1\]/gio;
    $re =~ s/([ô])/\[o$1\]/gio;
    $re =~ s/([ü])/\[u$1\]/gio;

    return qr/^$re/i;
}

sub read_csv_files {
    for (qw/BE FR NL INT/) {
        open my $fh, '<:encoding(UTF-8)', "db/$_.csv" or die $!; 
        while(my $line = readline $fh) {
            chomp $line;
            my ($id, $name, $lat, $long, $stationid, $lang, $usr01) = split /\s*;\s*/, $line;
            my $re = normalized_station_re($name);
            (my $compact = lc $name) =~ s/\W//gio;
            $searchlist_l1{$compact} = { lang => $lang, id => $id, stationid => $stationid };
            $searchlist{$re} = { lang => $lang, id => $id, stationid => $stationid } if $re;
            $stationlist{$id} ||= { id => $id, lat => $lat, long => $long, stationid => $stationid };
            $stationlist{$id}{name}{$lang || 'default'} = $name;
            push @{$stationlist{$id}{re}}, $re;
        }
        close $fh;
    }
    
    ($timestamp) = max map { (stat("db/$_.csv"))[9] } (qw/BE FR NL INT/);
}
   
unless (scalar %stationlist) { read_csv_files() }

# exported functions ##########################################################################
sub search_station {
    my ($name) = @_; $name =~ s/^\s*|\s*$//g; 
    my ($stationidre) = grep { $name =~ $_ } (keys %IRail::PSGI::Stations::searchlist);
    return $stationidre;
}

sub get_station_id {
    my $name = shift; 
    (my $compact = lc $name) =~ s/\W//gio;
    return $searchlist_l1{$compact}{id} if exists $searchlist_l1{$compact};
    my $stationidre = search_station($name);
    return $searchlist{$stationidre}{id} if $stationidre && exists $searchlist{$stationidre};
}

sub get_station_sid {
    my $name = shift; 
    (my $compact = lc $name) =~ s/\W//gio;
    return $searchlist_l1{$compact}{stationid} if exists $searchlist_l1{$compact};
    return $stationlist{$name}{stationid} if exists $stationlist{$name}; #when $name is BE.NBMS.\d
    my $stationidre = search_station($name);
    return $searchlist{$stationidre}{stationid} if $stationidre && exists $searchlist{$stationidre};
}

# external API ##############################################################################
our $API = sub {
    my $env = shift;
    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my ($lang) = ($param->{lang} || 'all' =~ m/^(nl|fr|en|de|all)$/io);
    my ($format) = ($param->{format} || 'xml' =~ m/^(xml|json|jsonp)$/io);

    if ($format =~ m/xml/io) {
        
        $xml{$lang} ||= encode('UTF-8',join("\n",(
          '<?xml version="1.0" encoding="UTF-8"?>',
          '<stations xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="stations.xsd" version="1.0" timestamp="'.$timestamp.'">',
            (map { '<station id="'.$_->{id}.'" location="'.$_->{lat}.' '.$_->{long}.'" locationY="'.$_->{lat}.'" locationX="'.$_->{long}.'">'. $_->{name}.'</station>' }
             grep { if(defined $_->{lang} && $lang =~ m/^\w{2}$/) { $_->{lang} =~ m/$lang/i } 1 } 
             sort { $a->{name} cmp $b->{name} } 
             values (%stationlist)),
          '</stations>',
        )));
    
        return [ 200, [ 'Content-Type' => 'text/xml' ], [ $xml{$lang} ] ];

    } elsif ($format =~ m/protobuf/) {

        Google::ProtocolBuffers->parse(qq#
                message Stations {
                  required string version  = 1;
                  required int32 timestamp = 2; // epoch timestamp
                  repeated Station list = 3 [packed=true];


                  message Station {
                    required string id = 1;
                    required string name = 2;
                    optional float long = 3;
                    optional float lat = 4;
                    repeated StationName names = 5 [packed=true];

                    message StationName {
                        required string name = 1;
                        required string lang = 2;
                    }

                  }
        
               }
        #, {create_accessors => 1 });

        my $buf = Stations->encode({ timestamp => $timestamp, version => "1.0", list => [values %stationlist]});

        return  [ 200, [ 'Content-Type' => 'application/octet-stream' ], [ $buf ] ];

    } elsif ($format =~ m/json$/i) {

        $json{$lang} ||= encode('UTF-8',encode_json { station => [ map { { id => $_->{id}, 
                                                                           name => $_->{name}, 
                                                                           locationX => $_->{long}, 
                                                                           locationY => $_->{lat}  } } 
             grep { if(defined $_->{lang} && $lang =~ m/^\w{2}$/) { $_->{lang} =~ m/$lang/i } 1 } 
                                                                   sort { $a->{name} cmp $b->{name} } 
                                                                   values %stationlist ] });

        return  [ 200, [ 'Content-Type' => 'application/json; charset=UTF-8' ], [ $json{$lang} ] ];

    } elsif ($format =~ m/jsonp$/i ) {

        my ($callback) = ($param->{callback} || 'callback' =~ m/^([\w_]+)$/);

        $json{$lang} ||= encode('UTF-8',encode_json { station => [ map { { id => $_->{id}, 
                                                                           name => $_->{name}, 
                                                                           locationX => $_->{long}, 
                                                                           locationY => $_->{lat}  } } 
             grep { if(defined $_->{lang} && $lang =~ m/^\w{2}$/) { $_->{lang} =~ m/$lang/i } 1 } 
                                                                   sort { $a->{name} cmp $b->{name} } 
                                                                   values %stationlist ] });

        return  [ 200, [ 'Content-Type' => 'application/javascript; charset=UTF-8' ], [ "$callback($json{$lang});" ] ];
    }

    return  [ 500, [ 'Content-Type' => 'text/plain' ], [ 'error' ] ];

    
};

42;


