
use Test::More qw(no_plan);
use RRDTool::OO;
use Log::Log4perl qw(:easy);

##############################################
# Configuration
##############################################
my $VIEW     = 0;     # Display graphs
my $LOGLEVEL = $OFF;  # Level of detail
##############################################

sub view {
    return unless $VIEW;
    system("xv $_[0]");
}

Log::Log4perl->easy_init({level => $OFF, layout => "%m%n", 
                          category => 'rrdtool',
                          file => 'stdout'});

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
    my $value = 2 + $_ * 0.1;

    $rrd->update(time => $time, values => { 
        load1 => $value,
        load2 => $value+1,
    });
}

$rrd->fetch_start(start => $start_time, cfunc => 'MAX');
$rrd->fetch_skip_undef();
while(my($time, $val1, $val2) = $rrd->fetch_next()) {
    last unless defined $val1;
    DEBUG "$time:$val1:$val2";
}

######################################################################
# Create anoter RRD "bar"
######################################################################

my $rrd2 = RRDTool::OO->new(file => "bar");

$start_time     = 1080460200;
$nof_iterations = 40;
$end_time       = $start_time + $nof_iterations * 60;

$rc = $rrd2->create(
    start     => $start_time - 10,
    step      => 60,
    data_source => { name      => 'load3',
                     type      => 'GAUGE',
                     heartbeat => 90,
                     min       => 0,
                     max       => 10.0,
                   },
    archive     => { cfunc    => 'AVERAGE',
                     xff      => '0.5',
                     cpoints  => 5,
                     rows     => 10,
                   },
);

is($rc, 1, "create ok");
ok(-f "bar", "RRD exists");

for(0..$nof_iterations) {
    my $time = $start_time + $_ * 60;
    my $value = 10 - $_ * 0.1;

    $rrd2->update(time => $time, values => { 
        load3 => $value,
    });
}

$rrd2->fetch_start(start => $start_time, cfunc => 'AVERAGE');
$rrd2->fetch_skip_undef();
while(my($time, $val1) = $rrd2->fetch_next()) {
    last unless defined $val1;
    DEBUG "$time:$val1";
}

######################################################################
# Draw simple graph
######################################################################
        # Simple line graph
    $rrd->graph(
      image          => "mygraph.png",
      vertical_label => 'My Salary',
      start          => $start_time,
      end            => $start_time + $nof_iterations * 60,
    );

view("mygraph.png");
ok(-f "mygraph.png", "Image exists");
unlink "mygraph.png";

######################################################################
# Draw simple area graph
######################################################################
        # Simple line graph
    $rrd->graph(
      image          => "mygraph.png",
      vertical_label => 'My Salary',
      start          => $start_time,
      end            => $start_time + $nof_iterations * 60,
      draw           => { 
          type  => "area",
          color => "00FF00",
      },
    );

view("mygraph.png");
ok(-f "mygraph.png", "Image exists");
unlink "mygraph.png";

######################################################################
# Draw simple stacked graph
######################################################################
        # Simple stacked graph
    $rrd->graph(
      image          => "mygraph.png",
      vertical_label => 'My Salary',
      start          => $start_time,
      end            => $start_time + $nof_iterations * 60,
      draw           => { 
          type  => "area",
          color => "00FF00",
      },
      draw           => { 
          dsname => "load2",
          type   => "stack",
          color  => "0000FF",
      },
    );

view("mygraph.png");
ok(-f "mygraph.png", "Image exists");
unlink "mygraph.png";

######################################################################
# Draw a graph from two RRD files
######################################################################
$rrd->graph(
  image          => "mygraph.png",
  vertical_label => 'My Salary',
  start          => $start_time,
  end            => $start_time + $nof_iterations * 60,
  draw           => {
          type      => "line",
          thickness => 3,
          color     => '0000ff',
          dsname    => 'load1',
          cfunc     => 'MIN',
  },
  draw           => {
          file      => 'bar',
          type      => "line",
          thickness => 3,
          color     => 'ff0000',
          # dsname    => 'load3',
          # cfunc     => 'AVERAGE',
  },
);

view("mygraph.png");
ok(-f "mygraph.png", "Image exists");
unlink "mygraph.png";

unlink("foo");
unlink("bar");
