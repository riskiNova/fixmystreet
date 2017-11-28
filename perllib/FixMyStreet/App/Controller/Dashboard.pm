package FixMyStreet::App::Controller::Dashboard;
use Moose;
use namespace::autoclean;

use DateTime;
use JSON::MaybeXS;
use Path::Tiny;
use Time::Piece;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

FixMyStreet::App::Controller::Dashboard - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub auto : Private {
    my ($self, $c) = @_;
    $c->stash->{filter_states} = $c->cobrand->state_groups_inspect;
    return 1;
}

sub example : Local : Args(0) {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'dashboard/index.html';

    $c->stash->{group_by} = 'category+state';

    eval {
        my $j = decode_json(path(FixMyStreet->path_to('data/dashboard.json'))->slurp_utf8);
        $c->stash($j);
    };
    if ($@) {
        my $message = _("There was a problem showing this page. Please try again later.") . ' ' .
            sprintf(_('The error was: %s'), $@);
        $c->detach('/page_error_500_internal_error', [ $message ]);
    }
}

=head2 check_page_allowed

Checks if we can view this page, and if not redirect to 404.

=cut

sub check_page_allowed : Private {
    my ( $self, $c ) = @_;

    $c->detach( '/auth/redirect' ) unless $c->user_exists;

    $c->detach( '/page_error_404_not_found' )
        unless $c->user->from_body || $c->user->is_superuser;

    my $body = $c->user->from_body;
    if (!$body && $c->get_param('body')) {
        # Must be a superuser, so allow query parameter if given
        $body = $c->model('DB::Body')->find({ id => $c->get_param('body') });
    }

    return $body;
}

=head2 index

Show the summary statistics table.

=cut

sub index : Path : Args(0) {
    my ( $self, $c ) = @_;

    my $body = $c->stash->{body} = $c->forward('check_page_allowed');

    if ($body) {
        my $area_id = $body->body_areas->first->area_id;
        my $children = mySociety::MaPit::call('area/children', $area_id,
            type => $c->cobrand->area_types_children,
        );
        $c->stash->{children} = $children;

        $c->forward('/admin/fetch_contacts');
        $c->stash->{contacts} = [ $c->stash->{contacts}->all ];

        # See if we've had anything from the body dropdowns
        $c->stash->{category} = $c->get_param('category');
        $c->stash->{ward} = $c->get_param('ward');
        if ($c->user->area_id) {
            $c->stash->{ward} = $c->user->area_id;
        }
    } else {
        $c->forward('/admin/fetch_all_bodies');
    }

    $c->stash->{start_date} = $c->get_param('start_date');
    $c->stash->{end_date} = $c->get_param('end_date');
    $c->stash->{q_state} = $c->get_param('state') || '';

    $c->forward('construct_rs_filter');

    if ( $c->get_param('export') ) {
        $self->export_as_csv($c);
    } else {
        $self->generate_data($c);
    }
}

sub construct_rs_filter : Private {
    my ($self, $c) = @_;

    my %where;
    $where{areas} = { 'like', '%,' . $c->stash->{ward} . ',%' }
        if $c->stash->{ward};
    $where{category} = $c->stash->{category}
        if $c->stash->{category};

    my $state = $c->stash->{q_state};
    if ( $state eq 'fixed - council' ) {
        $where{'me.state'} = [ FixMyStreet::DB::Result::Problem->fixed_states() ];
    } elsif ( $state ) {
        $where{'me.state'} = $state;
    } else {
        $where{'me.state'} = [ FixMyStreet::DB::Result::Problem->visible_states() ];
    }

    my $dtf = $c->model('DB')->storage->datetime_parser;
    my $date = DateTime->now( time_zone => FixMyStreet->local_time_zone )->subtract(days => 30);
    $date->truncate( to => 'day' );

    $where{'me.confirmed'} = { '>=', $dtf->format_datetime($date) };

    my $sd = $c->stash->{start_date};
    my $ed = $c->stash->{end_date};
    if ($sd or $ed) {
        my @parts;
        if ($sd) {
            my $date = $dtf->parse_datetime($sd);
            push @parts, { '>=', $dtf->format_datetime( $date ) };
        }
        if ($ed) {
            my $one_day = DateTime::Duration->new( days => 1 );
            my $date = $dtf->parse_datetime($ed);
            push @parts, { '<', $dtf->format_datetime( $date + $one_day ) };
        }

        if (scalar @parts == 2) {
            $where{'me.confirmed'} = [ -and => $parts[0], $parts[1] ];
        } else {
            $where{'me.confirmed'} = $parts[0];
        }
    }

    $c->stash->{params} = \%where;
    $c->stash->{problems_rs} = $c->cobrand->problems->to_body($c->stash->{body})->search( \%where );
}

