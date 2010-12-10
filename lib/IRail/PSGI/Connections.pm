package IRail::PSGI::Connections;
use strict;
use warnings;
use Carp;
use Date::Format;
use Encode;
use HTTP::Request;
use JSON::XS;
use List::Util qw/max reduce/;
use LWP::UserAgent;
use Plack::Request;
use WebHive::Log;
use XML::Twig;

# ABSTRACT: PSGI interface for IRail API

our $VERSION = 0.001;

# external API ##############################################################################
our $API = sub {
    my $env = shift;

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my ($from) = (($param->{from} || '') =~ m/^([\w\ \-\'\.]+)$/io);
    my ($to) = (($param->{to} || '') =~ m/^([\w\ \-\'\.]+)$/io);

    croak "from not defined" unless $from;
    croak "to not defined" unless $to;

    my ($lang) = (($param->{lang} || 'nl') =~ m/^(fr|de|en|nl)$/);
    my ($date) = (($param->{date} || time2str('%Y%m%d',time) ) =~ m/^(\d+\W?\d+\W?\d+)$/io); # d-m-y
    my ($time) = (($param->{'time'} || time2str('%H%M',time)) =~ m/^(\d+\W?\d+)$/io); # hh-mm
    my ($epoch) = (($param->{epoch} || '') =~ m/^(\d+)$/io);
    my ($timesel) = map { /^a/ and 0 || /^d/ and 1 || 1 } (($param->{timesel} || 'a') =~ m/^(a(?:rrive)?|d(?:epart)?)$/io); # a(rrive) or d(epart)
    my ($type) = (($param->{type} || 'train') =~ m/^(train|bus|taxi)$/io);
    my ($results) = map { $_ > 6 ? 6 : $_  } (($param->{results} || 6) =~ m/^(\d+)$/);

    my $ua = new LWP::UserAgent;
       $ua->agent("IRail::PSGI/$VERSION");
       $ua->timeout(10);

    my $data = qq{<?xml version="1.0 encoding="UTF-8"?>
                <ReqC ver="1.1" prod="iRail API v1.0" lang="EN">
                    <LocValReq id="from" maxNr="1">
                        <ReqLoc match="$from" type="ST"/>
                    </LocValReq>
                    <LocValReq id="to" maxNr="1">
                        <ReqLoc match="$to" type="ST"/>
                    </LocValReq>
                </ReqC>'};

    my $http_req = new HTTP::Request(POST => "http://hari.b-rail.be/Hafas/bin/extxml.exe", [], $data);
    my $res = $ua->request($http_req);

    croak "was unsuccessful in POSTing data" unless $res->is_success;

    my ($from_id, $to_id) = ($res->decoded_content =~ m/externalId="([^"]+)"/gio);

    my $trainsonly = '1111111111111111';
    my ($back,$_to,$the,$future) = ($results * $timesel, $to, 'flux capacitor',$results * (-1 * ($timesel-1)));

    my $data2 = qq{<?xml version="1.0 encoding="UTF-8"?>
                   <ReqC ver="1.1" prod="irail" lang="$lang">
                    <ConReq>
                        <Start min="0">
                            <Station externalId="$from_id" distance="0"></Station>
                            <Prod prod="$trainsonly"></Prod>
                        </Start>
                        <Dest min="0">
                            <Station externalId="$to_id" distance="0"></Station>
                        </Dest>
                        <Via></Via>
                        <ReqT time="$time" date="$date" a="$timesel"></ReqT>
                        <RFlags b="$back" f="$future"></RFlags>
                        <GISParameters>
                            <Front></Front>
                            <Back></Back>
                        </GISParameters>
                    </ConReq>
                   </ReqC>};

    my $http_req2 = new HTTP::Request(POST => "http://hari.b-rail.be/Hafas/bin/extxml.exe", [], $data2);
    my $res2 = $ua->request($http_req2);

    croak "was unsuccessful in POSTing data" unless $res2->is_success;
    
    my $t = new XML::Twig(
        twig_roots => { 'ResC/ConRes/ConnectionList/Connection'=> 1 },
        twig_handlers => {
            'ResC' => sub { 
                $_->set_tag('connections'); 
                $_->set_att('timestamp' => time); 
                $_->del_att(qw/prod xsi:noNamespaceSchemaLocation ver/); 
            },

            'Connection' => sub { 
                $_->set_tag('connection'); 
                $_->del_att(qw/xcheckSumStrict/); 
                $_->set_att(id => $_->pos); 

                # extract and compose the vehicle IDs
                my $silly_xpath = 'vias/via/Journey/JourneyAttributeList/JourneyAttribute/Attribute[@type="NAME"]/AttributeVariant/Text';
                my @vehicles = map { $_->text_only } ($_->get_xpath($silly_xpath));
                $_->first_child('departure')->insert_new_elt('first_child', vehicle => $vehicles[0]);
                $_->first_child('arrival')->insert_new_elt('first_child', vehicle => $vehicles[$#vehicles]);

                map { $_->delete } $_->get_xpath('//vias/via/Journey');

                # add a url attribute to the connection
                my @context = $_->get_xpath('ContextURL');
                $_->set_att(url => $context[0]->att('url')) and $context[0]->delete if $context[0];


                # magle the vias: f([x1,y1],[x2,y2],...[xn,yn]) -> [y1,x2], [y2,x3], ..., [yn-1,xn], [delete];
                my @via = $_->get_xpath('vias/via');
                $via[0]->first_child('departure')->delete;
                # this is an unnatural but wanted off-by-one. 
                for(0 .. $#via - 1 ) { 
                    $via[$_+1]->first_child('departure')->move(after => $via[$_]->first_child('arrival')); 
                    $via[$_]->insert_new_elt('last_child', timeBetween => 
                        $via[$_]->first_child('departure')->first_child('time')->text_only - $via[$_]->first_child('arrival')->first_child('time')->text_only);
                } 
                $via[$#via]->delete;
                
            },

            'Platform' => sub {
                $_->set_tag('platform');
                $_->set_text($_->text_only ? $_->text_only : 'NA');
                $_->trim;
            },

            'Station' => sub { 
                (my $x = $_->att('x')) =~ s/^(\d)(\d)/$1.$2/; 
                (my $y = $_->att('y')) =~ s/^(\d{2})(\d)/$1.$2/;

                $_->set_tag('station'); 
                $_->del_att(qw/externalStationNr/); 
                $_->set_text($_->att('name') =~ m/(.*?)(?:\ \[[^]]+\])?$/);
                $_->set_att(x => $x, y => $y); 
            },

            'ConSectionList' => sub {
                $_->set_tag('vias');
                $_->set_att(number => scalar $_->children('via') - 1);
            },

            'ConSection' => sub {
                $_->set_tag('via');
                $_->set_att(id => $_->pos);

                my $dep = $_->first_child('departure');
                my $arr = $_->first_child('arrival');

                # remove station from arrival and departure and move it one up
                $dep->first_child('station')->delete;
                $arr->first_child('station')->move(last_child => $_);

                # get the vehicle information
                my @n = $_->findnodes('Journey/JourneyAttributeList/JourneyAttribute/Attribute/AttributeVariant/Text');
                $_->insert_new_elt('last_child',vehicle => $n[0]->text_only) if($n[0]);

            },

            'Time' => sub {
                $_->set_tag('time'); my @x = (86400,3600,60,1);
                return unless $_->text_only;
                my $epoch = (int(time / 86400) * 86400) + reduce { $a + $b } map { $_ * shift @x } ($_->text_only =~ /(\d+)d(\d+):(\d+):(\d+)/io);
                $_->set_text($epoch);
                $_->set_att(formatted => time2str("%Y-%m-%dT%H:%M:%SZ",$epoch, 'ZULU'));
            },

            'Duration' => sub { 
                $_->set_tag('duration'); my @x = (86400,3600,60,1); 
                $_->set_att('formatted' => $_->text_only);
                $_->set_text(reduce { $a + $b } map { $_ * shift @x } ($_->text_only =~ /(\d+)d(\d+):(\d+):(\d+)/));
            },

            (map { my $name = $_; $name => sub {
                my @nodes = $_->get_xpath('StopPrognosis/*/time');
                my $diff = $nodes[0] ? $nodes[0]->text_only - $_->first_child('time')->text_only : 0;
                $_->set_tag(lc $name);
                $_->set_att(delay => $diff);
                $_->first_child('StopPrognosis')->delete if $_->first_child('StopPrognosis');
            } } (qw/Departure Arrival/)),

            (map { my $name = $_; $name => sub { $_->set_tag(lc $name) } } (qw/Status/)),


            (map { $_ => sub { $_->delete } } (qw/Date 
                                                  Products 
                                                  ServiceDays 
                                                  MarginalTimes 
                                                  Transfers
                                                  /)),

            (map { $_ => sub { $_->erase } } (qw{Overview 
                                                 RtState
                                                 RtStateList
                                                 Duration/Time 
                                                 Platform/Text 
                                                 Departure/BasicStop/Dep
                                                 Departure/BasicStop 
                                                 Arrival/BasicStop/Arr 
                                                 Arrival/BasicStop})),
        },
        pretty_print => 'indented'
    );
       
    $t->parse($res2->decoded_content());

    return [ 200, [ 'Content-Type' => 'text/xml' ], [ $t->sprint() ] ];

};

42;


