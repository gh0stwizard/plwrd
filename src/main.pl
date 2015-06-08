#!/usr/bin/perl

# plwrd - Perl Web Run Daemon
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.

use strict;
use POSIX ();
use Cwd ();
use Getopt::Long qw( :config no_ignore_case bundling );
use File::Spec::Functions ();
use vars qw( $PROGRAM_NAME $VERSION );


$PROGRAM_NAME = "plwrd"; $VERSION = '0.02';


my $retval = GetOptions
(
  \my %options,
  'help|h',             # print help page and exit
  'version',            # print program version and exit
  'debug',		# enables verbose logging
  'verbose',            # enables very verbose logging
  'pidfile|P=s',        # pid file ( optional )
  'home|H=s',           # chdir to home directory before fork
  'background|B',       # run in background
  'logfile|L=s',        # log file ( optional )
  'enable-syslog',      # enable logging via syslog
  'syslog-facility=s',  # syslog facility
  'quiet|q',            # enable silence mode (no log at all)
  'listen|l=s',         # listen on IP:PORT
  'backend|b=s',	# backend: feersum
  'app|a=s',		# application file
  'www-dir|W=s',	# www directory
);

# set $\ = "\n"
&os_fixes();

if ( defined $retval and !$retval ) {
  # unknown option workaround for GetOpt::Long module
  print "Use --help for help";
  exit 1;
} elsif ( exists $options{ 'help' } ) {
  &print_help();
} elsif ( exists $options{ 'version' } ) {
  &print_version();
} else {
  #*Cwd::_carp = sub { print STDERR @_ };
  &run_program();
}

exit 0;

# ---------------------------------------------------------------------

#
# OS-specific adjustments and fixes
#
sub os_fixes() {
  $\ = $^O eq 'MSWin32' ? "\r\n" : "\n";

  if ( $0 ne '-e' ) {
    # Fix for modules. Perl is able now loading program-specific
    # modules from directory where file main.pl is placed w/o "use lib".
    my $basedir = &get_program_basedir();
    my $mod_dir = "modules";
    unshift @INC, &File::Spec::Functions::rel2abs( $mod_dir, $basedir );
  }
  
  return;
}

#
# main subroutine
#
sub run_program() {
  &set_default_options();
  &fix_paths();
  &set_abs_paths();
  &set_env();
  &set_logger();
  &check_pidfile();
  &daemonize();
  &xrun();
}

#
# fork the process
#
sub daemonize() {
  exists $options{ 'background' } or return;

  my $rootdir = ( exists $options{'home'} )
    ? $options{ 'home' }
    : &File::Spec::Functions::rootdir();
  chdir( $rootdir )            || die "Can't chdir \`$rootdir\': $!";
  # Due a feature of Perl we are not closing standard handlers.
  # Otherwise, Perl will complains and throws warning messages
  # about reopenning 0, 1 and 2 filehandles.
  my $devnull = ( $^O eq 'MSWin32' ) ? 'NUL' : '/dev/null';
  open( STDIN, "< $devnull" )  || die "Can't read $devnull: $!";
  open( STDOUT, "> $devnull" ) || die "Can't write $devnull: $!";
  defined( my $pid = fork() )  || die "Can't fork: $!";
  exit if ( $pid );
  ( &POSIX::setsid() != -1 )   || die "Can't setsid: $!";
  open( STDERR, ">&STDOUT" )   || die "Can't dup stdout: $!";
}

#
# Starts a rest major part of the program
#
sub xrun() {
  my $rv;
  my $file = $options{ 'backend' };

  if ( $rv = do $file ) {
    return;
  }

  # an error was occured

  if ( $@ ) {
    die "Couldn't parse $file:$\$@";
  }

  if ( $! and !defined $rv ) {
    die "Couldn't do $file: $!";
  }

  if ( !$rv ) {
    die "Couldn't run: $file";
  }
}

#
# if pidfile exists throw error and exit
#
sub check_pidfile() {
  $options{ 'pidfile' } || return;
  -f $options{ 'pidfile' } || return;
  printf "pidfile %s: file exists\n", $options{ 'pidfile' };
  exit 1;
}

#
# sets relative paths for files and adds extention to file names
#
sub fix_paths() {
  my $file_ext = 'pl';
  my %relpaths =
  (
    # option       relative path
    'backend'	=> 'backend',
    'app'	=> 'app',
  );
  
  if ( $0 eq '-e' ) {
    # staticperl uses relative paths (vfs)
    for my $option ( keys %relpaths ) {
      my $relpath = $relpaths{ $option };
      my $filename = join '.', $options{ $option }, $file_ext;

      $options{ $option } = &File::Spec::Functions::catfile
      (
        $relpath,
        $filename,
      );
    }
  } else {  
    for my $option ( keys %relpaths ) {
      my $relpath = $relpaths{ $option };
      my $filename = join '.', $options{ $option }, $file_ext;

      $options{ $option } = &File::Spec::Functions::catfile
      (
        &get_program_basedir(),
        $relpath,
        $filename,
      );
    }
  }
}

#
# returns basedir of the program
#
sub get_program_basedir() {
  my $execp = $0;

  if ( $0 eq '-e' ) {
    # staticperl fix
    if ( $^O eq 'linux' ) {
      $execp = &Cwd::abs_path( "/proc/self/exe" );
    } else {
      die "not implemented yet";
    }
  }
  
  my ( $vol, $dirs ) = &File::Spec::Functions::splitpath( $execp );

  return &Cwd::abs_path
  (
    &File::Spec::Functions::catpath( $vol, $dirs, "" )
  );
}

