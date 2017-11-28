package FixMyStreet::App::Controller::Admin::AreaStats;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

sub index : Path : Args(0) {
    my ( $self, $c ) = @_;
    $c->res->redirect('/dashboard');
}

sub body : Path : Args(1) {
    my ($self, $c, $body_id) = @_;
    $c->forward('/admin/lookup_body', $body_id);
    $c->res->redirect('/dashboard?body=' . $c->stash->{body_id});
}

1;
