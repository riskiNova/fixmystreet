use FixMyStreet::TestMech;
# avoid wide character warnings from the category change message
use open ':std', ':encoding(UTF-8)';

my $mech = FixMyStreet::TestMech->new;

my $user = $mech->create_user_ok('test@example.com', name => 'Test User');

my $user2 = $mech->create_user_ok('test2@example.com', name => 'Test User 2');

my $superuser = $mech->create_user_ok('superuser@example.com', name => 'Super User', is_superuser => 1);

my $oxfordshire = $mech->create_body_ok(2237, 'Oxfordshire County Council');
my $oxfordshirecontact = $mech->create_contact_ok( body_id => $oxfordshire->id, category => 'Potholes', email => 'potholes@example.com' );
$mech->create_contact_ok( body_id => $oxfordshire->id, category => 'Traffic lights', email => 'lights@example.com' );
my $oxfordshireuser = $mech->create_user_ok('counciluser@example.com', name => 'Council User', from_body => $oxfordshire);

my $oxford = $mech->create_body_ok(2421, 'Oxford City Council');
$mech->create_contact_ok( body_id => $oxford->id, category => 'Graffiti', email => 'graffiti@example.net' );

my $bromley = $mech->create_body_ok(2482, 'Bromley Council');

my $user3;

my $dt = DateTime->new(
    year   => 2011,
    month  => 04,
    day    => 16,
    hour   => 15,
    minute => 47,
    second => 23
);

my $report = FixMyStreet::App->model('DB::Problem')->find_or_create(
    {
        postcode           => 'SW1A 1AA',
        bodies_str         => '2504',
        areas              => ',105255,11806,11828,2247,2504,',
        category           => 'Other',
        title              => 'Report to Edit',
        detail             => 'Detail for Report to Edit',
        used_map           => 't',
        name               => 'Test User',
        anonymous          => 'f',
        external_id        => '13',
        state              => 'confirmed',
        confirmed          => $dt->ymd . ' ' . $dt->hms,
        lang               => 'en-gb',
        service            => '',
        cobrand            => '',
        cobrand_data       => '',
        send_questionnaire => 't',
        latitude           => '51.5016605453401',
        longitude          => '-0.142497580865087',
        user_id            => $user->id,
        whensent           => $dt->ymd . ' ' . $dt->hms,
    }
);

my $alert = FixMyStreet::App->model('DB::Alert')->find_or_create(
    {
        alert_type => 'area_problems',
        parameter => 2482,
        confirmed => 1,
        user => $user,
    },
);

$mech->log_in_ok( $superuser->email );

subtest 'check summary counts' => sub {
    my $problems = FixMyStreet::App->model('DB::Problem')->search( { state => { -in => [qw/confirmed fixed closed investigating planned/, 'in progress', 'fixed - user', 'fixed - council'] } } );

    ok $mech->host('www.fixmystreet.com');

    my $problem_count = $problems->count;
    $problems->update( { cobrand => '' } );

    FixMyStreet::App->model('DB::Problem')->search( { bodies_str => 2489 } )->update( { bodies_str => 1 } );

    my $q = FixMyStreet::App->model('DB::Questionnaire')->find_or_new( { problem => $report, });
    $q->whensent( \'current_timestamp' );
    $q->in_storage ? $q->update : $q->insert;

    my $alerts =  FixMyStreet::App->model('DB::Alert')->search( { confirmed => { '>' => 0 } } );
    my $a_count = $alerts->count;

    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'fixmystreet' ],
    }, sub {
        $mech->get_ok('/admin');
    };

    $mech->title_like(qr/Summary/);

    $mech->content_contains( "$problem_count</strong> live problems" );
    $mech->content_contains( "$a_count confirmed alerts" );

    my $questionnaires = FixMyStreet::App->model('DB::Questionnaire')->search( { whensent => { -not => undef } } );
    my $q_count = $questionnaires->count();

    $mech->content_contains( "$q_count questionnaires sent" );

    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'oxfordshire' ],
    }, sub {
        ok $mech->host('oxfordshire.fixmystreet.com');

        $mech->get_ok('/admin');
        $mech->title_like(qr/Summary/);

        my ($num_live) = $mech->content =~ /(\d+)<\/strong> live problems/;
        my ($num_alerts) = $mech->content =~ /(\d+) confirmed alerts/;
        my ($num_qs) = $mech->content =~ /(\d+) questionnaires sent/;

        $report->bodies_str($oxfordshire->id);
        $report->cobrand('oxfordshire');
        $report->update;

        $alert->cobrand('oxfordshire');
        $alert->update;

        $mech->get_ok('/admin');

        $mech->content_contains( ($num_live+1) . "</strong> live problems" );
        $mech->content_contains( ($num_alerts+1) . " confirmed alerts" );
        $mech->content_contains( ($num_qs+1) . " questionnaires sent" );

        $report->bodies_str(2504);
        $report->cobrand('');
        $report->update;

        $alert->cobrand('');
        $alert->update;
    };

    FixMyStreet::App->model('DB::Problem')->search( { bodies_str => 1 } )->update( { bodies_str => 2489 } );
    ok $mech->host('www.fixmystreet.com');
};

