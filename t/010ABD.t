# Test dry run mode in RRDTool::OO

use Test::More;
use RRDTool::OO;

use Log::Log4perl qw(:easy);

plan tests => 6;

Log::Log4perl->easy_init({level => $INFO, layout => "%L: %m%n", 
                          category => 'rrdtool',
                          file => 'stdout'});

my $rrd = RRDTool::OO->new(
  file        => 'foo',
  raise_error => 1,
);

my $start_time     = 1080460200;
my $nof_iterations = 100;
my $end_time       = $start_time + $nof_iterations * 60;

   # Define the RRD
my $rc = $rrd->create(
    start       => $start_time - 10,
    step        => 60,
    data_source => { name      => 'load1',
                     type      => 'GAUGE',
                     heartbeat => 90,
                     min       => 0,
                     max       => 100.0,
                   },
    archive => { rows  => 300,
                 cfunc => "MAX",
               },

    hwpredict   => { rows            => 300,
                     alpha           => 0.01,
                     beta            => 0.01,
                     seasonal_period => 30,
                     threshold       => 2,
                     window_length   => 3,
                   },
);

my $time  = $start_time;
my $value = 2;

for(0..$nof_iterations) {
    $time  += 60;
    $value += 0.1;
    $rrd->update(time => $time, value => $value);
}

for(1..10) {
    $time += 60;
    $rrd->update(time => $time, value => $value + 5);
}

for(0..$nof_iterations) {
    $time  += 60;
    $value += 0.1;

    $rrd->update(time => $time, value => $value);
}

$rrd->graph(
    image => "mygraph.png",
    start => $start_time,
    end   => $time,
    draw           => {
        type   => "area",
        color  => '0000FF',
        cfunc  => 'MAX',
    }
);

system("xv mygraph.png");

__END__
$rrd->fetch_start(start => $start_time, cfunc => "FAILURES");
$rrd->fetch_skip_undef();
my $count = 0;
while(my($time, $val) = $rrd->fetch_next()) {
    last unless defined $val;
    print "$time: $val\n";
}
