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
                      mandatory => [qw(rows)],
                      optional  => [qw(cfunc cpoints xff)],
                    },
                  },
    update     => { mandatory => [qw(value)],
                    optional  => [qw(time)],
                  },
    graph      => { mandatory => [],
                    optional  => [],
                  },
    fetch_start=> { mandatory => [qw()],
                    optional  => [qw(cfunc start end resolution)],
                  },
    fetch_next => { mandatory => [],
                    optional  => [],
                  },
    dump       => { mandatory => [],
                    optional  => [],
                  },
    restore    => { mandatory => [],
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

    $options = [] unless defined $options;

    my %options_hash = (@$options);

    my @parts = split m#/#, $method;

    my $ref = $OPTIONS;

    $ref = $ref->{$_} for @parts;

    my %optional  = map { $_ => 1 } @{$ref->{optional}};
    my %mandatory = map { $_ => 1 } @{$ref->{mandatory}};

        # Check if we got all mandatory parameters
    for(@{$ref->{mandatory}}) {
        if(! exists $options_hash{$_}) {
            Log::Log4perl->get_logger("")->logcroak(
                "Mandatory parameter '$_' not set " .
                "in $method() (@{[%mandatory]}) (@$options)");
        }
    }
    
        # Check if all of the optional parameters we got are indeed
        # valid optional parameters
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
        raise_error => 1,
        file        => $options{file},
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

    $self->{archive_cfuncs} = [];
    my %cfuncs = ();

    for(@archives) {
       # RRA:CF:xff:steps:rows
       DEBUG "archive: @{[%$_]}";
       if(! exists $_->{xff}) {
           $_->{xff} = 0.5;
       }

       $_->{cpoints} ||= 1;

       if($_->{cpoints} > 1 and
          !exists $_->{cfunc}) {
           LOGDIE "Must specify cfunc if cpoints > 1";
       }
       if(! exists $_->{cfunc}) {
           $_->{cfunc} = 'MAX';
       }
       push @{$self->{archive_cfuncs}}, $_->{cfunc} unless 
           $cfuncs{$_->{cfunc}}++;

       push @rrdtool_options, 
           "RRA:$_->{cfunc}:$_->{xff}:$_->{cpoints}:$_->{rows}";
    }

    $self->RRDs_execute("create", @rrdtool_options);
}

my %RRDs_functions = (
    create => \&RRDs::create,
    fetch  => \&RRDs::fetch,
    update => \&RRDs::update,
);
    
#################################################
sub RRDs_execute {
#################################################
    my ($self, $command, @args) = @_;

    INFO "rrdtool $command @args";

    my @rc;
    my $error;

    if(wantarray) {
        @rc = $RRDs_functions{$command}->(@args);
        INFO "rrdtool rc=(", array_as_string(\@rc), ")";
        $error = 1 unless defined $rc[0];
    } else {
        $rc[0] = $RRDs_functions{$command}->(@args);
        INFO "rrdtool rc=(", array_as_string(\@rc), ")";
        $error = 1 unless $rc[0];
    }

    if($error) {
        LOGDIE "rrdtool $command @args failed: ", $self->error_message() if
            $self->{raise_error};
    }

        # Important to return no array in scalar context.
    if(wantarray) {
        return @rc;
    } else {
        return $rc[0];
    }
}

#################################################
sub update {
#################################################
    my($self, @options) = @_;

        # Expand short form
    @options = (value => $options[0]) if @options == 1;

    check_options "update", \@options;

    my %options_hash = @options;

    $options_hash{time} = "N" unless exists $options_hash{time};

    my $update_string  = "$options_hash{time}:";
    my @update_options = ();

    if(exists $options_hash{values}) {
        if(ref($options_hash{values} eq "HASH")) {
                # Do the template magic
            push @update_options, "--template", 
                 join(":", keys %{$options_hash{values}});
            $update_string .= join ":", values %{$options_hash{values}};
        } else {
                # We got multiple values in correct order
            $update_string .= join ":", @{$options_hash{values}};
        }
    } else {
            # We just have a single value
        $update_string .= $options_hash{value};
    }

    $self->RRDs_execute("update", $self->{file}, 
                        @update_options, $update_string);
}

#################################################
sub fetch_start {
#################################################
    my($self, @options) = @_;

    check_options "fetch_start", \@options;

    my %options_hash = @options;

    if(!exists $options_hash{cfunc}) {
        LOGDIE "No default archive cfunc" unless 
            defined $self->{archive_cfuncs}->[0];
        $options_hash{cfunc} = $self->{archive_cfuncs}->[0];
        DEBUG "Getting default cfunc '$options_hash{cfunc}'";
    }

    my $cfunc = $options_hash{cfunc};
    delete $options_hash{cfunc};

    @options = add_dashes(\%options_hash);

    INFO "rrdtool fetch $self->{file} $cfunc @options";

    ($self->{fetch_time_current}, 
     $self->{fetch_time_step},
     $self->{fetch_ds_names},
     $self->{fetch_data}) =
         $self->RRDs_execute("fetch", $self->{file}, $cfunc, @options);

    $self->{fetch_idx} = 0;
}

#################################################
sub fetch_next {
#################################################
    my($self) = @_;

    if(!defined $self->{fetch_data}->[$self->{fetch_idx}]) {
        INFO "Idx $self->{fetch_idx} returned undef";
        return ();
    }

    my @values = @{$self->{fetch_data}->[$self->{fetch_idx}++]};

        # Put the time of the data point in front
    unshift @values, $self->{fetch_time_current};

    INFO "rrdtool fetch $self->{file} ", array_as_string(\@values) if @values;

    $self->{fetch_time_current} += $self->{fetch_time_step};

    return @values;
}