# This override is wrapped around ALL the /admin/body tests
FixMyStreet::override_config {
    MAPIT_URL => 'http://mapit.uk/',
    MAPIT_TYPES => [ 'UTA' ],
    BASE_URL => 'http://www.example.org',
}, sub {

my $body = $mech->create_body_ok(2650, 'Aberdeen City Council');
$mech->get_ok('/admin/body/' . $body->id);
$mech->content_contains('Aberdeen City Council');
$mech->content_like(qr{AB\d\d});
$mech->content_contains("http://www.example.org/around");

subtest 'check contact creation' => sub {
    $mech->get_ok('/admin/body/' . $body->id);

    $mech->submit_form_ok( { with_fields => { 
        category   => 'test category',
        email      => 'test@example.com',
        note       => 'test note',
        non_public => undef,
        state => 'unconfirmed',
    } } );

    $mech->content_contains( 'test category' );
    $mech->content_contains( 'test@example.com' );
    $mech->content_contains( '<td>test note' );
    $mech->content_like( qr/<td>\s*unconfirmed\s*<\/td>/ ); # No private

    $mech->submit_form_ok( { with_fields => { 
        category   => 'private category',
        email      => 'test@example.com',
        note       => 'test note',
        non_public => 'on',
    } } );

    $mech->content_contains( 'private category' );
    $mech->content_like( qr{test\@example.com\s*</td>\s*<td>\s*confirmed\s*<br>\s*<small>\s*Private\s*</small>\s*</td>} );

    $mech->submit_form_ok( { with_fields => {
        category => 'test/category',
        email    => 'test@example.com',
        note     => 'test/note',
        non_public => 'on',
    } } );
    $mech->get_ok('/admin/body/' . $body->id . '/test/category');
    $mech->content_contains('<h1>test/category</h1>');
};

subtest 'check contact editing' => sub {
    $mech->get_ok('/admin/body/' . $body->id .'/test%20category');

    $mech->submit_form_ok( { with_fields => {
        email    => 'test2@example.com',
        note     => 'test2 note',
        non_public => undef,
    } } );

    $mech->content_contains( 'test category' );
    $mech->content_like( qr{test2\@example.com\s*</td>\s*<td>\s*unconfirmed\s*</td>} );
    $mech->content_contains( '<td>test2 note' );

    $mech->get_ok('/admin/body/' . $body->id . '/test%20category');
    $mech->submit_form_ok( { with_fields => {
        email    => 'test2@example.com, test3@example.com',
        note     => 'test3 note',
    } } );

    $mech->content_contains( 'test2@example.com,test3@example.com' );

    $mech->get_ok('/admin/body/' . $body->id . '/test%20category');
    $mech->content_contains( '<td><strong>test2@example.com,test3@example.com' );

    $mech->submit_form_ok( { with_fields => {
        email    => 'test2@example.com',
        note     => 'test2 note',
        non_public => 'on',
    } } );

    $mech->content_like( qr{test2\@example.com\s*</td>\s*<td>\s*unconfirmed\s*<br>\s*<small>\s*Private\s*</small>\s*</td>} );

    $mech->get_ok('/admin/body/' . $body->id . '/test%20category');
    $mech->content_contains( '<td><strong>test2@example.com' );
};

subtest 'check contact updating' => sub {
    $mech->get_ok('/admin/body/' . $body->id . '/test%20category');
    $mech->content_like(qr{test2\@example.com</strong>[^<]*</td>[^<]*<td>unconfirmed}s);

    $mech->get_ok('/admin/body/' . $body->id);

    $mech->form_number( 1 );
    $mech->tick( 'confirmed', 'test category' );
    $mech->submit_form_ok({form_number => 1});

    $mech->content_like(qr'test2@example.com</td>[^<]*<td>\s*confirmed's);
    $mech->get_ok('/admin/body/' . $body->id . '/test%20category');
    $mech->content_like(qr{test2\@example.com[^<]*</td>[^<]*<td><strong>confirmed}s);
};

$body->update({ send_method => undef }); 

subtest 'check open311 configuring' => sub {
    $mech->get_ok('/admin/body/' . $body->id);
    $mech->content_lacks('Council contacts configured via Open311');

    $mech->form_number(3);
    $mech->submit_form_ok(
        {
            with_fields => {
                api_key      => 'api key',
                endpoint     => 'http://example.com/open311',
                jurisdiction => 'mySociety',
                send_comments => 0,
                send_method  => 'Open311',
            }
        }
    );
    $mech->content_contains('Council contacts configured via Open311');
    $mech->content_contains('Values updated');

    my $conf = FixMyStreet::App->model('DB::Body')->find( $body->id );
    is $conf->endpoint, 'http://example.com/open311', 'endpoint configured';
    is $conf->api_key, 'api key', 'api key configured';
    is $conf->jurisdiction, 'mySociety', 'jurisdiction configures';

    $mech->form_number(3);
    $mech->submit_form_ok(
        {
            with_fields => {
                api_key      => 'new api key',
                endpoint     => 'http://example.org/open311',
                jurisdiction => 'open311',
                send_comments => 0,
                send_method  => 'Open311',
            }
        }
    );

    $mech->content_contains('Values updated');

    $conf = FixMyStreet::App->model('DB::Body')->find( $body->id );
    is $conf->endpoint, 'http://example.org/open311', 'endpoint updated';
    is $conf->api_key, 'new api key', 'api key updated';
    is $conf->jurisdiction, 'open311', 'jurisdiction configures';
};

subtest 'check text output' => sub {
    $mech->get_ok('/admin/body/' . $body->id . '?text=1');
    is $mech->content_type, 'text/plain';
    $mech->content_contains('test category');
    $mech->content_lacks('<body');
};


}; # END of override wrap


my $log_entries = FixMyStreet::App->model('DB::AdminLog')->search(
    {
        object_type => 'problem',
        object_id   => $report->id
    },
    { 
        order_by => { -desc => 'id' },
    }
);

is $log_entries->count, 0, 'no admin log entries';

my $report_id = $report->id;
ok $report, "created test report - $report_id";

