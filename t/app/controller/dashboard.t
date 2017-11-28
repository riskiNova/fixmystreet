use strict;
use warnings;

use FixMyStreet::TestMech;
use Web::Scraper;

my $mech = FixMyStreet::TestMech->new;

my $other_body = $mech->create_body_ok(1234, 'Some Other Council');
my $body = $mech->create_body_ok(2651, 'City of Edinburgh Council');
my @cats = ('Litter', 'Other', 'Potholes', 'Traffic lights');
for my $contact ( @cats ) {
    $mech->create_contact_ok(body_id => $body->id, category => $contact, email => "$contact\@example.org");
}

my $superuser = $mech->create_user_ok('superuser@example.com', name => 'Super User', is_superuser => 1);
my $counciluser = $mech->create_user_ok('counciluser@example.com', name => 'Council User', from_body => $body);
my $normaluser = $mech->create_user_ok('normaluser@example.com', name => 'Normal User');

my $body_id = $body->id;
my $area_id = '60705';
my $alt_area_id = '62883';

$mech->create_problems_for_body(2, $body->id, 'Title', { areas => ",$area_id,2651,", category => 'Potholes', cobrand => 'fixmystreet' });
$mech->create_problems_for_body(3, $body->id, 'Title', { areas => ",$area_id,2651,", category => 'Traffic lights', cobrand => 'fixmystreet' });
$mech->create_problems_for_body(1, $body->id, 'Title', { areas => ",$alt_area_id,2651,", category => 'Litter', cobrand => 'fixmystreet' });

my @scheduled_problems = $mech->create_problems_for_body(7, $body->id, 'Title', { areas => ",$area_id,2651,", category => 'Traffic lights', cobrand => 'fixmystreet' });
my @fixed_problems = $mech->create_problems_for_body(4, $body->id, 'Title', { areas => ",$area_id,2651,", category => 'Potholes', cobrand => 'fixmystreet' });
my @closed_problems = $mech->create_problems_for_body(3, $body->id, 'Title', { areas => ",$area_id,2651,", category => 'Traffic lights', cobrand => 'fixmystreet' });

foreach my $problem (@scheduled_problems) {
    $problem->update({ state => 'action scheduled' });
    $mech->create_comment_for_problem($problem, $counciluser, 'Title', 'text', 0, 'confirmed', 'action scheduled', { confirmed => \'current_timestamp' });
}

foreach my $problem (@fixed_problems) {
    $problem->update({ state => 'fixed - council' });
    $mech->create_comment_for_problem($problem, $counciluser, 'Title', 'text', 0, 'confirmed', 'fixed', { confirmed => \'current_timestamp' });
}

foreach my $problem (@closed_problems) {
    $problem->update({ state => 'closed' });
    $mech->create_comment_for_problem($problem, $counciluser, 'Title', 'text', 0, 'confirmed', 'closed', { confirmed => \'current_timestamp' });
}

FixMyStreet::override_config {
    ALLOWED_COBRANDS => [ { fixmystreet => '.' } ],
    MAPIT_URL => 'http://mapit.uk/',
}, sub {

    subtest 'not logged in, redirected to login' => sub {
        $mech->not_logged_in_ok;
        $mech->get_ok('/dashboard');
        $mech->content_contains( 'sign in' );
    };

    subtest 'normal user, 404' => sub {
        $mech->log_in_ok( $normaluser->email );
        $mech->get('/dashboard');
        is $mech->status, '404', 'If not council user get 404';
    };

    subtest 'superuser, body list' => sub {
        $mech->log_in_ok( $superuser->email );
        $mech->get_ok('/dashboard');
        # Contains body name, in list of bodies
        $mech->content_contains('Some Other Council');
        $mech->content_contains('Edinburgh Council');
        $mech->content_lacks('Category:');
    };

    subtest 'council user, ward list' => sub {
        $mech->log_in_ok( $counciluser->email );
        $mech->get_ok('/dashboard');
        $mech->content_lacks('Some Other Council');
        $mech->content_contains('Edinburgh Council');
        $mech->content_contains('Trowbridge');
        $mech->content_contains('Category:');
    };

    subtest 'area user can only see their area' => sub {
        $counciluser->update({area_id => $area_id});

        $mech->get("/dashboard");
        $mech->content_contains('<h1>Trowbridge</h1>');
        $mech->get("/dashboard?body=" . $other_body->id);
        $mech->content_contains('<h1>Trowbridge</h1>');
        $mech->get("/dashboard?ward=$alt_area_id");
        $mech->content_contains('<h1>Trowbridge</h1>');

        $counciluser->update({area_id => undef});
    };

    my $categories = scraper {
        process "select[name=category] > option", 'cats[]' => 'TEXT',
        process "table[id=overview] > tr", 'rows[]' => scraper {
            process 'td', 'cols[]' => 'TEXT'
        },
    };

    subtest 'The correct categories and totals shown by default' => sub {
        $mech->get("/dashboard");
        my $expected_cats = [ 'All', @cats ];
        my $res = $categories->scrape( $mech->content );
        is_deeply( $res->{cats}, $expected_cats, 'correct list of categories' );

        my @expected = (
            1, 0, 0, 1,
            0, 0, 0, 0,
            2, 0, 4, 6,
            10, 3, 0, 13,
            13, 3, 4, 20,
        );
        my $i = 0;
        foreach my $row ( @{ $res->{rows} }[1 .. 11] ) {
            foreach my $col ( @{ $row->{cols} } ) {
                is $col, $expected[$i++];
            }
        }
    };

    # TODO Test the filters do some filtering

    subtest 'export as csv' => sub {
        $mech->create_problems_for_body(1, $body->id, 'Title', {
            detail => "this report\nis split across\nseveral lines",
            areas => ",$alt_area_id,2651,",
        });
        $mech->get_ok('/dashboard?export=1');
        open my $data_handle, '<', \$mech->content;
        my $csv = Text::CSV->new( { binary => 1 } );
        my @rows;
        while ( my $row = $csv->getline( $data_handle ) ) {
            push @rows, $row;
        }
        is scalar @rows, 22, '1 (header) + 21 (reports) = 22 lines';

        is scalar @{$rows[0]}, 18, '18 columns present';

        is_deeply $rows[0],
            [
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
                'Latitude',
                'Longitude',
                'Query',
                'Ward',
                'Easting',
                'Northing',
                'Report URL',
            ],
            'Column headers look correct';

        is $rows[5]->[14], 'Trowbridge', 'Ward column is name not ID';
        is $rows[5]->[15], '529025', 'Correct Easting conversion';
        is $rows[5]->[16], '179716', 'Correct Northing conversion';
    };

};

END {
    done_testing();
}
