#!/usr/bin/perl
use Plack::Builder;
use IRail::PSGI::Stations;
use IRail::PSGI::Connections;

#sub status { [ shift, [ 'Content-Type' => 'text/plain' ], [ shift ] ] }

builder {
    enable 'Plack::Middleware::Static', path => qr{^/(images|js|html|static|css|favicon\.ico)}, root => 'html/';
    mount '/stations/' => builder { 
        $IRail::PSGI::Stations::API;
    };
    mount '/connections/' => builder {
        #enable '+WebHive::Middleware::Cache', config => { driver => 'File', global => 1 };
        $IRail::PSGI::Connections::API;
    };
}

__DATA__