foreach my $test (
    {
        description => 'edit report title',
        fields      => {
            title      => 'Report to Edit',
            detail     => 'Detail for Report to Edit',
            state      => 'confirmed',
            name       => 'Test User',
            username => $user->email,
            anonymous  => 0,
            flagged    => undef,
            non_public => undef,
        },
        changes     => { title => 'Edited Report', },
        log_entries => [qw/edit/],
        resend      => 0,
    },
    {
        description => 'edit report description',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Detail for Report to Edit',
            state      => 'confirmed',
            name       => 'Test User',
            username => $user->email,
            anonymous  => 0,
            flagged    => undef,
            non_public => undef,
        },
        changes     => { detail => 'Edited Detail', },
        log_entries => [qw/edit edit/],
        resend      => 0,
    },
    {
        description => 'edit report user name',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Test User',
            username => $user->email,
            anonymous  => 0,
            flagged    => undef,
            non_public => undef,
        },
        changes     => { name => 'Edited User', },
        log_entries => [qw/edit edit edit/],
        resend      => 0,
        user        => $user,
    },
    {
        description => 'edit report set flagged true',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Edited User',
            username => $user->email,
            anonymous  => 0,
            flagged    => undef,
            non_public => undef,
        },
        changes => {
            flagged    => 'on',
        },
        log_entries => [qw/edit edit edit edit/],
        resend      => 0,
        user        => $user,
    },
    {
        description => 'edit report user email',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Edited User',
            username => $user->email,
            anonymous  => 0,
            flagged    => 'on',
            non_public => undef,
        },
        changes     => { username => $user2->email, },
        log_entries => [qw/edit edit edit edit edit/],
        resend      => 0,
        user        => $user2,
    },
    {
        description => 'change state to unconfirmed',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Edited User',
            username => $user2->email,
            anonymous  => 0,
            flagged    => 'on',
            non_public => undef,
        },
        expect_comment => 1,
        changes   => { state => 'unconfirmed' },
        log_entries => [qw/edit state_change edit edit edit edit edit/],
        resend      => 0,
    },
    {
        description => 'change state to confirmed',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'unconfirmed',
            name       => 'Edited User',
            username => $user2->email,
            anonymous  => 0,
            flagged    => 'on',
            non_public => undef,
        },
        expect_comment => 1,
        changes   => { state => 'confirmed' },
        log_entries => [qw/edit state_change edit state_change edit edit edit edit edit/],
        resend      => 0,
    },
    {
        description => 'change state to fixed',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Edited User',
            username => $user2->email,
            anonymous  => 0,
            flagged    => 'on',
            non_public => undef,
        },
        expect_comment => 1,
        changes   => { state => 'fixed' },
        log_entries =>
          [qw/edit state_change edit state_change edit state_change edit edit edit edit edit/],
        resend => 0,
    },
    {
        description => 'change state to hidden',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'fixed',
            name       => 'Edited User',
            username => $user2->email,
            anonymous  => 0,
            flagged    => 'on',
            non_public => undef,
        },
        expect_comment => 1,
        changes     => { state => 'hidden' },
        log_entries => [
            qw/edit state_change edit state_change edit state_change edit state_change edit edit edit edit edit/
        ],
        resend => 0,
    },
    {
        description => 'edit and change state',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'hidden',
            name       => 'Edited User',
            username => $user2->email,
            anonymous  => 0,
            flagged    => 'on',
            non_public => undef,
        },
        expect_comment => 1,
        changes => {
            state     => 'confirmed',
            anonymous => 1,
        },
        log_entries => [
            qw/edit state_change edit state_change edit state_change edit state_change edit state_change edit edit edit edit edit/
        ],
        resend => 0,
    },
    {
        description => 'resend',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Edited User',
            username => $user2->email,
            anonymous  => 1,
            flagged    => 'on',
            non_public => undef,
        },
        changes     => {},
        log_entries => [
            qw/resend edit state_change edit state_change edit state_change edit state_change edit state_change edit edit edit edit edit/
        ],
        resend => 1,
    },
    {
        description => 'non public',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Edited User',
            username => $user2->email,
            anonymous  => 1,
            flagged    => 'on',
            non_public => undef,
        },
        changes     => {
            non_public => 'on',
        },
        log_entries => [
            qw/edit resend edit state_change edit state_change edit state_change edit state_change edit state_change edit edit edit edit edit/
        ],
        resend => 0,
    },
    {
        description => 'change state to investigating as body superuser',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'confirmed',
            name       => 'Edited User',
            username   => $user2->email,
            anonymous  => 1,
            flagged    => 'on',
            non_public => 'on',
        },
        expect_comment => 1,
        user_body => $oxfordshire,
        changes   => { state => 'investigating' },
        log_entries => [
            qw/edit state_change edit resend edit state_change edit state_change edit state_change edit state_change edit state_change edit edit edit edit edit/
        ],
        resend => 0,
    },
    {
        description => 'change state to in progess and change category as body superuser',
        fields      => {
            title      => 'Edited Report',
            detail     => 'Edited Detail',
            state      => 'investigating',
            name       => 'Edited User',
            username   => $user2->email,
            anonymous  => 1,
            flagged    => 'on',
            non_public => 'on',
        },
        expect_comment => 1,
        expected_text => '*Category changed from ‘Other’ to ‘Potholes’*',
        user_body => $oxfordshire,
        changes   => { state => 'in progress', category => 'Potholes' },
        log_entries => [
            qw/edit state_change edit state_change edit resend edit state_change edit state_change edit state_change edit state_change edit state_change edit edit edit edit edit/
        ],
        resend => 0,
    },
  )
{
    subtest $test->{description} => sub {
        $report->comments->delete;
        $log_entries->reset;

        if ( $test->{user_body} ) {
            $superuser->from_body( $test->{user_body}->id );
            $superuser->update;
        }

        $mech->get_ok("/admin/report_edit/$report_id");

        @{$test->{fields}}{'external_id', 'external_body', 'external_team', 'category'} = (13, "", "", "Other");
        is_deeply( $mech->visible_form_values(), $test->{fields}, 'initial form values' );

        my $new_fields = {
            %{ $test->{fields} },
            %{ $test->{changes} },
        };

        if ( $test->{resend} ) {
            $mech->click_ok( 'resend' );
        } else {
            $mech->submit_form_ok( { with_fields => $new_fields }, 'form_submitted' );
        }

        is_deeply( $mech->visible_form_values(), $new_fields, 'changed form values' );
        is $log_entries->count, scalar @{$test->{log_entries}}, 'log entry count';
        is $log_entries->next->action, $_, 'log entry added' for @{ $test->{log_entries} };

        $report->discard_changes;

        if ($report->state eq 'confirmed' && $report->whensent) {
            $mech->content_contains( 'type="submit" name="resend"', 'resend button' );
        } else {
            $mech->content_lacks( 'type="submit" name="resend"', 'no resend button' );
        }

        $test->{changes}->{flagged} = 1 if $test->{changes}->{flagged};
        $test->{changes}->{non_public} = 1 if $test->{changes}->{non_public};

        is $report->$_, $test->{changes}->{$_}, "$_ updated" for grep { $_ ne 'username' } keys %{ $test->{changes} };

        if ( $test->{user} ) {
            is $report->user->id, $test->{user}->id, 'user changed';
        }

        if ( $test->{resend} ) {
            $mech->content_contains( 'That problem will now be resent' );
            is $report->whensent, undef, 'mark report to resend';
        }

        if ( $test->{expect_comment} ) {
            my $comment = $report->comments->first;
            ok $comment, 'report status change creates comment';
            is $report->comments->count, 1, 'report only has one comment';
            if ($test->{expected_text}) {
                is $comment->text, $test->{expected_text}, 'comment has expected text';
            } else {
                is $comment->text, '', 'comment has no text';
            }
            if ( $test->{user_body} ) {
                ok $comment->get_extra_metadata('is_body_user'), 'body user metadata set';
                ok !$comment->get_extra_metadata('is_superuser'), 'superuser metadata not set';
                is $comment->name, $test->{user_body}->name, 'comment name is body name';
            } else {
                ok !$comment->get_extra_metadata('is_body_user'), 'body user metadata not set';
                ok $comment->get_extra_metadata('is_superuser'), 'superuser metadata set';
                is $comment->name, _('an adminstrator'), 'comment name is admin';
            }
        } else {
            is $report->comments->count, 0, 'report has no comments';
        }

        $superuser->from_body(undef);
        $superuser->update;
    };
}

FixMyStreet::override_config {
    ALLOWED_COBRANDS => 'fixmystreet',
}, sub {

subtest 'change report category' => sub {
    my ($ox_report) = $mech->create_problems_for_body(1, $oxfordshire->id, 'Unsure', {
        category => 'Potholes',
        areas => ',2237,2421,', # Cached used by categories_for_point...
        latitude => 51.7549262252,
        longitude => -1.25617899435,
        whensent => \'current_timestamp',
    });
    $mech->get_ok("/admin/report_edit/" . $ox_report->id);

    $mech->submit_form_ok( { with_fields => { category => 'Traffic lights' } }, 'form_submitted' );
    $ox_report->discard_changes;
    is $ox_report->category, 'Traffic lights';
    isnt $ox_report->whensent, undef;
    is $ox_report->comments->count, 1, "Comment created for update";
    is $ox_report->comments->first->text, '*Category changed from ‘Potholes’ to ‘Traffic lights’*', 'Comment text correct';

    $mech->submit_form_ok( { with_fields => { category => 'Graffiti' } }, 'form_submitted' );
    $ox_report->discard_changes;
    is $ox_report->category, 'Graffiti';
    is $ox_report->whensent, undef;
};

};