sub generate_data {
    my ($self, $c) = @_;

    my $state_map = $c->stash->{state_map} = {};
    $state_map->{$_} = 'open' foreach FixMyStreet::DB::Result::Problem->open_states;
    $state_map->{$_} = 'closed' foreach FixMyStreet::DB::Result::Problem->closed_states;
    $state_map->{$_} = 'fixed' foreach FixMyStreet::DB::Result::Problem->fixed_states;

    $self->generate_grouped_data($c);
    $self->generate_summary_figures($c);
}

sub generate_grouped_data {
    my ($self, $c) = @_;
    my $state_map = $c->stash->{state_map};

    my $group_by = $c->get_param('group_by') || '';
    my (%grouped, @groups, %totals);
    if ($group_by eq 'category') {
        %grouped = map { $_->category => {} } @{$c->stash->{contacts}};
        @groups = qw/category/;
    } elsif ($group_by eq 'state') {
        @groups = qw/state/;
    } elsif ($group_by eq 'month') {
        @groups = (
                { extract => \"month from confirmed", -as => 'c_month' },
                { extract => \"year from confirmed", -as => 'c_year' },
        );
    } elsif ($group_by eq 'device/site') {
        @groups = qw/cobrand service/;
    } else {
        $group_by = 'category+state';
        @groups = qw/category state/;
        %grouped = map { $_->category => {} } @{$c->stash->{contacts}};
    }
    my $problems = $c->stash->{problems_rs}->search(undef, {
        group_by => [ map { ref $_ ? $_->{-as} : $_ } @groups ],
        select   => [ @groups, { count => 'me.id' } ],
        as       => [ @groups == 2 ? qw/key1 key2 count/ : qw/key1 count/ ],
    } );
    $c->stash->{group_by} = $group_by;

    while (my $p = $problems->next) {
        my %cols = $p->get_columns;
        my ($col1, $col2) = ($cols{key1}, $cols{key2});
        if ($group_by eq 'category+state') {
            $col2 = $state_map->{$cols{key2}};
        } elsif ($group_by eq 'month') {
            $col1 = Time::Piece->strptime("2017-$cols{key1}-01", '%Y-%m-%d')->fullmonth;
        }
        $grouped{$col1}->{$col2} += $cols{count} if defined $col2;
        $grouped{$col1}->{total} += $cols{count};
        $totals{$col2} += $cols{count} if defined $col2;
        $totals{total} += $cols{count};
    }
    $c->stash->{grouped} = \%grouped;
    $c->stash->{totals} = \%totals;
}

sub generate_summary_figures {
    my ($self, $c) = @_;
    my $state_map = $c->stash->{state_map};

    # problems this month by state
    $c->stash->{"summary_$_"} = 0 for values %$state_map;

    $c->stash->{summary_open} = $c->stash->{problems_rs}->count;

    my $params = $c->stash->{params};
    $params = { map { my $n = $_; s/me\./problem\./ unless /me\.confirmed/; $_ => $params->{$n} } keys %$params };

    my $comments = $c->model('DB::Comment')->to_body(
        $c->stash->{body}
    )->search(
        {
            %$params,
            'me.id' => { 'in' => \"(select min(id) from comment where me.problem_id=comment.problem_id and problem_state not in ('', 'confirmed') group by problem_state)" },
        },
        {
            join     => 'problem',
            group_by => [ 'problem_state' ],
            select   => [ 'problem_state', { count => 'me.id' } ],
            as       => [ qw/problem_state count/ ],
        }
    );

    while (my $comment = $comments->next) {
        my $meta_state = $state_map->{$comment->problem_state};
        next if $meta_state eq 'open';
        $c->stash->{"summary_$meta_state"} += $comment->get_column('count');
    }
}

