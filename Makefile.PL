use 5.006;
use ExtUtils::MakeMaker;
use File::Basename;

# Check if RRDs is installed
eval { require RRDs; };
my $DIST_URL = 
"http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/pub/rrdtool.tar.gz";

if($@) {
    print <<EOT;
This module requires the RRDs module to be installed. It is 
available in the rrdtool distribution:
 $DIST_URL
EOT

    $| = 1;
    print "Do you want me to install it for you right now ([y]/n)?";
    my $in = <>;
    chomp $in;
    if($in =~ /^\s*$/ or $in =~ /y/i) {
        eval { install_RRDs() };
        if($@) {
            print $@;
            note();
            exit 0;
        }
    } else {
        note();
        exit 0;
    }
}

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'RRDTool::OO',
    VERSION_FROM      => 'lib/RRDTool/OO.pm', # finds $VERSION
    PREREQ_PM         => {
                         Log::Log4perl => '0.40',
                         RRDs          => undef,
                         }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/RRDTool/OO.pm', # retrieve abstract from module
       AUTHOR         => 'Mike Schilli <m@perlmeister.com>') : ()),
);

##################################################################
sub install_RRDs {
##################################################################

    require LWP::Simple;
    print STDERR "Downloading ... ";
    LWP::Simple::getstore($DIST_URL, basename($DIST_URL)) or 
        die "Cannot download $DIST_URL ($!)";
    print STDERR "done.\n";

    system("gzip -dc rrdtool.tar.gz | tar xfv -; cd `ls -t | head -1`; configure; make; cd perl-shared; perl Makefile.PL; make; make test; make install") and die "Install failed: $!";

}

##################################################################
sub note {
##################################################################
    print "################################################\n";
    print "# Please check the INSTALLATION section in the #\n";
    print "# RRDTool::OO manual page.                     #\n";
    print "################################################\n";
}