subtest 'change email to new user' => sub {
    $log_entries->delete;
    $mech->get_ok("/admin/report_edit/$report_id");
    my $fields = {
        title  => $report->title,
        detail => $report->detail,
        state  => $report->state,
        name   => $report->name,
        username => $report->user->email,
        category => 'Potholes',
        anonymous => 1,
        flagged => 'on',
        non_public => 'on',
        external_id => '13',
        external_body => '',
        external_team => '',
    };

    is_deeply( $mech->visible_form_values(), $fields, 'initial form values' );

    my $changes = {
        username => 'test3@example.com'
    };

    $user3 = FixMyStreet::App->model('DB::User')->find( { email => 'test3@example.com' } );

    ok !$user3, 'user not in database';

    my $new_fields = {
        %{ $fields },
        %{ $changes },
    };

    $mech->submit_form_ok(
        {
            with_fields => $new_fields,
        }
    );

    is $log_entries->count, 1, 'created admin log entries';
    is $log_entries->first->action, 'edit', 'log action';
    is_deeply( $mech->visible_form_values(), $new_fields, 'changed form values' );

    $user3 = FixMyStreet::App->model('DB::User')->find( { email => 'test3@example.com' } );

    $report->discard_changes;

    ok $user3, 'new user created';
    is $report->user_id, $user3->id, 'user changed to new user';
};

subtest 'adding email to abuse list from report page' => sub {
    my $email = $report->user->email;

    my $abuse = FixMyStreet::App->model('DB::Abuse')->find( { email => $email } );
    $abuse->delete if $abuse;

    $mech->get_ok( '/admin/report_edit/' . $report->id );
    $mech->content_contains('Ban user');

    $mech->click_ok('banuser');

    $mech->content_contains('User added to abuse list');
    $mech->content_contains('<small>User in abuse table</small>');

    $abuse = FixMyStreet::App->model('DB::Abuse')->find( { email => $email } );
    ok $abuse, 'entry created in abuse table';

    $mech->get_ok( '/admin/report_edit/' . $report->id );
    $mech->content_contains('<small>User in abuse table</small>');
};

subtest 'remove user from abuse list from edit user page' => sub {
    my $abuse = FixMyStreet::App->model('DB::Abuse')->find_or_create( { email => $user->email } );
    $mech->get_ok( '/admin/user_edit/' . $user->id );
    $mech->content_contains('User in abuse table');

    $mech->click_ok('unban');

    $abuse = FixMyStreet::App->model('DB::Abuse')->find( { email => $user->email } );
    ok !$abuse, 'record removed from abuse table';
};

subtest 'remove user with phone account from abuse list from edit user page' => sub {
    my $abuse_user = $mech->create_user_ok('01234 456789');
    my $abuse = FixMyStreet::App->model('DB::Abuse')->find_or_create( { email => $abuse_user->phone } );
    $mech->get_ok( '/admin/user_edit/' . $abuse_user->id );
    $mech->content_contains('User in abuse table');
    my $abuse_found = FixMyStreet::App->model('DB::Abuse')->find( { email => $abuse_user->phone } );
    ok $abuse_found, 'user in abuse table';

    $mech->click_ok('unban');

    $abuse = FixMyStreet::App->model('DB::Abuse')->find( { email => $user->phone } );
    ok !$abuse, 'record removed from abuse table';
};

subtest 'no option to remove user already in abuse list' => sub {
    my $abuse = FixMyStreet::App->model('DB::Abuse')->find( { email => $user->email } );
    $abuse->delete if $abuse;
    $mech->get_ok( '/admin/user_edit/' . $user->id );
    $mech->content_lacks('User in abuse table');
};

subtest 'flagging user from report page' => sub {
    $report->user->flagged(0);
    $report->user->update;

    $mech->get_ok( '/admin/report_edit/' . $report->id );
    $mech->content_contains('Flag user');

    $mech->click_ok('flaguser');

    $mech->content_contains('User flagged');
    $mech->content_contains('Remove flag');

    $report->discard_changes;
    ok $report->user->flagged, 'user flagged';

    $mech->get_ok( '/admin/report_edit/' . $report->id );
    $mech->content_contains('Remove flag');
};

subtest 'unflagging user from report page' => sub {
    $report->user->flagged(1);
    $report->user->update;

    $mech->get_ok( '/admin/report_edit/' . $report->id );
    $mech->content_contains('Remove flag');

    $mech->click_ok('removeuserflag');

    $mech->content_contains('User flag removed');
    $mech->content_contains('Flag user');

    $report->discard_changes;
    ok !$report->user->flagged, 'user not flagged';

    $mech->get_ok( '/admin/report_edit/' . $report->id );
    $mech->content_contains('Flag user');
};

$log_entries->delete;

my $update = FixMyStreet::App->model('DB::Comment')->create(
    {
        text => 'this is an update',
        user => $user,
        state => 'confirmed',
        problem => $report,
        mark_fixed => 0,
        anonymous => 1,
    }
);

$log_entries = FixMyStreet::App->model('DB::AdminLog')->search(
    {
        object_type => 'update',
        object_id   => $update->id
    },
    { 
        order_by => { -desc => 'id' },
    }
);

is $log_entries->count, 0, 'no admin log entries';

for my $test (
    {
        desc => 'edit update text',
        fields => {
            text => 'this is an update',
            state => 'confirmed',
            name => '',
            anonymous => 1,
            username => 'test@example.com',
        },
        changes => {
            text => 'this is a changed update',
        },
        log_count => 1,
        log_entries => [qw/edit/],
    },
    {
        desc => 'edit update name',
        fields => {
            text => 'this is a changed update',
            state => 'confirmed',
            name => '',
            anonymous => 1,
            username => 'test@example.com',
        },
        changes => {
            name => 'A User',
        },
        log_count => 2,
        log_entries => [qw/edit edit/],
    },
    {
        desc => 'edit update anonymous',
        fields => {
            text => 'this is a changed update',
            state => 'confirmed',
            name => 'A User',
            anonymous => 1,
            username => 'test@example.com',
        },
        changes => {
            anonymous => 0,
        },
        log_count => 3,
        log_entries => [qw/edit edit edit/],
    },
    {
        desc => 'edit update user',
        fields => {
            text => 'this is a changed update',
            state => 'confirmed',
            name => 'A User',
            anonymous => 0,
            username => 'test@example.com',
        },
        changes => {
            username => 'test2@example.com',
        },
        log_count => 4,
        log_entries => [qw/edit edit edit edit/],
        user => $user2,
    },
    {
        desc => 'edit update state',
        fields => {
            text => 'this is a changed update',
            state => 'confirmed',
            name => 'A User',
            anonymous => 0,
            username => 'test2@example.com',
        },
        changes => {
            state => 'unconfirmed',
        },
        log_count => 5,
        log_entries => [qw/state_change edit edit edit edit/],
    },
    {
        desc => 'edit update state and text',
        fields => {
            text => 'this is a changed update',
            state => 'unconfirmed',
            name => 'A User',
            anonymous => 0,
            username => 'test2@example.com',
        },
        changes => {
            text => 'this is a twice changed update',
            state => 'confirmed',
        },
        log_count => 7,
        log_entries => [qw/edit state_change state_change edit edit edit edit/],
    },
) {
    subtest $test->{desc} => sub {
        $log_entries->reset;
        $mech->get_ok('/admin/update_edit/' . $update->id );

        is_deeply $mech->visible_form_values, $test->{fields}, 'initial form values';

        my $to_submit = {
            %{ $test->{fields} },
            %{ $test->{changes} }
        };

        $mech->submit_form_ok( { with_fields => $to_submit } );

        is_deeply $mech->visible_form_values, $to_submit, 'submitted form values';

        is $log_entries->count, $test->{log_count}, 'number of log entries';
        is $log_entries->next->action, $_, 'log action' for @{ $test->{log_entries} };

        $update->discard_changes;

        is $update->$_, $test->{changes}->{$_} for grep { $_ ne 'username' } keys %{ $test->{changes} };
        if ( $test->{changes}{state} && $test->{changes}{state} eq 'confirmed' ) {
            isnt $update->confirmed, undef;
        }

        if ( $test->{user} ) {
            is $update->user->id, $test->{user}->id, 'update user';
        }
    };
}

