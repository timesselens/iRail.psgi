#!/usr/bin/perl
use Plack::Test;
use Test::More;
use Test::Deep;
use Data::Dumper;
use HTTP::Request::Common;
use Plack::Builder;
use IRail::PSGI::Liveboard;
use Plack::App::Proxy;
use XML::Simple;

### [ t/011_fets_liveboard_dendermonde_vertaling_kortrijk.t ] ######################################################################
# 
# ISSUE:    raised by Stef Van Dessel Wed, Dec 22, 2010 at 11:17 PM
# AUTHOR:   Tim Esselens
# DATE:     2010-12-23
#
# DESCRIPTION:
#   1. The liveboard on http://widgets.irail.be/liveboard.html?station=dendermonde&lang=fr&dir=arr 
#      indicates there is a train from "Court-Saint-Etienne"
#
#   2. The same liveboard in dutch http://widgets.irail.be/liveboard.html?station=dendermonde&lang=nl&dir=arr
#      shows the same train as coming from "Kortrijk"
#
# PROBLEM: 
#   - "Kortrijk" SHOULD BE "Courtrai" NOT "Court-Saint-Etienne"
#
# PROOF (both sides):
#   - get liveboard for "Dendermonde" in french             
#   - seek trains from "Court-Saint-Etienne"
#   - get vehicle id
#   - get liveboard for "Dendermonde" in dutch
#   - seek same vehicle id and assert existance
#   - assert vehicle is not "Kortrijk"
#
#   - get liveboard for "Dendermonde" in dutch
#   - seek trains from "Kortrijk"
#   - get vehicle id
#   - get liveboard for "Dendermonde" in french
#   - seek same vehicle id and assert existance
#   - assert vehicle is "Courtrai"
#
# BORDER CASES:
#   - no arrivals in "Dendermonde" station
#   - no arrivals from "Court-Saint-Etienne" in "Dendermonde"
#   - no arrivals from "Kortrijk"
#   - two arrivals from either "Kortrijk" or "Court-Saint-Etienne"
#
####################################################################################################################################

# this is a small psgi application with only one bound url
my $app = builder { mount '/liveboard/' => builder { $IRail::PSGI::Liveboard::API } };

# this is a psgi proxy application pointing to api.irail.be for /liveboard/ => /liveboard/
my $proxy_app = builder { mount "/liveboard/" => Plack::App::Proxy->new(remote => "http://api.irail.be/liveboard/")->to_app; };

# this is the main test loop which will setup a psgi application and test it
test_psgi app => $ENV{PROXY} == 1 ? $proxy_app : $app, client => sub {
    my $cb = shift;
    my $res; # see man HTTP::Response

    #############################################################################################################################
    ## LEFT HAND SIDE ###########################################################################################################
    #############################################################################################################################
    
    # get the liveboard for "Dendermonde" in french ###########################################################################
    $res = $cb->(GET "/liveboard/?station=dendermonde&arrdep=ARR&lang=fr");
    ok($res->is_success, "HTTP::Response should have successful state") or diag($res->content);
    like($res->header('Content-Type'),qr@^text/xml@, "Header Content-Type must be text/xml");
    cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url';

    # if the request was successful start parsing the content from xml to perl
    my $xml1 = XMLin($res->decoded_content);

    # print Dumper $xml1; # for all your debugging needs :-)

    like($xml1->{station}->{content}, qr/dendermonde|termonde/i, "This is the liveboard of Dendermonde station");
    like($xml1->{station}->{content}, qr/termonde/i, "Dendermonde station was correctly translated to french");
    my @trains1 = values %{$xml1->{arrivals}->{arrival}};


    SKIP: {
        skip('currently no arrivals in Dendermonde, bailing out', 7)  unless @trains1 > 0;
        skip('currently no arrivals from Court-Saint-Etienne in Dendermonde station, skipping', 7)
            unless grep { $_->{station}->{content} =~ m/^court\W?saint\W?etienne$/i } @trains1;

        my ($vehicle_id) = map { $_->{vehicle} } grep { $_->{station}->{content} =~ m/^court\W?saint\W?etienne$/i } @trains1;

    
        # get the liveboard for "Dendermonde" in dutch #############################################################################
        $res = $cb->(GET "/liveboard/?station=dendermonde&arrdep=ARR&lang=nl");
        ok($res->is_success, "HTTP::Response should have successful state") or diag($res->content);
        like($res->header('Content-Type'),qr@^text/xml@, "Header Content-Type must be text/xml");
        cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url';

        # if the request was successful start parsing the content from xml to perl, check the station name
        my $xml2 = XMLin($res->decoded_content);
        like($xml2->{station}->{content}, qr/dendermonde|termonde/i, "This is the liveboard of Dendermonde station");
        like($xml2->{station}->{content}, qr/dendermonde/i, "Dendermonde station was correctly translated to dutch");

        # get a list of arrivals, bail out if none arrive or seek $vehicle_id exists in the list
        my @trains2 = values %{$xml2->{arrivals}->{arrival}};
        diag('currently no arrivals in Dendermonde, bailing out') and done_testing() unless @trains2 > 0;
        cmp_deeply(\@trains2, superbagof(superhashof({vehicle => $vehicle_id})), "liveboard SHOULD contain $vehicle_id");
            
        # assert the station name for the specified vehicle id is correct
        my ($station) = map { $_->{station}->{content} } grep { $_->{vehicle} =~ m/$vehicle_id/i } @trains2;
        ok($station ne 'Kortrijk', 'Court-Saint-Etienne is MUST NOT be translated as Kortrijk for the same verhicle_id');

    }

    #############################################################################################################################
    ## RIGHT HAND SIDE ##########################################################################################################
    #############################################################################################################################
    
    # get the liveboard for "Dendermonde" in dutch #############################################################################
    $res = $cb->(GET "/liveboard/?station=dendermonde&arrdep=ARR&lang=nl");
    ok($res->is_success, "HTTP::Response should have successful state") or diag($res->content);
    like($res->header('Content-Type'),qr@^text/xml@, "Header Content-Type must be text/xml");
    cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url';

    # if the request was successful start parsing the content from xml to perl
    my $xml3 = XMLin($res->decoded_content);

    # print Dumper $xml3; # for all your debugging needs :-)

    like($xml3->{station}->{content}, qr/dendermonde|termonde/i, "This is the liveboard of Dendermonde station");
    like($xml3->{station}->{content}, qr/dendermonde/i, "Dendermonde station was correctly translated to dutch");
    my @trains3 = values %{$xml3->{arrivals}->{arrival}};

    SKIP: {
        skip('currently no arrivals in Dendermonde, bailing out',7) unless @trains3 > 0;
        skip('currently no arrivals from Kortrijk in Dendermonde station, bailing out',7)
            unless grep { $_->{station}->{content} =~ m/^kortrijk$/i } @trains3;

        my ($vehicle_id2) = map { $_->{vehicle} } grep { $_->{station}->{content} =~ m/^kortrijk$/i } @trains3;
        
        # get the liveboard for "Dendermonde" in french ###########################################################################
        $res = $cb->(GET "/liveboard/?station=dendermonde&arrdep=ARR&lang=fr");
        ok($res->is_success, "HTTP::Response should have successful state") or diag($res->content);
        like($res->header('Content-Type'),qr@^text/xml@, "Header Content-Type must be text/xml");
        cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url';

        # if the request was successful start parsing the content from xml to perl, check the station name
        my $xml2 = XMLin($res->decoded_content);
        like($xml2->{station}->{content}, qr/dendermonde|termonde/i, "This is the liveboard of Dendermonde station");
        like($xml2->{station}->{content}, qr/termonde/i, "Dendermonde station was correctly translated to french");

        # get a list of arrivals, bail out if none arrive or seek $vehicle_id2 exists in the list
        my @trains4 = values %{$xml2->{arrivals}->{arrival}};
        diag('currently no arrivals in Dendermonde, bailing out') and done_testing() unless @trains4 > 0;
        cmp_deeply(\@trains4, superbagof(superhashof({vehicle => $vehicle_id2})), "liveboard SHOULD contain $vehicle_id2");
            
        # assert the station name for the specified vehicle id is correct
        my ($station) = map { $_->{station}->{content} } grep { $_->{vehicle} =~ m/$vehicle_id2/i } @trains4;
        ok($station eq 'Courtrai', 'Kortrijk MUST be translated as Courtrai for the same verhicle_id');
    }

    done_testing();
}


