#!/usr/bin/perl
use Plack::Runner;
use Plack::Builder;
use IRail::PSGI;

#sub status { [ shift, [ 'Content-Type' => 'text/plain' ], [ shift ] ] }

builder {
    enable 'Plack::Middleware::Static', path => qr{^/(images|js|html|static|css|favicon\.ico)}, root => 'html/';
    mount '/stations/' => builder { 
        $IRail::PSGI::stations 
    };
}

__DATA__

