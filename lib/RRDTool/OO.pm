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
                      mandatory => [qw(name type)],
                      optional  => [qw(min max heartbeat)],
                    },
                    archive     => {
                      mandatory => [qw(rows)],
                      optional  => [qw(cfunc cpoints xff)],
                    },
                  },
    update     => { mandatory => [qw(value)],
                    optional  => [qw(time)],
                  },
    graph      => { mandatory => [qw(file)],
                    optional  => [qw(vertical_label start end)],
                    draw      => {
                      mandatory => [qw()],
                      optional  => [qw(dsname cfunc thickness color)],
                    },
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

my %RRDs_functions = (
    create => \&RRDs::create,
    fetch  => \&RRDs::fetch,
    update => \&RRDs::update,
    graph  => \&RRDs::graph,
);

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
        raise_error       => 1,
        meta              => 
            { discovered   => 0,
              cfuncs       => [],
              cfuncs_hash  => {},
              dsnames      => [],
              dsnames_hash => {},
            },
        file              => $options{file},
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

        # RRDtool default setting
    $options_hash{step} ||= 300;

    for(@data_sources) {
       # DS:ds-name:DST:heartbeat:min:max
       DEBUG "data_source: @{[%$_]}";
       $_->{heartbeat} ||= $options_hash{step} * 2;
       push @rrdtool_options, 
           "DS:$_->{name}:$_->{type}:$_->{heartbeat}:" .
           (defined $_->{min} ? $_->{min} : "U") . ":" .
           (defined $_->{max} ? $_->{max} : "U");

       $self->meta_data("dsnames", $_->{name}, 1);
    }

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
       
       $self->meta_data("cfuncs", $_->{cfunc}, 1);

       push @rrdtool_options, 
           "RRA:$_->{cfunc}:$_->{xff}:$_->{cpoints}:$_->{rows}";
    }

    $self->RRDs_execute("create", @rrdtool_options);
}

#################################################
sub RRDs_execute {
#################################################
    my ($self, $command, @args) = @_;

    my $logger = get_logger("rrdtool");
    $logger->info("rrdtool $command @args");

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
        my $cfuncs = $self->meta_data("cfuncs");
        LOGDIE "No default archive cfunc" unless 
            defined $cfuncs->[0];
        $options_hash{cfunc} = $cfuncs->[0];
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
    my($options_hashref, $assign_hashref) = @_;

    $assign_hashref = {} unless $assign_hashref;

    my @options = ();

    foreach(keys %$options_hashref) {
        (my $newname = $_) =~ s/_/-/g;
        if($assign_hashref->{$_}) {
            push @options, "--$newname=$options_hashref->{$_}";
        } else {
            push @options, "--$newname", $options_hashref->{$_};
        }
    }
   
    return @options;
}

#################################################
sub error_message {
#################################################
    my($self) = @_;

    return RRDs::error();
}

#################################################
sub graph {
#################################################
    my($self, @options) = @_;

    check_options "graph", \@options;

    my @draws = ();
    my %options_hash = @options;
    my $draw_count   = 1;

    my $file = delete $options_hash{file};
    delete $options_hash{draw};

    for(my $i=0; $i < @options; $i += 2) {
        push @draws, $options[$i+1] if $options[$i] eq "draw";
    }

    @options = add_dashes(\%options_hash);

    # Set dsname default
    if(!exists $options_hash{dsname}) {
        my $dsnames = $self->meta_data("dsnames");
        LOGDIE "No default archive dsname" unless 
            defined $dsnames->[0];
        $options_hash{dsname} = $dsnames->[0];
        DEBUG "Getting default dsname '$options_hash{dsname}'";
    }

    # Set cfunc default
    if(!exists $options_hash{cfunc}) {
        my $cfuncs = $self->meta_data("cfuncs");
        LOGDIE "No default archive cfunc" unless 
            defined $cfuncs->[0];
        $options_hash{cfunc} = $cfuncs->[0];
        DEBUG "Getting default cfunc '$options_hash{cfunc}'";
    }

        # Push a pseudo draw if there's none.
    @draws = ({}) unless @draws;

    for(@draws) {
        check_options "graph/draw", [%$_];

        $_->{thickness} ||= 1;        # LINE1 is default
        $_->{color}     ||= 'FF0000'; # red is default

        # Create the draw strings
            #DEF:myload=$DB:load:MAX
        push @options, "DEF:draw$draw_count=$self->{file}:" .
                       "$options_hash{dsname}:" .
                       "$options_hash{cfunc}";
            #LINE2:myload#FF0000
        push @options, "LINE$_->{thickness}:draw$draw_count#$_->{color}";
        $draw_count++;
    }

    unshift @options, $file;

    $self->RRDs_execute("graph", @options);
}

