
use Test::More qw(no_plan);
use RRDTool::OO;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({level => $INFO, layout => "%L: %m%n", 
                          file => 'stdout'});

my $rrd;

######################################################################
    # constructor missing mandatory parameter
eval { $rrd = RRDTool::OO->new(); };
like($@, qr/Mandatory parameter 'file' not set/, "new without file");

    # constructor featuring illegal parameter
eval { $rrd = RRDTool::OO->new( file => 'file', foobar => 'abc' ); };
like($@, qr/Illegal parameter 'foobar' in new/, "new with illegal parameter");

    # Legal constructor
$rrd = RRDTool::OO->new( file => 'foo' );

######################################################################
    # create missing everything
eval { $rrd->create(); };
like($@, qr/Mandatory parameter/, "create missing everything");

    # create missing data_source
eval { $rrd->create( archive => {} ); };
like($@, qr/Mandatory parameter/, "create missing data_source");

    # create missing archive
eval { $rrd->create( data_source => {} ); };
like($@, qr/Mandatory parameter/, "create missing archive");

    # create missing heartbeat
eval { $rrd->create(
    data_source => { name      => 'foobar',
                     type      => 'foo',
                     # heartbeat => 10,
                   },
    archive     => { cf    => 'abc',
                     xff   => '0.5',
                     steps => 5,
                     rows  => 10,
                   },
) };

like($@, qr/Mandatory parameter/, "create missing hearbeat");

    # legal create
my $rc = $rrd->create(
    start     => time() - 3600,
    step      => 10,
    data_source => { name      => 'foobar',
                     type      => 'GAUGE',
                     heartbeat => 100,
                   },
    archive     => { cf    => 'MAX',
                     xff   => '0.5',
                     steps => 1,
                     rows  => 100,
                   },
);

is($rc, 1, "create ok");
ok(-f "foo", "RRD exists");

######################################################################
# Check updates
######################################################################

my $items_in = 0;

for(my $i=400; $i >= 0; $i -= 20) {
    $items_in++;
    my $time  = time() - $i;
    my $value = 1000 + $i;
    $rrd->update(value => $value, time => $time);
}

$rrd->fetch_start(start => time() - 500, cf => 'MAX');
$rrd->fetch_skip_undef();
my $count = 0;
while(my($time, $val) = $rrd->fetch_next()) {
    $count++;
}
is($count, 11, "11 items found ($items_in in)");

######################################################################
# Failed update: time went backwards
######################################################################
ok(! $rrd->update(value => 123, time => time()), 
   "update with expired timestamp");

like($rrd->error_message(), qr/illegal attempt to update using time \d+ when last update time is \d+ \(minimum one second step\)/, "check error message");

END { unlink('foo'); }
