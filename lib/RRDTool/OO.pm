package RRDTool::OO;

use 5.6.0;
use strict;
use warnings;
use Carp;
use RRDs;
use Log::Log4perl qw(:easy);

our $VERSION = '0.01';

   # Define the mandatory and optional parameters for every method.
our $OPTIONS = {
    new        => { mandatory => ['file'],
                    optional  => [],
                  },
    create     => { mandatory => [qw(data_source archive)],
                    optional  => [qw(step start)],
                    data_source => { 
                      mandatory => [qw(name type heartbeat)],
                      optional  => [qw(min max)],
                    },
                    archive     => {
                      mandatory => [qw(cf xff steps rows)],
                      optional  => [],
                    },
                  },
    update     => { mandatory => [qw(value)],
                    optional  => [qw(time)],
                  },
    graph      => { mandatory => [],
                    optional  => [],
                  },
    dump       => { mandatory => [],
                    optional  => [],
                  },
    restore    => { mandatory => [],
                    optional  => [],
                  },
    fetch      => { mandatory => [],
                    optional  => [],
                  },
    tune       => { mandatory => [],
                    optional  => [],
                  },
    last       => { mandatory => [],
                    optional  => [],
                  },
    info       => { mandatory => [],
                    optional  => [],
                  },
    rrdresize  => { mandatory => [],
                    optional  => [],
                  },
    xport      => { mandatory => [],
                    optional  => [],
                  },
    rrdcgi     => { mandatory => [],
                    optional  => [],
                  },
};

#################################################
sub check_options {
#################################################
    my($method, $options) = @_;

    DEBUG "checking '@$options'";

    $options = [] unless defined $options;

    my %options_hash = (@$options);

    my @parts = split m#/#, $method;

    my $ref = $OPTIONS;

    $ref = $ref->{$_} for @parts;

    my %optional  = map { $_ => 1 } @{$ref->{optional}};
    my %mandatory = map { $_ => 1 } @{$ref->{mandatory}};

    for(@{$ref->{mandatory}}) {
        if(! exists $options_hash{$_}) {
            Log::Log4perl->get_logger("")->logcroak(
                "Mandatory parameter '$_' not set " .
                "in $method() (@{[%mandatory]}) (@$options)");
        }
    }
    
    for(keys %options_hash) {
        if(! exists $optional{$_} and
           ! exists $mandatory{$_}) {
            Log::Log4perl->get_logger("")->logcroak(
                "Illegal parameter '$_' in $method()");
        }
    }

    1;
}

#################################################
sub new {
#################################################
    my($class, %options) = @_;

    check_options "new", [%options];

    my $self = {
        file => $options{file},
    };

    bless $self, $class;
}

#################################################
sub create {
#################################################
    my($self, @options) = @_;

    check_options "create", \@options;
    my %options_hash = @options;

    my @archives;
    my @data_sources;

    for(my $i=0; $i < @options; $i += 2) {
        push @archives, $options[$i+1] if $options[$i] eq "archive";
        push @data_sources, $options[$i+1] if $options[$i] eq "data_source";
    }

    DEBUG "Archives: ", scalar @archives, " Sources: ", scalar @data_sources;

    for(@archives) {
        check_options "create/archive", [%$_];
    }
    for(@data_sources) {
        check_options "create/data_source", [%$_];
    }

    my @rrdtool_options = ($self->{file});

    push @rrdtool_options, "--start", $options_hash{start} if
        exists $options_hash{start};

    push @rrdtool_options, "--step", $options_hash{step} if
        exists $options_hash{step};

    for(@data_sources) {
       # DS:ds-name:DST:heartbeat:min:max
       DEBUG "data_source: @{[%$_]}";
       push @rrdtool_options, 
           "DS:$_->{name}:$_->{type}:$_->{heartbeat}:" .
           (defined $_->{min} ? $_->{min} : "U") . ":" .
           (defined $_->{max} ? $_->{max} : "U");
    }

    for(@archives) {
       # RRA:CF:xff:steps:rows
       DEBUG "archive: @{[%$_]}";
       push @rrdtool_options, 
           "RRA:$_->{cf}:$_->{xff}:$_->{steps}:$_->{rows}";
    }

    DEBUG "rrdtool create @rrdtool_options";
    RRDs::create(@rrdtool_options) or die "Cannot create rrd";
}

#################################################
sub update {
#################################################
    my($self, @options) = @_;

# TODO: takes multiple values (see manual)

    check_options "update", \@options;

    my %options_hash = @options;

    $options_hash{time} = "N" unless exists $options_hash{time};

    my $update_string = "$options_hash{time}:$options_hash{value}";

    DEBUG "rrdtool update $self->{file} $update_string";
    RRDs::update($self->{file}, $update_string) or 
       die "Cannot update rrd with '$update_string'";
}

1;

__END__

$rrd->update( time => $time,
              value => $value,
             );

$rrd->fetch_start( start => $time, end => $endtime );
$rrd->fetch_skip_undef();
while(my($value, $time) = $rrd->fetch_next()) {
     # ... $value
}
$rrd->fetch_reset();

$rrd->graph( var   => $varname,
              start => $start_time,
              end   => $end_time,
            );

$rrd->delete();

1;
__END__

=head1 NAME

RRDTool::OO - Object-oriented interface to RRDTool

=head1 SYNOPSIS

        # Constructor
    my $rrd = RRDTool::OO->new( file => $file );

        # Create an archive
    $rrd->create(
         data_source => { name => $ds_name }
         archive     => { name         => $arch_name,
                          con_function => 'MAX',
                          max_points   => 5,
                          con_points   => 1 });

        # Update RRD with a sample value
    $rrd->update($value) or 
        warn "Update failed: ", $rrd->error_message();

        # Start fetching values from one day back, 
        # but skip undef'd ones first
    $rrd->fetch_reset(start => $time - 3600*24);
    $rrd->fetch_skip_undef();

        # Fetch stored values
    while(my($time, $value) = $rrd->fetch_next()) {
         print "$time: $value\n";
    }

=head1 DESCRIPTION

C<RRDTool::OO> is an object-oriented interface to Tobi Oetiker's 
round robin database RRDTool. It uses the C<RRDs> module, under
the hood, but provides a user-friendly interface with named parameters 
instead of the more compact but rather terse RRDTool configuration 
notation.

=head1 SEE ALSO

http://rrdtool.org

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Mike Schilli

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
