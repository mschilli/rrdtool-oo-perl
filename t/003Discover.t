
###########################################
# Test meta data discovery
# Mike Schilli, 2004 (m@perlmeister.com)
###########################################
use warnings;
use strict;

use Test::More qw(no_plan);
use RRDTool::OO;

use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init({
#    level => $DEBUG, 
#    layout => "%L: %m%n", 
#    file => 'stdout'
#});

my $rrd = RRDTool::OO->new(file => "rrdtooltest.rrd");

        # Create a round-robin database
$rrd->create(
     step        => 1,  # one-second intervals
     data_source => { name      => "mydatasource",
                      type      => "GAUGE" },
     archive     => { rows      => 5 });

$rrd->meta_data_discover();
my $dsnames = $rrd->meta_data("dsnames");
my $cfuncs  = $rrd->meta_data("cfuncs");
is("@$cfuncs", "MAX", "check cfunc");
is("@$dsnames", "mydatasource", "check dsname");

END { unlink "rrdtooltest.rrd";
