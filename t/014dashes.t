
use Test::More tests => 12;
use RRDTool::OO;
use Log::Log4perl qw(:easy);

$SIG{__WARN__} = sub {
    use Carp qw(cluck);
    print cluck();
};

##############################################
# Configuration
##############################################
my $VIEW     = 0;                 # Display graphs
my $VIEWPROG = "/usr/bin/eog";    # using viewprog
my $LOGLEVEL = $INFO;            # Level of detail
my $DELETE   = 1;                 # Delete charts
##############################################

sub view {
    return unless $VIEW;
    system( $VIEWPROG, $_[0] ) if ( -x $VIEWPROG );
}

#Log::Log4perl->easy_init( { level    => $LOGLEVEL, layout   => "%m%n",
##    category => 'rrdtool',
#    file     => 'stderr',
#    layout   => '%F{1}-%L: %m%n',
#});

my $rrd = RRDTool::OO->new( file => "foo" );

######################################################################
# Create a RRD "foo"
######################################################################

my $start_time     = 1080460200;
my $nof_iterations = 40;
my $end_time       = $start_time + $nof_iterations * 60;

my $rc = $rrd->create(
    start       => $start_time - 10,
    step        => 60,
    data_source => {
        name      => 'load1',
        type      => 'GAUGE',
        heartbeat => 90,
        min       => 0,
        max       => 10.0,
    },
    data_source => {
        name      => 'load2',
        type      => 'GAUGE',
        heartbeat => 90,
        min       => 0,
        max       => 10.0,
    },
    archive => {
        cfunc   => 'MAX',
        xff     => '0.5',
        cpoints => 1,
        rows    => 5,
    },
    archive => {
        cfunc   => 'MAX',
        xff     => '0.5',
        cpoints => 5,
        rows    => 10,
    },
    archive => {
        cfunc   => 'MIN',
        xff     => '0.5',
        cpoints => 1,
        rows    => 5,
    },
    archive => {
        cfunc   => 'MIN',
        xff     => '0.5',
        cpoints => 5,
        rows    => 10,
    },
);

is( $rc, 1, "create ok" );
ok( -f "foo", "RRD exists" );

for ( 0 .. $nof_iterations ) {
    my $time = $start_time + $_ * 60;
    my $value = sprintf "%.2f", 2 + $_ * 0.1;

    $rrd->update(
        time   => $time,
        values => {
            load1 => $value,
            load2 => $value + 1,
        }
    );
}

$rrd->fetch_start(
    start => $start_time,
    end   => $end_time,
    cfunc => 'MAX'
);
$rrd->fetch_skip_undef();
while ( my ( $time, $val1, $val2 ) = $rrd->fetch_next() ) {
    last unless defined $val1;
    DEBUG "$time:$val1:$val2";
}

######################################################################
# Draw simple graph
######################################################################
# Simple line graph, no new features
test_graph( $rrd, "mygraph", "My Salary", "My Salary", [], );

######################################################################
# Draw simple graph with dashed line
######################################################################
# Simple line graph, default dash
test_graph(
    $rrd,
    "dash_default",
    "My Salary",
    "Dash Default",
    [
        draw => {
            dashes    => undef,
            thickness => 2,
        }
    ]
);

######################################################################
# Draw simple graph with specific dash pattern
######################################################################
test_graph(
    $rrd,
    "dash_defined",
    "My Salary",
    "Dash Defined 5=red, 5,10,4=blue",
    [
        draw => {
            dsname    => 'load1',
            dashes    => 5,
            thickness => 2,
        },
        draw => {
            dsname    => "load2",
            dashes    => "5,10,4",
            color     => '0000ff',
            thickness => 2,
        }
    ]
);

######################################################################
# Draw graph with two lines with a dash offset.
######################################################################
test_graph(
    $rrd,
    "dash_offset",
    "My Salary",
    "Offset Dashes",
    [
        draw => {
            dashes    => "3,4",
            thickness => 1,
        },
        draw => {
            dsname      => 'load2',
            dashes      => "3,4",
            thickness   => 1,
            dash_offset => 3,
        }
    ]
);

######################################################################
# Simple line graph, skipscale
######################################################################
test_graph(
    $rrd,
    "line_skipscale",
    "load2 has skipscale",
    [
        draw => {
            dashes    => "3,4",
            thickness => 1,
        },
        draw => {
            dsname      => 'load2',
            dashes      => "3,4",
            thickness   => 1,
            skipscale   => undef,
            dash_offset => 2,
        }
    ]
);

unlink("foo") if $DELETE;
unlink("bar") if $DELETE;

done_testing();
######################################################################
######################################################################
######################################################################

sub test_graph {
    my $rrd   = shift;
    my $image = shift;
    my $title = shift;
    my $draws = shift;

    ok(
        $rrd->graph(
            image          => "$image.png",
            vertical_label => 'My Salary',
            title          => $title,
            start          => $start_time,
            end            => $start_time + $nof_iterations * 60,
            @{$draws},
        ),
        "Graph state"
    );

    view("$image.png");
    ok( -f "$image.png", "Image $image exists" );
    unlink("$image.png") if $DELETE;
}
