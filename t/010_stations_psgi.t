#!/usr/bin/perl
use Plack::Test;
use Test::More;
use Data::Dumper;
use HTTP::Request::Common;
use Plack::Builder;
use IRail::PSGI::Stations;
use Plack::App::Proxy;
use WebHive::Middleware::Cache;

# this is a small psgi application with only one bound url
my $app = builder { 
    mount '/stations/' => builder { 
        $IRail::PSGI::Stations::API 
    } 
};

# this is a psgi proxy application pointing to dev.api.irail.be for all urls
my $proxy_app = builder { mount "/" => Plack::App::Proxy->new(remote => "http://dev.api.irail.be/")->to_app; };

# this is the main test loop which will setup a psgi application and test it
test_psgi app => $ENV{PROXY} == 1 ? $proxy_app : $app, client => sub {
    my $cb = shift;
    my $res; # see man HTTP::Response
    
    # test unknown url
    $res = $cb->(GET "/unknown_url");
    cmp_ok $res->status_line, 'eq', '404 Not Found', 'expecting status 400 when url does not begin with http';
    
    # test station url with different kind of arguments ########################################################
    $res = $cb->(GET "/stations/");
    ok($res->is_success, "HTTP::Response should have successful state");
    like($res->header('Content-Type'), qr@text/xml@, "Header Content-Type must be text/xml");
    cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url'
        or diag($res->content);

    $res = $cb->(GET "/stations/?format=xml");
    ok($res->is_success, "HTTP::Response should have successful state");
    like($res->header('Content-Type'), qr@text/xml@, "Header Content-Type must be text/xml");
    cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url'
        or diag($res->content);

    $res = $cb->(GET "/stations/?format=json");
    ok($res->is_success, "HTTP::Response should have successful state");
    like($res->header('Content-Type'),qr@^application/json@, "Header Content-Type must be application/json");
    cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url'
        or diag($res->content);

    $res = $cb->(GET "/stations/?format=jsonp");
    ok($res->is_success, "HTTP::Response should have successful state");
    like($res->header('Content-Type'),qr@^application/javascript@, "Header Content-Type must be application/json");
    cmp_ok $res->status_line, 'eq', '200 OK', 'expecting status 200 OK for normal url'
        or diag($res->content);
    
    done_testing();
}