#################################################
sub meta_data {
#################################################
    my($self, $field, $value, $unique_push) = @_;

    if(defined $value) {
        $self->{meta}->{discovered} = 1;
    }

    if(!$self->{meta}->{discovered}) {
        $self->meta_data_discover();
    }

    if(defined $value) {
        if($unique_push) {
            push @{$self->{meta}->{$field}}, $value unless 
                   $self->{meta}->{"${field}_hash"}->{$value}++;
        } else {
            $self->{meta}->{$field} = $value;
        }
    }

    return $self->{meta}->{$field};
}

#################################################
sub meta_data_discover {
#################################################
    my($self) = @_;

    local($self->{raise_error});

        # Disable throwing an error for a moment
    $self->{raise_error} = 0;

    for my $cfunc (qw(AVERAGE MAX MIN LAST)) {
        my ($time, $step, $dsnames, $data) =
             $self->RRDs_execute("fetch", $self->{file}, $cfunc, 
                 "--start", time()-1);
        next unless defined $time;
        DEBUG "Discovered cfunc $cfunc and dsnames=(@$dsnames)";

        $self->meta_data("cfuncs", $cfunc, 1);
        for my $dsname (@$dsnames) {
            $self->meta_data("dsnames", $dsname, 1);
        }
    }

    DEBUG "Discovery: cfuncs=(@{$self->{meta}->{cfuncs}}) ",
                    "dsnames=(@{$self->{meta}->{dsnames}})";

    $self->{meta}->{discovered} = 1;
}

1;

__END__

=head1 NAME

RRDTool::OO - Object-oriented interface to RRDTool

=head1 SYNOPSIS

        # Constructor     
    my $rrd = RRDTool::OO->new(
                 file => "myrrdfile.rdd" );

        # Create a round-robin database
    $rrd->create(
         step        => 1,  # one-second intervals
         data_source => { name      => "mydatasource",
                          type      => "GAUGE" },
         archive     => { rows      => 5 });

        # Update RRD with sample values, use current time.
    for(1..3) {
        $rrd->update($_);
        sleep(1);
    }

        # Start fetching values from one day back, 
        # but skip undefined ones first
    $rrd->fetch_start();
    $rrd->fetch_skip_undef();

        # Fetch stored values
    while(my($time, $value) = $rrd->fetch_next()) {
         print "$time: ", 
               defined $value ? $value : "[undef]", "\n";
    }

        # Draw a graph in a PNG image
    $rrd->graph(
      file           => "mygraph.png",
      vertical_label => 'My Salary',
      start          => time() - 10,
    );

=head1 DESCRIPTION

C<RRDTool::OO> is an object-oriented interface to Tobi Oetiker's 
round robin database tool I<rrdtool>. It uses I<rrdtool>'s 
C<RRDs> module to get access to I<rrdtool>'s shared library.

C<RRDTool::OO> tries to marry I<rrdtool>'s database engine with the
dwimminess and whipuptitude Perl programmers take for granted. Using
C<RRDTool::OO> abstracts away implementation details of the RRD engine,
uses easy to memorize named parameters and sets meaningful defaults 
for parameters not needed in simple cases.
For the experienced user, however, it provides full access to
I<rrdtool>'s API.
(Please check L<Development Status> to verify
how much of it has been implemented yet, though, since this module
is under development :).

=head2 FUNCTIONS

=over 4

=item I<my $rrd = RRDTool::OO-E<gt>new( file =E<gt> $file )>

The constructor hooks up with an existing RRD database file C<$file>, 
but doesn't create a new one if none exists. That's what the C<create()>
methode is for. Returns a C<RRDTool::OO> object, which can be used to 
get access to the following methods.