my $westminster = $mech->create_body_ok(2504, 'Westminster City Council');
$report->bodies_str($westminster->id);
$report->update;

for my $test (
    {
        desc          => 'user is problem owner',
        problem_user  => $user,
        update_user   => $user,
        update_fixed  => 0,
        update_reopen => 0,
        update_state  => undef,
        user_body     => undef,
        content       => 'user is problem owner',
    },
    {
        desc          => 'user is body user',
        problem_user  => $user,
        update_user   => $user2,
        update_fixed  => 0,
        update_reopen => 0,
        update_state  => undef,
        user_body     => $westminster->id,
        content       => 'user is from same council as problem - ' . $westminster->id,
    },
    {
        desc          => 'update changed problem state',
        problem_user  => $user,
        update_user   => $user2,
        update_fixed  => 0,
        update_reopen => 0,
        update_state  => 'planned',
        user_body     => $westminster->id,
        content       => 'Update changed problem state to planned',
    },
    {
        desc          => 'update marked problem as fixed',
        problem_user  => $user,
        update_user   => $user3,
        update_fixed  => 1,
        update_reopen => 0,
        update_state  => undef,
        user_body     => undef,
        content       => 'Update marked problem as fixed',
    },
    {
        desc          => 'update reopened problem',
        problem_user  => $user,
        update_user   => $user,
        update_fixed  => 0,
        update_reopen => 1,
        update_state  => undef,
        user_body     => undef,
        content       => 'Update reopened problem',
    },
) {
    subtest $test->{desc} => sub {
        $report->user( $test->{problem_user} );
        $report->update;

        $update->user( $test->{update_user} );
        $update->problem_state( $test->{update_state} );
        $update->mark_fixed( $test->{update_fixed} );
        $update->mark_open( $test->{update_reopen} );
        $update->update;

        $test->{update_user}->from_body( $test->{user_body} );
        $test->{update_user}->update;

        $mech->get_ok('/admin/update_edit/' . $update->id );
        $mech->content_contains( $test->{content} );
    };
}

subtest 'editing update email creates new user if required' => sub {
    my $user = FixMyStreet::App->model('DB::User')->find( { email => 'test4@example.com' } );

    $user->delete if $user;

    my $fields = {
            text => 'this is a changed update',
            state => 'hidden',
            name => 'A User',
            anonymous => 0,
            username => 'test4@example.com',
    };

    $mech->submit_form_ok( { with_fields => $fields } );

    $user = FixMyStreet::App->model('DB::User')->find( { email => 'test4@example.com' } );

    is_deeply $mech->visible_form_values, $fields, 'submitted form values';

    ok $user, 'new user created';

    $update->discard_changes;
    is $update->user->id, $user->id, 'update set to new user';
};

subtest 'adding email to abuse list from update page' => sub {
    my $email = $update->user->email;

    my $abuse = FixMyStreet::App->model('DB::Abuse')->find( { email => $email } );
    $abuse->delete if $abuse;

    $mech->get_ok( '/admin/update_edit/' . $update->id );
    $mech->content_contains('Ban user');

    $mech->click_ok('banuser');

    $mech->content_contains('User added to abuse list');
    $mech->content_contains('<small>User in abuse table</small>');

    $abuse = FixMyStreet::App->model('DB::Abuse')->find( { email => $email } );
    ok $abuse, 'entry created in abuse table';

    $mech->get_ok( '/admin/update_edit/' . $update->id );
    $mech->content_contains('<small>User in abuse table</small>');
};

subtest 'flagging user from update page' => sub {
    $update->user->flagged(0);
    $update->user->update;

    $mech->get_ok( '/admin/update_edit/' . $update->id );
    $mech->content_contains('Flag user');

    $mech->click_ok('flaguser');

    $mech->content_contains('User flagged');
    $mech->content_contains('Remove flag');

    $update->discard_changes;
    ok $update->user->flagged, 'user flagged';

    $mech->get_ok( '/admin/update_edit/' . $update->id );
    $mech->content_contains('Remove flag');
};

subtest 'unflagging user from update page' => sub {
    $update->user->flagged(1);
    $update->user->update;

    $mech->get_ok( '/admin/update_edit/' . $update->id );
    $mech->content_contains('Remove flag');

    $mech->click_ok('removeuserflag');

    $mech->content_contains('User flag removed');
    $mech->content_contains('Flag user');

    $update->discard_changes;
    ok !$update->user->flagged, 'user not flagged';

    $mech->get_ok( '/admin/update_edit/' . $update->id );
    $mech->content_contains('Flag user');
};

subtest 'hiding comment marked as fixed reopens report' => sub {
    $update->mark_fixed( 1 );
    $update->update;

    $report->state('fixed - user');
    $report->update;

    my $fields = {
            text => 'this is a changed update',
            state => 'hidden',
            name => 'A User',
            anonymous => 0,
            username => 'test2@example.com',
    };

    $mech->submit_form_ok( { with_fields => $fields } );

    $report->discard_changes;
    is $report->state, 'confirmed', 'report reopened';
    $mech->content_contains('Problem marked as open');
};

$log_entries->delete;

subtest 'report search' => sub {
    $update->state('confirmed');
    $update->user($report->user);
    $update->update;

    $mech->get_ok('/admin/reports');
    $mech->get_ok('/admin/reports?search=' . $report->id );

    $mech->content_contains( $report->title );
    my $r_id = $report->id;
    $mech->content_like( qr{href="http://[^/]*[^.]/report/$r_id"[^>]*>$r_id</a>} );

    $mech->get_ok('/admin/reports?search=' . $report->external_id);
    $mech->content_like( qr{href="http://[^/]*[^.]/report/$r_id"[^>]*>$r_id</a>} );

    $mech->get_ok('/admin/reports?search=ref:' . $report->external_id);
    $mech->content_like( qr{href="http://[^/]*[^.]/report/$r_id"[^>]*>$r_id</a>} );

    $mech->get_ok('/admin/reports?search=' . $report->user->email);

    my $u_id = $update->id;
    $mech->content_like( qr{href="http://[^/]*[^.]/report/$r_id"[^>]*>$r_id</a>} );
    $mech->content_like( qr{href="http://[^/]*[^.]/report/$r_id#update_$u_id"[^>]*>$u_id</a>} );

    $update->state('hidden');
    $update->update;

    $mech->get_ok('/admin/reports?search=' . $report->user->email);
    $mech->content_like( qr{<tr [^>]*hidden[^>]*> \s* <td> \s* $u_id \s* </td>}xs );

    $report->state('hidden');
    $report->update;

    $mech->get_ok('/admin/reports?search=' . $report->user->email);
    $mech->content_like( qr{<tr [^>]*hidden[^>]*> \s* <td[^>]*> \s* $r_id \s* </td>}xs );

    $report->state('fixed - user');
    $report->update;

    $mech->get_ok('/admin/reports?search=' . $report->user->email);
    $mech->content_like( qr{href="http://[^/]*[^.]/report/$r_id"[^>]*>$r_id</a>} );
};

