package WebHive::Middleware::Cache;
use strict;
use warnings;
use parent qw/Plack::Middleware/;
use Plack::Request;
use Plack::Util;
use Plack::Util::Accessor qw/config/;
use WebHive::Log qw/warn info alert/;
use CHI;

sub prepare_app {
    my ($self) = shift;

    die "config argument required (see CHI)" unless $self->config;
    die "config argument needs te be a hash" unless ref $self->config eq "HASH";
}

sub call {
    my ($self, $env) = @_;

    my @args = (%{$self->config});
    my $cache = $env->{cache} = CHI->new(@args) or die $!;

    my $ret = $self->app->($env);

    # after request cache hooks 

    return $ret;
}

42;