=item I<$rrd-E<gt>create( ... )>

Creates a new round robin database (RRD). A RRD consists of one or more
data sources and one or more archives:

    $rrd->create(
         step        => 60,
         data_source => { name      => "mydatasource",
                          type      => "GAUGE" },
         archive     => { rows      => 5 });

This defines a RRD database with a step rate of 60 seconds in between
primary data points. 

It also sets up one data source named C<my_data_source>
of type C<GAUGE>, telling I<rrdtool> to use values of data samples 
as-is, without additional trickery.  

And it creates a single archive with a 1:1 mapping between primary data 
points and archive points, with a capacity to hold five data points.

The RRD's C<step> parameter is optional, and will be set to 300 seconds
by I<rrdtool> by default.

In addition to the mandatory settings for C<name> and C<type>,
C<data_source> parameter takes the following optional parameters:
C<min> (minimum input, defaults to C<U>),
C<max> (maximum input, defaults to C<U>), 
C<heartbeat> (defaults to twice the RRD's step rate).

Archives expect at least one parameter, C<rows> indicating the number
of data points the archive is configured to hold. If nothing else is
set, I<rrdtool> will store primary data points 1:1 in the archive.

If you want
to combine several primary data points into one archive point, specify
values for 
C<cpoints> (the number of points to combine) and C<cfunc> 
(the consolidation function) explicitely:

    $rrd->create(
         step        => 60,
         data_source => { name      => "mydatasource",
                          type      => "GAUGE" },
         archive     => { rows      => 5,
                          cpoints   => 10,
                          cfunc     => 'AVERAGE',
                        });

This will collect 10 data points to form one archive point, using
the calculated average, as indicated by the parameter C<cfunc>
(Consolidation Function, CF). Other options for C<cfunc> are 
C<MIN>, C<MAX>, and C<LAST>.

=item I<$rrd-E<gt>update( ... ) >

Update the round robin database with a new data sample, 
consisting of a value and an optional time stamp.
If called with a single parameter, like in

    $rrd->update($value);

then the current timestamp and the defined C<$value> will be used. 
If C<update> is called with a named parameter list like in

    $rrd->update(time => $time, value => $value);

then the given timestamp C<$time> is used along with the given value 
C<$value>.

When updating multiple data sources, use the C<values> parameter
(instead of C<value>) and pass an arrayref:

    $rrd->update(time => $time, values => [$val1, $val2, ...]);

This way, I<rrdtool> expects you to pass in the data values in 
exactly the same order as the data sources were defined in the
C<create> method. If that's not the case,
then the C<values> parameter also accepts a hashref, mapping data source
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
functions, you have to specify which one you want:

    $rrd->fetch_start(cfunc => "MAX");

Other options for C<cfunc> are C<MIN>, C<AVERAGE>, and C<LAST>.

C<fetch_start> features a number of optional parameters: 
C<start>, C<end> and C<resolution>.

If the C<start>
time parameter is omitted, the fetch starts 24 hours before the end of the 
archive. Also, an C<end> time can be specified:

    $rrd->fetch_start(start => time()-10*60,
                      end   => time());

The third optional parameter,
C<resolution> defaults to the highest resolution available and can
be set to a value in seconds, specifying the time interval between
the data samples extracted from the RRD.
See the C<rrdtool fetch> manual page for details.

Development note: The current implementation
fetches I<all> values from the RRA in one swoop 
and caches them in memory. This might 
change in the future, to cache only the last timestamp and keep fetching
from the RRD with every C<fetch_next()> call.

=item I<$rrd-E<gt>fetch_skip_undef()>

I<rrdtool> doesn't remember the time the first data sample went into the
archive. So if you run a I<rrdtool fetch> with a start time of 24 hours
ago and you've only submitted a couple of samples to the archive, you'll
see many C<undef> values.

Starting from the current iterator position (or at the specified C<start>
time immediately after a C<fetch_start()>), C<fetch_skip_undef()>
will skip all C<undef> values in the RRA and
positions the iterator right before the first defined value.
If all values in the RRA are undefined, the
a following C<$rrd-E<gt>fetch_next()> will return C<undef>.

=item I<($time, $value, ...) = $rrd-E<gt>fetch_next()>

Gets the next row from the RRD iterator, initialized by a previous call
to C<$rrd-E<gt>fetch_start()>. Returns the time of the archive point
along with all values as a list.

=item I<$rrd-E<gt>graph( ... )>

If there's only one data source in the RRD, drawing nice graph in
an image file on disk is as easy as

    $rrd->graph(
      file           => $image_file_name,
      vertical_label => 'My Salary',
      draw           => { thickness => 2,
                          color     => 'FF0000'},
    );

This will assume a start time of 24 hours before now and an
end time of now. Specify C<start> and C<end> explicitely to
be clear:

    $rrd->graph(
      file           => $image_file_name,
      vertical_label => 'My Salary',
      color          => 'FF0000', # (red)
      start          => time() - 24*3600,
      end            => time(),
      draw           => { thickness => 2,
                          color     => 'FF0000'},
    );

If there are multiple datasources in the RRD or multiple archives
with different values for C<cfunc>, just specify explicitely which
one to draw:

    $rrd->graph(
      file           => $image_file_name,
      vertical_label => 'My Salary',
      draw           => {
        thickness => 2,
        color     => 'FF0000',
        dsname    => "load",
        cfunc     => 'MAX'},
    );

And you can certainly have more than one graph in the picture:

    $rrd->graph(
      file           => $image_file_name,
      vertical_label => 'My Salary',
      draw           => {
        thickness => 2,
        color     => 'FF0000', # red
        dsname    => "load",
        cfunc     => 'MAX'},
      draw        => {
        thickness => 2,
        color     => '00FF00', # green
        dsname    => "load",
        cfunc     => 'AVERAGE'},
    );

NOTE: C<graph()> is still under development, the interface displayed 
above might change.

=item I<$rrd-E<gt>error_message()>

Return the message of the last error that occurred while interacting
with C<RRDTool::OO>.

=back

=head2 Development Status

The following methods are not yet implemented:

C<graph> (partially),
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
they're calling C<die>) if the underlying C<RRDs::*> commands indicate
failure.

This behaviour can be overridden by calling the constructor with
the C<raise_error> flag set to false:

    my $rrd = RRDTool::OO->new(
        file        => "myrrdfile.rdd",
        raise_error => 0,
    );

In this mode, RRDTool's methods will just pass back values returned
from the underlying C<RRDs> functions if an error happens (usually
1 if successful and C<undef> if an error occurs).

=head2 Debugging

C<RRDTool::OO> is C<Log::Log4perl> enabled, so if you want to know 
what's going on under the hood, just turn it on:

    use Log::Log4perl qw(:easy);

    Log::Log4perl->easy_init({
        level    => $DEBUG
    }); 

If you're interested particularily in I<rrdtool> commands issued
by C<RRDTool::OO> while you're operating it, just enable the
category C<"rrdtool">:

    Log::Log4perl->easy_init({
        level    => $INFO, 
        category => 'rrdtool',
        layout   => '%m%n',
    }); 


This will display all C<rrdtool> commands that C<RRDTool::OO> submits
to the shared library. Let's turn it on for the code snippet in the
SYNOPSIS section of this manual page and watch the output:

    rrdtool create myrrdfile.rdd --step 1 \
            DS:mydatasource:GAUGE:2:U:U RRA:MAX:0.5:1:5
    rrdtool update myrrdfile.rdd N:1
    rrdtool update myrrdfile.rdd N:2
    rrdtool update myrrdfile.rdd N:3
    rrdtool fetch myrrdfile.rdd MAX

Often handy for cut-and-paste.

=head1 INSTALLATION

C<RRDTool::OO> requires a I<rrdtool> installation with the
C<RRDs> Perl module, that comes with the C<rrdtool> distribution.

Download the tarball from

    http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/pub/rrdtool.tar.gz

and then unpack, compile and install:

    tar zxfv rrdtool.tar.gz
    cd rrdtool-1.0.46
    make
    cd perl-shared
    perl Makefile.PL
    ./configure
    make
    make test
    make install

=head1 SEE ALSO

Tobi Oetiker's RRDTool homepage at 

    http://rrdtool.org

especially the manual page at 

    http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/manual/index.html

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Mike Schilli

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
