#!/usr/bin/perl
use Plack::Builder;
use IRail::PSGI::Stations;
use IRail::PSGI::Connections;
use IRail::PSGI::Liveboard;

builder {
    enable 'Plack::Middleware::Static', path => qr{^/(images|js|html|static|css|favicon\.ico)}, root => 'html/';
    mount '/stations/' => builder { 
        $IRail::PSGI::Stations::API;
    };
    mount '/connections/' => builder {
        #enable '+WebHive::Middleware::Cache', config => { driver => 'File', global => 1 };
        $IRail::PSGI::Connections::API;
    };
    mount '/liveboard/' => builder {
        #enable '+WebHive::Middleware::Cache', config => { driver => 'File', global => 1 };
        $IRail::PSGI::Liveboard::API;
    };
}

__DATA__

