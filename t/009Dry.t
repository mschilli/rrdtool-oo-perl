# Test dry run mode in RRDTool::OO

use Test::More qw(no_plan);
use RRDTool::OO;

use Log::Log4perl qw(:easy);

#Log::Log4perl->easy_init({level => $INFO, layout => "%L: %m%n", 
#                          category => 'rrdtool',
#                          file => 'stdout'});

my $rrd = RRDTool::OO->new(
  file    => 'foo',
  dry_run => 1,
);

my $start_time     = 1080460200;

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
    data_source => { name      => 'load2',
                     type      => 'GAUGE',
                     heartbeat => 90,
                     min       => 0,
                     max       => 100.0,
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
);

my($subref, $args, $func) = $rrd->get_exec_env();

is($func, "create", "get_exec_env function");
is("@$args", "foo --start 1080460190 --step 60 DS:load1:GAUGE:90:0:100 DS:load2:GAUGE:90:0:100 RRA:MAX:0.5:1:5 RRA:MAX:0.5:5:10", "dry run arguments");
