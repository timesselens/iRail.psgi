#!/usr/bin/perl
use Plack::Builder;
use IRail::PSGI::Stations;

#sub status { [ shift, [ 'Content-Type' => 'text/plain' ], [ shift ] ] }

builder {
    enable 'Plack::Middleware::Static', path => qr{^/(images|js|html|static|css|favicon\.ico)}, root => 'html/';
    mount '/stations/' => builder { 
        #enable 'Static', path => qr#/#, root => 'stations/';
        #enable 'XSendfile';
        #enable '+WebHive::Middleware::Cache', config => { driver => 'File', global => 1 };

        # complex caching example
        # enable '+WebHive::Middleware::Cache', config => { driver   => 'Memcached',
        #                                                   servers  => [ "10.0.0.15:11211", "10.0.0.15:11212" ],
        #                                                   l1_cache => {
        #                                                       driver     => 'File',
        #                                                       root_dir   => '/path/to/root',
        #                                                       l1_cache   => { driver => 'Memory' }
        #                                                 };
        $IRail::PSGI::Stations::API 
    };
}

__DATA__

