
use Test::More;
use RRDTool::OO;

$| = 1;

###################################################
my $LOGLEVEL = $OFF;
###################################################

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({level => $LOGLEVEL, layout => "%L: %m%n", 
                          category => 'rrdtool',
                          file => 'stderr'});

my $rrd = RRDTool::OO->new(file => "foo");

eval { $SIG{__DIE__} = $SIG{__WARN__} = sub {}; $rrd->dump(); };

if($@ =~ /Can't locate/) {
    plan skip_all => "only with RRDs supporting dump/restore";
} else {
    print "Err: $@";
    plan tests => 2;
}

    # create with superfluous param
$rrd->create(
    data_source => { name      => 'foobar',
                     type      => 'GAUGE',
                   },
    archive     => { cfunc   => 'MAX',
                     xff     => '0.5',
                     cpoints => 5,
                     rows    => 10,
                   },
);

ok(-e "foo", "RRD exists");
my $size = -s "foo";

#####################################################
# Dump it.
#####################################################
unless (my $pid = open DUMP, "-|") {
  die "Can't fork: $!" unless defined $pid;
  $rrd->dump();
  exit 0;
}

open OUT, ">out";
print OUT $_ for <DUMP>;
close OUT;

unlink "foo";

#####################################################
# Restore it.
#####################################################
$rrd->restore("out");
is(-s "foo", $size, "RRD same size");

END { unlink "foo"; 
      unlink "out";
}