sub export_as_csv {
    my ($self, $c) = @_;
    require Text::CSV;
    my $problems = $c->stash->{problems_rs}->search(
        {}, { prefetch => 'comments', order_by => 'me.confirmed' });

    my $filename = do {
        my %where = (
            category => $c->stash->{category},
            state    => $c->stash->{q_state},
            ward     => $c->stash->{ward},
        );
        $where{body} = $c->stash->{body}->id if $c->stash->{body};
        join '-',
            $c->req->uri->host,
            map {
                my $value = $where{$_};
                (defined $value and length $value) ? ($_, $value) : ()
            } sort keys %where };

    my $csv = Text::CSV->new({ binary => 1, eol => "\n" });
    $csv->combine(
            'Report ID',
            'Title',
            'Detail',
            'User Name',
            'Category',
            'Created',
            'Confirmed',
            'Acknowledged',
            'Fixed',
            'Closed',
            'Status',
            'Latitude', 'Longitude',
            'Query',
            'Ward',
            'Easting',
            'Northing',
            'Report URL',
            );
    my @body = ($csv->string);

    my $fixed_states = FixMyStreet::DB::Result::Problem->fixed_states;
    my $closed_states = FixMyStreet::DB::Result::Problem->closed_states;

    while ( my $report = $problems->next ) {
        my $external_body;
        my $body_name = "";
        if ( $external_body = $report->body($c) ) {
            # seems to be a zurich specific thing
            $body_name = $external_body->name if ref $external_body;
        }
        my $hashref = $report->as_hashref($c);

        $hashref->{user_name_display} = $report->anonymous?
            '(anonymous)' : $report->user->name;

        for my $comment ($report->comments) {
            my $problem_state = $comment->problem_state or next;
            next if $problem_state eq 'confirmed';
            $hashref->{acknowledged_pp} //= $c->cobrand->prettify_dt( $comment->created );
            $hashref->{fixed_pp} //= $fixed_states->{ $problem_state } ?
                $c->cobrand->prettify_dt( $comment->created ): undef;
            if ($closed_states->{ $problem_state }) {
                $hashref->{closed_pp} = $c->cobrand->prettify_dt( $comment->created );
                last;
            }
        }

        my $wards = join ', ',
          map { $c->stash->{children}->{$_}->{name} }
          grep {$c->stash->{children}->{$_} }
          split ',', $hashref->{areas};

        my @local_coords = $report->local_coords;

        $csv->combine(
            @{$hashref}{
                'id',
                'title',
                'detail',
                'user_name_display',
                'category',
                'created_pp',
                'confirmed_pp',
                'acknowledged_pp',
                'fixed_pp',
                'closed_pp',
                'state',
                'latitude', 'longitude',
                'postcode',
                },
            $wards,
            $local_coords[0],
            $local_coords[1],
            (join '', $c->cobrand->base_url_for_report($report), $report->url),
        );

        push @body, $csv->string;
    }
    $c->res->content_type('text/csv; charset=utf-8');
    $c->res->header('content-disposition' => "attachment; filename=${filename}.csv");
    $c->res->body( join "", @body );
}

=head1 AUTHOR

Matthew Somerville

=head1 LICENSE

Copyright (c) 2017 UK Citizens Online Democracy. All rights reserved.
Licensed under the Affero GPL.

=cut

__PACKAGE__->meta->make_immutable;

1;