subtest 'search abuse' => sub {
    $mech->get_ok( '/admin/users?search=example' );
    $mech->content_like(qr{test4\@example.com.*</td>\s*<td>.*?</td>\s*<td>User in abuse table}s);
};

subtest 'show flagged entries' => sub {
    $report->flagged( 1 );
    $report->update;

    $user->flagged( 1 );
    $user->update;

    $mech->get_ok('/admin/flagged');
    $mech->content_contains( $report->title );
    $mech->content_contains( $user->email );
};

my $haringey = $mech->create_body_ok(2509, 'Haringey Borough Council');

subtest 'user search' => sub {
    $mech->get_ok('/admin/users');
    $mech->get_ok('/admin/users?search=' . $user->name);

    $mech->content_contains( $user->name);
    my $u_id = $user->id;
    $mech->content_like( qr{user_edit/$u_id">Edit</a>} );

    $mech->get_ok('/admin/users?search=' . $user->email);

    $mech->content_like( qr{user_edit/$u_id">Edit</a>} );

    $user->from_body($haringey->id);
    $user->update;
    $mech->get_ok('/admin/users?search=' . $haringey->id );
    $mech->content_contains('Haringey');
};

subtest 'search does not show user from another council' => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'oxfordshire' ],
    }, sub {
        $mech->get_ok('/admin/users');
        $mech->get_ok('/admin/users?search=' . $user->name);

        $mech->content_contains( "Searching found no users." );

        $mech->get_ok('/admin/users?search=' . $user->email);
        $mech->content_contains( "Searching found no users." );
    };
};

subtest 'user_edit does not show user from another council' => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'oxfordshire' ],
    }, sub {
        $mech->get('/admin/user_edit/' . $user->id);
        ok !$mech->res->is_success(), "want a bad response";
        is $mech->res->code, 404, "got 404";
    };
};

$log_entries = FixMyStreet::App->model('DB::AdminLog')->search(
    {
        object_type => 'user',
        object_id   => $user->id
    },
    { 
        order_by => { -desc => 'id' },
    }
);

is $log_entries->count, 0, 'no admin log entries';

$user->flagged( 0 );
$user->update;

my $southend = $mech->create_body_ok(2607, 'Southend-on-Sea Borough Council');

for my $test (
    {
        desc => 'add user - blank form',
        fields => {
            email => '', email_verified => 0,
            phone => '', phone_verified => 0,
        },
        error => ['Please verify at least one of email/phone', 'Please enter a name'],
    },
    {
        desc => 'add user - blank, verify phone',
        fields => {
            email => '', email_verified => 0,
            phone => '', phone_verified => 1,
        },
        error => ['Please enter a valid email or phone number', 'Please enter a name'],
    },
    {
        desc => 'add user - bad email',
        fields => {
            name => 'Norman',
            email => 'bademail', email_verified => 0,
            phone => '', phone_verified => 0,
        },
        error => ['Please enter a valid email'],
    },
    {
        desc => 'add user - bad phone',
        fields => {
            name => 'Norman',
            phone => '01214960000000', phone_verified => 1,
        },
         error => ['Please check your phone number is correct'],
    },
    {
        desc => 'add user - landline',
        fields => {
            name => 'Norman Name',
            phone => '+441214960000',
            phone_verified => 1,
        },
        error => ['Please enter a mobile number'],
    },
    {
        desc => 'add user - good details',
        fields => {
            name => 'Norman Name',
            phone => '+61491570156',
            phone_verified => 1,
        },
    },
) {
    subtest $test->{desc} => sub {
        $mech->get_ok('/admin/users');
        $mech->submit_form_ok( { with_fields => $test->{fields} } );
        if ($test->{error}) {
            $mech->content_contains($_) for @{$test->{error}};
        } else {
            $mech->content_contains('Updated');
        }
    };
}

my %default_perms = (
    "permissions[moderate]" => undef,
    "permissions[planned_reports]" => undef,
    "permissions[report_edit]" => undef,
    "permissions[report_edit_category]" => undef,
    "permissions[report_edit_priority]" => undef,
    "permissions[report_inspect]" => undef,
    "permissions[report_instruct]" => undef,
    "permissions[contribute_as_another_user]" => undef,
    "permissions[contribute_as_anonymous_user]" => undef,
    "permissions[contribute_as_body]" => undef,
    "permissions[view_body_contribute_details]" => undef,
    "permissions[user_edit]" => undef,
    "permissions[user_manage_permissions]" => undef,
    "permissions[user_assign_body]" => undef,
    "permissions[user_assign_areas]" => undef,
    "permissions[template_edit]" => undef,
    "permissions[responsepriority_edit]" => undef,
    "permissions[category_edit]" => undef,
    trusted_bodies => undef,
);

# Start this section with user having no name
# Regression test for mysociety/fixmystreetforcouncils#250
$user->update({ name => '' });

FixMyStreet::override_config {
    MAPIT_URL => 'http://mapit.uk/',
}, sub {
    for my $test (
        {
            desc => 'edit user name',
            fields => {
                name => '',
                email => 'test@example.com',
                body => $haringey->id,
                phone => '',
                flagged => undef,
                is_superuser => undef,
                area_id => '',
                %default_perms,
            },
            changes => {
                name => 'Changed User',
            },
            log_count => 1,
            log_entries => [qw/edit/],
        },
        {
            desc => 'edit user email',
            fields => {
                name => 'Changed User',
                email => 'test@example.com',
                body => $haringey->id,
                phone => '',
                flagged => undef,
                is_superuser => undef,
                area_id => '',
                %default_perms,
            },
            changes => {
                email => 'changed@example.com',
            },
            log_count => 2,
            log_entries => [qw/edit edit/],
        },
        {
            desc => 'edit user body',
            fields => {
                name => 'Changed User',
                email => 'changed@example.com',
                body => $haringey->id,
                phone => '',
                flagged => undef,
                is_superuser => undef,
                area_id => '',
                %default_perms,
            },
            changes => {
                body => $southend->id,
            },
            log_count => 3,
            log_entries => [qw/edit edit edit/],
        },
        {
            desc => 'edit user flagged',
            fields => {
                name => 'Changed User',
                email => 'changed@example.com',
                body => $southend->id,
                phone => '',
                flagged => undef,
                is_superuser => undef,
                area_id => '',
                %default_perms,
            },
            changes => {
                flagged => 'on',
            },
            log_count => 4,
            log_entries => [qw/edit edit edit edit/],
        },
        {
            desc => 'edit user remove flagged',
            fields => {
                name => 'Changed User',
                email => 'changed@example.com',
                body => $southend->id,
                phone => '',
                flagged => 'on',
                is_superuser => undef,
                area_id => '',
                %default_perms,
            },
            changes => {
                flagged => undef,
            },
            log_count => 4,
            log_entries => [qw/edit edit edit edit/],
        },
        {
            desc => 'edit user add is_superuser',
            fields => {
                name => 'Changed User',
                email => 'changed@example.com',
                body => $southend->id,
                phone => '',
                flagged => undef,
                is_superuser => undef,
                area_id => '',
                %default_perms,
            },
            changes => {
                is_superuser => 'on',
            },
            removed => [
                keys %default_perms,
            ],
            log_count => 5,
            log_entries => [qw/edit edit edit edit edit/],
        },
        {
            desc => 'edit user remove is_superuser',
            fields => {
                name => 'Changed User',
                email => 'changed@example.com',
                body => $southend->id,
                phone => '',
                flagged => undef,
                is_superuser => 'on',
                area_id => '',
            },
            changes => {
                is_superuser => undef,
            },
            added => {
                %default_perms,
            },
            log_count => 5,
            log_entries => [qw/edit edit edit edit edit/],
        },
    ) {
        subtest $test->{desc} => sub {
            $mech->get_ok( '/admin/user_edit/' . $user->id );

            my $visible = $mech->visible_form_values;
            is_deeply $visible, $test->{fields}, 'expected user';

            my $expected = {
                %{ $test->{fields} },
                %{ $test->{changes} }
            };

            $mech->submit_form_ok( { with_fields => $expected } );

            # Some actions cause visible fields to be added/removed
            foreach my $x (@{ $test->{removed} }) {
                delete $expected->{$x};
            }
            if ( $test->{added} ) {
                $expected = {
                    %$expected,
                    %{ $test->{added} }
                };
            }

            $visible = $mech->visible_form_values;
            is_deeply $visible, $expected, 'user updated';

            $mech->content_contains( 'Updated!' );
        };
    }
};

FixMyStreet::override_config {
    MAPIT_URL => 'http://mapit.uk/',
    SMS_AUTHENTICATION => 1,
}, sub {
    subtest "Test edit user add verified phone" => sub {
        $mech->get_ok( '/admin/user_edit/' . $user->id );
        $mech->submit_form_ok( { with_fields => {
            phone => '+61491570157',
            phone_verified => 1,
        } } );
        $mech->content_contains( 'Updated!' );
    };

    subtest "Test changing user to an existing one" => sub {
        my $existing_user = $mech->create_user_ok('existing@example.com', name => 'Existing User');
        $mech->create_problems_for_body(2, 2514, 'Title', { user => $existing_user });
        my $count = FixMyStreet::DB->resultset('Problem')->search({ user_id => $user->id })->count;
        $mech->get_ok( '/admin/user_edit/' . $user->id );
        $mech->submit_form_ok( { with_fields => { email => 'existing@example.com' } }, 'submit email change' );
        is $mech->uri->path, '/admin/user_edit/' . $existing_user->id, 'redirected';
        my $p = FixMyStreet::DB->resultset('Problem')->search({ user_id => $existing_user->id })->count;
        is $p, $count + 2, 'reports merged';
    };

};

subtest "Test setting a report from unconfirmed to something else doesn't cause a front end error" => sub {
    $report->update( { confirmed => undef, state => 'unconfirmed', non_public => 0 } );
    $mech->get_ok("/admin/report_edit/$report_id");
    $mech->submit_form_ok( { with_fields => { state => 'investigating' } } );
    $report->discard_changes;
    ok( $report->confirmed, 'report has a confirmed timestamp' );
    $mech->get_ok("/report/$report_id");
};

subtest "Check admin_base_url" => sub {
    my $rs = FixMyStreet::App->model('DB::Problem');
    my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker($report->cobrand)->new();

    is ($report->admin_url($cobrand),
        (sprintf 'http://www.example.org/admin/report_edit/%d', $report_id),
        'get_admin_url OK');
};

# Finished with the superuser tests
$mech->log_out_ok;

subtest "Users without from_body can't access admin" => sub {
    $user = FixMyStreet::App->model('DB::User')->find( { email => 'existing@example.com' } );
    $user->from_body( undef );
    $user->update;

    $mech->log_in_ok( $user->email );

    ok $mech->get('/admin');
    is $mech->res->code, 403, "got 403";

    $mech->log_out_ok;
};

subtest "Users with from_body can access their own council's admin" => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'oxfordshire' ],
    }, sub {
        $mech->log_in_ok( $oxfordshireuser->email );

        $mech->get_ok('/admin');
        $mech->content_contains( 'FixMyStreet admin:' );

        $mech->log_out_ok;
    };
};

subtest "Users with from_body can't access another council's admin" => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'bristol' ],
    }, sub {
        $mech->log_in_ok( $oxfordshireuser->email );

        ok $mech->get('/admin');
        is $mech->res->code, 403, "got 403";

        $mech->log_out_ok;
    };
};

subtest "Users with from_body can't access fixmystreet.com admin" => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'fixmystreet' ],
    }, sub {
        $mech->log_in_ok( $oxfordshireuser->email );

        ok $mech->get('/admin');
        is $mech->res->code, 403, "got 403";

        $mech->log_out_ok;
    };
};

subtest "response templates can be added" => sub {
    is $oxfordshire->response_templates->count, 0, "No response templates yet";
    $mech->log_in_ok( $superuser->email );
    $mech->get_ok( "/admin/templates/" . $oxfordshire->id . "/new" );

    my $fields = {
        title => "Report acknowledgement",
        text => "Thank you for your report. We will respond shortly.",
        auto_response => undef,
        "contacts[".$oxfordshirecontact->id."]" => 1,
    };
    $mech->submit_form_ok( { with_fields => $fields } );

     is $oxfordshire->response_templates->count, 1, "Response template was added";
};

subtest "response templates are included on page" => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'oxfordshire' ],
    }, sub {
        $report->update({ category => $oxfordshirecontact->category, bodies_str => $oxfordshire->id });
        $mech->log_in_ok( $oxfordshireuser->email );

        $mech->get_ok("/report/" . $report->id);
        $mech->content_contains( $oxfordshire->response_templates->first->text );

        $mech->log_out_ok;
    };
};