#
# use realpath always
#
sub set_abs_paths() {
  my @pathopts = qw
  (
    logfile
    home
    pidfile
    www-dir
  );

  for my $option ( @pathopts ) {
    next if ( not exists $options{ $option } );

    my $path = $options{ $option };
    # naive but simple
    if ( ! &File::Spec::Functions::file_name_is_absolute( $path ) ) {
      my $cwd = &Cwd::cwd();
      $path = &File::Spec::Functions::catdir( $cwd, $path );
      $path = &File::Spec::Functions::rel2abs( $path );
    }
    
    if ( -e $path ) {
      # stupid Cwd calls carp when path does not exists!
      $options{ $option } = &Cwd::abs_path( $path );
    } else {
      $options{ $option } = $path;
    }
  }
}

sub set_default_options() {
  my %defaultmap =
  (
    'backend'	=> 'feersum',
    'app'	=> 'feersum',
    'www-dir'	=> &File::Spec::Functions::catdir( '..', 'www' ),
  );
  
  for my $option ( keys %defaultmap ) {
    if ( not exists $options{ $option } ) {
      $options{ $option } = $defaultmap{ $option };
    }
  }
}

#
# use environment variables to exchange between main & child
#
sub set_env() {
  my $prefix = uc( $PROGRAM_NAME );
  my %envmap = 
  (
    #  %options        %ENV
    'pidfile'   => join( '_', $prefix, 'PIDFILE' ),
    'listen'    => join( '_', $prefix, 'LISTEN' ),
    'app'	=> join( '_', $prefix, 'APP_NAME' ),
    'www-dir'   => join( '_', $prefix, 'WWW_DIR' ),
  );

  for my $option ( keys %envmap ) {
    if ( exists $options{ $option } ) {
      $ENV{ $envmap{ $option } } //= $options{ $option };
    }
  }
  
  # set basedir
  my $key = join( '_', $prefix, 'BASEDIR' );
  $ENV{ $key } = &get_program_basedir();
  
  return;
}

#
# we're using AE::Log logger, see perlodc -m AnyEvent::Log for details.
# Logger is configured via environment variables.
#
sub set_logger() {
  my $loglevel = 'filter=note';    # default log level 'notice'
  my $output = 'log=';             # print to stdout by default
  # disables notifications from AnyEvent(?::*) modules
  # they are "buggy" with syslog and annoying
  my $suppress = 'AnyEvent=error';

  if ( exists $options{ 'debug' } ) {
    $loglevel = 'filter=debug';
  }
  
  if ( exists $options{ 'verbose' } ) {
    $loglevel = 'filter=trace';
  }

  # setup output device: stdout, logfile or syslog

  if ( exists $options{ 'logfile' } ) {
    $output = sprintf "log=file=%s", $options{ 'logfile' };
  }

  if ( exists $options{ 'enable-syslog' } ) {
    my $facility = $options{ 'syslog-facility' } || 'LOG_DAEMON';
    $output = sprintf "log=syslog=%s", $facility;
  }
  
  # silence mode
  if ( exists $options{ 'quiet' } ) {
    $output = '+log=nolog';
  } else {  
    if ( exists $options{ 'background' } ) {
      # disables logging when running in background
      # and are not using logfile or syslog
      unless ( 
          exists $options{ 'logfile' }
       || exists $options{ 'enable-syslog' }
      ) {
        $output = '+log=nolog';
      }
    }
  }

  $ENV{ 'PERL_ANYEVENT_LOG' } ||= join
  (
    # FIXME
    # A sequence dependence due "bugs" in AnyEvent and AnyEvent::Util
    # * Please, no AE::Log() calls into BEGIN {} blocks;
    # * Sys::Syslog::openlog() must be called before
    #   "use AnyEvent(::Util)";
    " ",
    $suppress,
    join( ":", $loglevel, $output ),
  );
}

#
# prints help page to stdout
#
sub print_help() {
  print "Allowed options:";

  my $h = "  %-24s %-48s" . $\;

  printf $h, "--help [-h]", "prints this information";
  printf $h, "--version", "prints program version";

  printf $h, "--listen [-l] arg", "IP:PORT for listener";
  printf $h, "", "- default: \"127.0.0.1:28990\"";

  printf $h, "--backend [-b] arg", "backend name (default: feersum)";
  printf $h, "--app [-a] arg", "application name (default: feersum)";
  
  printf $h, "--background [-B]", "run process in background";
  printf $h, "", "- default: run in foreground (disables logging)";
  printf $h, "", "- hint: use --logfile / --enable-syslog for logging";

  printf $h, "--home [-H] arg", "working directory after fork";
  printf $h, "", "- default: root directory";
  printf $h, "--www-dir [-W] arg", "www directory with index.html";
  
  printf $h, "--debug", "be verbose";
  printf $h, "--verbose", "be very verbose";
  printf $h, "--quiet [-q]", "be silence, disables logging";
  printf $h, "--enable-syslog", "enable logging via syslog (default: disabled)";
  printf $h, "--syslog-facility arg", "syslog's facility (default: LOG_DAEMON)";
  printf $h, "--logfile [-L] arg", "path to log file (default: stdout)";

  printf $h, "--pidfile [-P] arg", "path to pid file (default: none)";
}

sub print_version() {
  printf "%s version %s%s",
    ( &File::Spec::Functions::splitpath( $PROGRAM_NAME ) )[2],
    $VERSION,
    $\,
  ;
}

__END__

=encoding utf-8

=head1 NAME

plwrd - Perl Web Run Daemon

=head1 USAGE

plwrd [-L logfile | --enable-syslog ] [-P pidfile]

=head1 DESCRIPTION

Run programs from a web interface!

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut
