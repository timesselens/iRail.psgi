#!/usr/bin/perl
use Plack::Test;
use Test::More;
use Data::Dumper;
use HTTP::Request::Common;
use Plack::Builder;
use IRail::PSGI;
use Plack::App::Proxy;


my $app = builder {
    mount '/stations/' => builder { $IRail::PSGI::stations }
};

my $proxy_app = builder {
    mount "/" => Plack::App::Proxy->new(remote => "http://dev.api.irail.be/")->to_app;
};

test_psgi app => $ENV{PROXY} == 1 ? $proxy_app : $app, client => sub {
    my $cb = shift;
    my $res; # see man HTTP::Response
    
    # test unknown url
    $res = $cb->(GET "/unknown_url");
    cmp_ok $res->status_line, 'eq', '404 Not Found', 'expecting status 400 when url does not begin with http';
    
    # test station url
    $res = $cb->(GET "/stations/", [format => 'xml']);
    ok($res->is_success, "HTTP::Response should have successful state");
    is($res->header('Content-Type'),'text/xml', "Header Content-Type must be text/xml");
    cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url'
        or diag($res->content);
    
    done_testing();
}


