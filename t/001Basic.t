
use Test::More qw(no_plan);
use RRDTool::OO;

use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init({level => $DEBUG, layout => "%L: %m%n"});

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
    data_source => { name      => 'foobar',
                     type      => 'GAUGE',
                     heartbeat => 10,
                   },
    archive     => { cf    => 'MAX',
                     xff   => '0.5',
                     steps => 5,
                     rows  => 10,
                   },
);

is($rc, 1, "create ok");
ok(-f "foo", "RRD exists");
END { unlink('foo'); }

######################################################################

ok($rrd->update(value => '1000'), "update without time");
ok($rrd->update(value => '1000', time => time() + 10), "update with time");

__END__