subtest "auto-response templates that duplicate a single category can't be added" => sub {
    $mech->delete_response_template($_) for $oxfordshire->response_templates;
    my $template = $oxfordshire->response_templates->create({
        title => "Report fixed - potholes",
        text => "Thank you for your report. This problem has been fixed.",
        auto_response => 1,
        state => 'fixed - council',
    });
    $template->contact_response_templates->find_or_create({
        contact_id => $oxfordshirecontact->id,
    });
    is $oxfordshire->response_templates->count, 1, "Initial response template was created";


    $mech->log_in_ok( $superuser->email );
    $mech->get_ok( "/admin/templates/" . $oxfordshire->id . "/new" );

    # This response template has the same category & state as an existing one
    # so won't be allowed.
    my $fields = {
        title => "Report marked fixed - potholes",
        text => "Thank you for your report. This pothole has been fixed.",
        auto_response => 'on',
        state => 'fixed - council',
        "contacts[".$oxfordshirecontact->id."]" => 1,
    };
    $mech->submit_form_ok( { with_fields => $fields } );
    is $mech->uri->path, '/admin/templates/' . $oxfordshire->id . '/new', 'not redirected';
    $mech->content_contains( 'Please correct the errors below' );
    $mech->content_contains( 'There is already an auto-response template for this category/state.' );

    is $oxfordshire->response_templates->count, 1, "Duplicate response template wasn't added";
};

subtest "auto-response templates that duplicate all categories can't be added" => sub {
    $mech->delete_response_template($_) for $oxfordshire->response_templates;
    $oxfordshire->response_templates->create({
        title => "Report investigating - all cats",
        text => "Thank you for your report. This problem has been fixed.",
        auto_response => 1,
        state => 'fixed - council',
    });
    is $oxfordshire->response_templates->count, 1, "Initial response template was created";


    $mech->log_in_ok( $superuser->email );
    $mech->get_ok( "/admin/templates/" . $oxfordshire->id . "/new" );

    # There's already a response template for all categories and this state, so
    # this new template won't be allowed.
    my $fields = {
        title => "Report investigating - single cat",
        text => "Thank you for your report. This problem has been fixed.",
        auto_response => 'on',
        state => 'fixed - council',
        "contacts[".$oxfordshirecontact->id."]" => 1,
    };
    $mech->submit_form_ok( { with_fields => $fields } );
    is $mech->uri->path, '/admin/templates/' . $oxfordshire->id . '/new', 'not redirected';
    $mech->content_contains( 'Please correct the errors below' );
    $mech->content_contains( 'There is already an auto-response template for this category/state.' );


    is $oxfordshire->response_templates->count, 1, "Duplicate response template wasn't added";
};

subtest "all-category auto-response templates that duplicate a single category can't be added" => sub {
    $mech->delete_response_template($_) for $oxfordshire->response_templates;
    my $template = $oxfordshire->response_templates->create({
        title => "Report fixed - potholes",
        text => "Thank you for your report. This problem has been fixed.",
        auto_response => 1,
        state => 'fixed - council',
    });
    $template->contact_response_templates->find_or_create({
        contact_id => $oxfordshirecontact->id,
    });
    is $oxfordshire->response_templates->count, 1, "Initial response template was created";


    $mech->log_in_ok( $superuser->email );
    $mech->get_ok( "/admin/templates/" . $oxfordshire->id . "/new" );

    # This response template is implicitly for all categories, but there's
    # already a template for a specific category in this state, so it won't be
    # allowed.
    my $fields = {
        title => "Report marked fixed - all cats",
        text => "Thank you for your report. This problem has been fixed.",
        auto_response => 'on',
        state => 'fixed - council',
    };
    $mech->submit_form_ok( { with_fields => $fields } );
    is $mech->uri->path, '/admin/templates/' . $oxfordshire->id . '/new', 'not redirected';
    $mech->content_contains( 'Please correct the errors below' );
    $mech->content_contains( 'There is already an auto-response template for this category/state.' );

    is $oxfordshire->response_templates->count, 1, "Duplicate response template wasn't added";
};



$mech->log_in_ok( $superuser->email );

subtest "response priorities can be added" => sub {
    is $oxfordshire->response_priorities->count, 0, "No response priorities yet";
    $mech->get_ok( "/admin/responsepriorities/" . $oxfordshire->id . "/new" );

    my $fields = {
        name => "Cat 1A",
        description => "Fixed within 24 hours",
        deleted => undef,
        is_default => undef,
        "contacts[".$oxfordshirecontact->id."]" => 1,
    };
    $mech->submit_form_ok( { with_fields => $fields } );

     is $oxfordshire->response_priorities->count, 1, "Response priority was added to body";
     is $oxfordshirecontact->response_priorities->count, 1, "Response priority was added to contact";
};

subtest "response priorities can set to default" => sub {
    my $priority_id = $oxfordshire->response_priorities->first->id;
    is $oxfordshire->response_priorities->count, 1, "Response priority exists";
    $mech->get_ok( "/admin/responsepriorities/" . $oxfordshire->id . "/$priority_id" );

    my $fields = {
        name => "Cat 1A",
        description => "Fixed within 24 hours",
        deleted => undef,
        is_default => 1,
        "contacts[".$oxfordshirecontact->id."]" => 1,
    };
    $mech->submit_form_ok( { with_fields => $fields } );

     is $oxfordshire->response_priorities->count, 1, "Still one response priority";
     is $oxfordshirecontact->response_priorities->count, 1, "Still one response priority";
     ok $oxfordshire->response_priorities->first->is_default, "Response priority set to default";
};

subtest "response priorities can be listed" => sub {
    $mech->get_ok( "/admin/responsepriorities/" . $oxfordshire->id );

    $mech->content_contains( $oxfordshire->response_priorities->first->name );
    $mech->content_contains( $oxfordshire->response_priorities->first->description );
};

subtest "response priorities are limited by body" => sub {
    my $bromleypriority = $bromley->response_priorities->create( {
        deleted => 0,
        name => "Bromley Cat 0",
    } );

     is $bromley->response_priorities->count, 1, "Response priority was added to Bromley";
     is $oxfordshire->response_priorities->count, 1, "Response priority wasn't added to Oxfordshire";

     $mech->get_ok( "/admin/responsepriorities/" . $oxfordshire->id );
     $mech->content_lacks( $bromleypriority->name );

     $mech->get_ok( "/admin/responsepriorities/" . $bromley->id );
     $mech->content_contains( $bromleypriority->name );
};

$mech->log_out_ok;

subtest "response priorities can't be viewed across councils" => sub {
    FixMyStreet::override_config {
        ALLOWED_COBRANDS => [ 'oxfordshire' ],
    }, sub {
        $oxfordshireuser->user_body_permissions->create({
            body => $oxfordshire,
            permission_type => 'responsepriority_edit',
        });
        $mech->log_in_ok( $oxfordshireuser->email );
        $mech->get_ok( "/admin/responsepriorities/" . $oxfordshire->id );
        $mech->content_contains( $oxfordshire->response_priorities->first->name );


        $mech->get( "/admin/responsepriorities/" . $bromley->id );
        ok !$mech->res->is_success(), "want a bad response";
        is $mech->res->code, 404, "got 404";

        my $bromley_priority_id = $bromley->response_priorities->first->id;
        $mech->get( "/admin/responsepriorities/" . $bromley->id . "/" . $bromley_priority_id );
        ok !$mech->res->is_success(), "want a bad response";
        is $mech->res->code, 404, "got 404";
    };
};

done_testing();