#################################################
sub array_as_string {
#################################################
    my($arrayref) = @_;

    return join "-", map { defined $_ ? $_ : '[undef]' } @$arrayref;
}

#################################################
sub fetch_skip_undef {
#################################################
    my($self) = @_;

    {
        if(!defined $self->{fetch_data}->[$self->{fetch_idx}]) {
            return undef;
        }
   
        my $value = $self->{fetch_data}->[$self->{fetch_idx}]->[0];

        unless(defined $value) {
            $self->{fetch_idx}++;
            $self->{fetch_time_current} += $self->{fetch_time_step};
            redo;
        }
    }
}

#################################################
sub add_dashes {
#################################################
    my($options_hashref) = @_;

    my @options = ();

    foreach(keys %$options_hashref) {
        push @options, "--$_", $options_hashref->{$_};
    }
   
    return @options;
}

#################################################
sub error_message {
#################################################
    my($self) = @_;

    return RRDs::error();
}

1;

__END__

=head1 NAME

RRDTool::OO - Object-oriented interface to RRDTool

=head1 SYNOPSIS

        # Constructor
    my $rrd = RRDTool::OO->new( file => "myrrdfile.rdd" );

        # Create a round-robin database
    $rrd->create(
         data_source => { name => "mydatasource",
                          type => "GAUGE" },
         archive     => { rows => 5 });

        # Update RRD with a sample value, 
        # use current time.
    $rrd->update(42);

        # Start fetching values from one day back, 
        # but skip undef'd ones first
    $rrd->fetch_start(start => $time - 3600*24);
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

=over 4

=item I<my $rrd = RRDTool::OO-E<gt>new( file =E<gt> $file )>

The constructor hooks up with an existing RRD database file C<$file>, 
but doesn't create a new one if none exists. That's what the C<create()>
methode is for. Returns a C<RRDTool::OO> object, which can be used to 
get access to the following methods.

=item I<$rrd-E<gt>create( ... )>

Creates a new round robin database (RRD). It consists of one or more
data sources and one or more archives:

    $rrd->create(
         data_source => { name => $ds_name }
         archive     => { name      => $arch_name,
                          rows      => 5,
                        });

This defines an archive with a 1:1 mapping between primary data 
points and archive points. 
If you want
to combine several primary data points into one archive point, specify
values for 
C<cpoints> (the number of points to combine) and C<cfunc> 
(the consolidation function) explicitely:

    $rrd->create(
         data_source => { name => $ds_name }
         archive     => { name      => $arch_name,
                          rows      => 5,
                          cpoints   => 10,
                          cfunc     => 'AVERAGE',
                        });

This will collect 10 data points to form one archive point, using
the calculated average. 
Other options for C<cfunc> are 
C<MIN>, C<MAX>, and C<LAST>.

=item I<$rrd-E<gt>update( ... ) >

Update the round robin database with a value and an optional time stamp.
If called with a single parameter, like in

    $rrd->update($value);

then the current timestamp and the defined C<$value> are used. If C<update>
is called with a named parameter list like in

    $rrd->update(time => $time, value => $value);

then the given timestamp C<$time> is used along with the given value 
C<$value>.

When updating multiple data sources, use the C<values> parameter
instead of C<value> and pass an arrayref:

    $rrd->update(time => $time, values => [$val1, $val2, ...]);

The C<values> parameter also accepts a hashref, mapping data source
names to values:

    $rrd->update(time => $time, 
                 values => { $dsname1 => $val1, 
                             $dsname2 => $val2, ...});

C<RRDTool::OO> will transform this automagically
into C<RRDTool's> I<template> syntax.

=item I<$rrd-E<gt>fetch_start( ... )>

Initializes the iterator to fetch data from the RRD. This works nicely without
any parameters if
your archives are using a single consolidation function (e.g. C<MAX>).
If there's several archives in the RRD using different consolidation
functions, you have to specify the one you want:

    $rrd->fetch_start(cfunc => "MAX",
                      start => time()-10*60
                     );

Other options for C<cfunc> are C<MIN>, C<AVERAGE>, and C<LAST>.

If the C<start>
time parameter is omitted, the fetch starts 24 hours before the end of the 
archive. Also, an C<end> time can be specified:

    $rrd->fetch_start(start => time()-10*60,
                      end   => time());

Another optional parameter is C<resolution> (seconds per value). 
It defaults to the highest
one available. See the C<rrdtool fetch> manual page for details.

The current implementation
fetches all values from the RRA in one swoop 
and caches them in memory. I might
change this behaviour to cache only the last timestamp and keep fetching.

=item I<$rrd-E<gt>fetch_skip_undef()>

Skips all undef values in the RRA and
positions the iterator right before the first defined value.
If all values in the RRA are undefined, the
a following C<$rrd-E<gt>fetch_next()> will return C<undef>.

=item I<($time, $value, ...) = $rrd-E<gt>fetch_next()>

Gets the next row from the RRD iterator, initialized by a previous call
to C<$rrd-E<gt>fetch_start()>.

=item I<$rrd-E<gt>error_message()>

Return the message of the last error that occurred while interacting
with C<RRDTool::OO>.

=back

The following methods are not yet implemented:

C<dump>,
C<restore>,
C<tune>,
C<last>,
C<info>,
C<rrdresize>,
C<xport>,
C<rrdcgi>.

=head2 Error Handling

By default, C<RRDTool::OO>'s methods will throw fatal errors (as in: 
they're calling C<die()>) if the underlying C<RRDs::*> commands indicate
failure.

This behaviour can be overridden by calling the constructor with
the C<raise_error> flag set to false:

    my $rrd = RRDTool::OO->new(
        file        => "myrrdfile.rdd",
        raise_error => 0,
    );

In this mode, RRDTool's methods will just pass back values returned
from the underlying C<RRDs> functions if an error happens.

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
