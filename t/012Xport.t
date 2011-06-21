
use Test::More qw/no_plan/;
use RRDTool::OO;
use Log::Log4perl qw(:easy);

$SIG{__WARN__} = sub {
    use Carp qw(cluck);
    print cluck();
};

##############################################
# Configuration
##############################################
my $LOGLEVEL = $INFO;  # Level of detail
##############################################

my $rrd = RRDTool::OO->new(file => "foo");

######################################################################
# Create a RRD "foo"
######################################################################

my $start_time     = 1080460200;
my $nof_iterations = 40;
my $end_time       = $start_time + $nof_iterations * 60;

my $rc = $rrd->create(
    start     => $start_time - 10,
    step      => 60,
    data_source => { name      => 'load1',
                     type      => 'GAUGE',
                     heartbeat => 90,
                     min       => 0,
                     max       => 10.0,
                   },
    data_source => { name      => 'load2',
                     type      => 'GAUGE',
                     heartbeat => 90,
                     min       => 0,
                     max       => 10.0,
                   },
    archive     => { cfunc    => 'MAX',
                     xff      => '0.5',
                     cpoints  => 1,
                     rows     => 5,
                   },
    archive     => { cfunc    => 'MAX',
                     xff      => '0.5',
                     cpoints  => 5,
                     rows     => 10,
                   },
    archive     => { cfunc    => 'MIN',
                     xff      => '0.5',
                     cpoints  => 1,
                     rows     => 5,
                   },
    archive     => { cfunc    => 'MIN',
                     xff      => '0.5',
                     cpoints  => 5,
                     rows     => 10,
                   },
);

is($rc, 1, "create ok");
ok(-f "foo", "RRD exists");

for(0..$nof_iterations) {
    my $time = $start_time + $_ * 60;
    my $value = sprintf "%.2f", 2 + $_ * 0.1;

    $rrd->update(time => $time, values => { 
        load1 => $value,
        load2 => $value+1,
    });
}

$rrd->fetch_start(start => $start_time, end => $end_time,
                  cfunc => 'MAX');
$rrd->fetch_skip_undef();
while(my($time, $val1, $val2) = $rrd->fetch_next()) {
    last unless defined $val1;
    DEBUG "$time:$val1:$val2";
}

############################
## Do some real test here ##
############################
my $results = $rrd->xport(
	start => $start_time,
	end => $end_time,
	def => [{
		vname => "load1_vname",
		file => "foo",
		dsname => "load1",
		cfunc => "MAX",
	},
	{
		vname => "load2_vname",
		file => "foo",
		dsname => "load2",
		cfunc => "MIN",
	}],
	xport => [{
		vname => "load1_vname",
		legend => "it_gonna_be_legend",
	},
	{
		vname => "load2_vname",
		legend => "wait_for_it___dary",
	}],
);
ok(defined($results), "RRDs::xport returns something");

my $meta = $results->{meta};
my $data = $results->{data};

ok($meta->{end} == $end_time, "EndTime matches");
ok($meta->{start} == $start_time, "StartTime matches");
ok($meta->{columns} == $nof_iterations, "Number of columns matches");
ok(ref($meta->{legend}) eq "ARRAY", "Legend is an ARRAY ref");
ok($meta->{legend}->[0] eq "it_gonna_be_legend", "First legend matches");
ok($meta->{legend}->[1] eq "wait_for_it___dary", "First legend matches");

my $first = shift(@$data);
my $last = pop(@$data);
ok($first->[0] == $start_time, "First data timestamp matches");
ok($last->[0] == $end_time, "Last data timestamp matches");

ok($data->[2] - $data->[1] == $meta->{step}, "Step is respected between two entries");

# Some cleanup
unlink("foo");
unlink("bar");
