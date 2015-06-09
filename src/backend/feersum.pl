#!/usr/bin/perl

# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.

=encoding utf-8

=head1 NAME

Backend for plwrd program written with Feersum.

=cut

#
# Workaround for AnyEvent::Fork->new() + staticperl:
#  Instead of using a Proc::FastSpawn::spawn() call
#  just fork the current process.
#  
#  Creates parent, template process.
#
use AnyEvent::Fork::Early;
my $PREFORK = AnyEvent::Fork->new();

# there is 'main' program starts

use strict;
use common::sense;
use Feersum;
use EV;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Util ();
use AnyEvent::Fork::RPC;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;
use Socket ();
use vars qw( $PROGRAM_NAME $VERSION );


my %CURRENT_SETTINGS;
my %DEFAULT_SETTINGS =
(
  'LISTEN'    => '127.0.0.1:28990',
  'APP_NAME'  => 'app+feersum.pl',
  'SOMAXCONN' => &Socket::SOMAXCONN(),
  'PIDFILE'   => '',
  'MAXPROC'   => 8, # max. number of forked processes
  'MAXLOAD'   => 2, # max. number of queued queries per worker process
);


{
  my $t; $t = AE::timer 0, 0, sub {
    undef $t;
    &start_server();
  };
  
  my %signals; %signals = 
  (
    'HUP' => sub {
      AE::log alert => "SIGHUP recieved, reload";
      &reload_server();
    },
    'INT' => sub {
      AE::log alert => 'SIGINT recieved, shutdown';
      %signals = ();
      &shutdown_server();
    },
    'TERM' => sub {
      AE::log alert => 'SIGTERM recieved, shutdown';
      %signals = ();
      &shutdown_server();
    },
  );
  
  %signals = map {
    # signal name         AE::signal( NAME, CALLBACK )
    +"$_"         =>      AE::signal( $_, $signals{ $_ } )
  } keys %signals;
            
  $EV::DIED = $Feersum::DIED = sub {
    AE::log fatal => "$@";
  };
}

# ---------------------------------------------------------------------

=head1 FUNCTIONS

=over 4

=item B<create_pool>()

Creates pool of worker processes.

=cut

{
  my $pool; # AnyEvent::Fork::Pool object reference
  my %queue;

  sub create_pool() {
    my $max_proc = $CURRENT_SETTINGS{ 'MAXPROC' };
    my $max_load = $CURRENT_SETTINGS{ 'MAXLOAD '};
  
    $pool = $PREFORK->require( "Local::Run" )->AnyEvent::Fork::Pool::run
      (
        "Local::Run::execute",
        max   => ( scalar AnyEvent::Fork::Pool::ncpu( $max_proc ) ),
        idle  => int( $max_proc / 2 ) || 1,
        load  => $max_load,
        start => 0.1,
        stop  => 10,
        async => 0,
        serializer => $AnyEvent::Fork::RPC::JSON_SERIALISER,
        on_error => \&_pool_error_cb,
        on_event => \&_pool_event_cb,
        on_destroy => \&_pool_destroy_cb,
      )
    ;
    
    return;
  }

  
=item B<run>( $cmd, @args, $cb->( $rv, $out ) )

Executes a program $cmd with arguments @args. A callback function 
is called with two arguments:

=over 2

=item *

$rv is a result either 1 (ok) or 0 (error)

=item *

$out is an output string containing both stdout and stderr

=back

=cut

  
  sub run {
    $pool->( @_ );
  }

  
  sub _pool_error_cb {
    AE::log crit => "pool: @_";
    undef $pool;
  }

  sub _pool_event_cb {
    # using on_event as logger
    AE::log $_[0] => $_[1];
  }
  
  sub _pool_destroy_cb {
    AE::log alert => "pool has been destroyed";
  }
}


# ---------------------------------------------------------------------

=item B<start_server>()

Start a server process.

=cut

  
sub start_server() {
  &enable_syslog();
  &debug_settings();
  &update_settings();
  &write_pidfile();
  
  &create_pool();
  &start_httpd();
  
  AE::log note => "Listen on %s:%d, PID = %d",
    parse_listen(),
    $$,
  ;
}


=item B<shutdown_server>()

Shutdown a server process.

=cut


sub shutdown_server() {
  &unlink_pidfile();
  &stop_httpd();
  &EV::unloop();
}


=item B<reload_server>()

Reload a server process.

=cut


sub reload_server() {
  &reload_syslog();  
  &stop_httpd();
  &start_httpd();

  AE::log note => "Server restarted, PID = %d", $$;
}


=item B<update_settings>()

Updates the server settings either by %ENV variables or
default settings.

=cut


sub update_settings() {
  for my $var ( keys %DEFAULT_SETTINGS ) {
    my $envname = join '_', uc( $PROGRAM_NAME ), $var;
    
    $CURRENT_SETTINGS{ $var } = defined $ENV{ $envname }
      ? $ENV{ $envname }
      : $DEFAULT_SETTINGS{ $var }
    ;
  }
}


=item B<enable_syslog>()

Enables syslog.

=cut


sub enable_syslog() {
  my $facility = &get_syslog_facility() || return;
  
  require Sys::Syslog;
  
  &Sys::Syslog::openlog
  (
    $PROGRAM_NAME,
    'ndelay,pid', # nodelay, include pid
    $facility,
  );
}


=item B<reload_syslog>()

Reload syslog context.

=cut


sub reload_syslog() {
  my $facility = &get_syslog_facility() || return;
  
  require Sys::Syslog;
  
  &Sys::Syslog::closelog();

  &Sys::Syslog::openlog
  (
    $PROGRAM_NAME,
    'ndelay,pid',
    $facility,
  );
}


=item $facility = B<get_syslog_facility>()

Returns a syslog facility name from C< $ENV{ PERL_ANYEVENT_LOG } >
variable.

=cut


sub get_syslog_facility() {
  $ENV{ 'PERL_ANYEVENT_LOG' } =~ m/syslog=([_\w]+)$/ or return;
  return "$1";
}


=item B<start_httpd>()

Starts Feersum.

=cut

{
  my $Instance;
  
  sub start_httpd() {
    $Instance ||= Feersum->endjinn();

    my ( $addr, $port ) = parse_listen();
    my $socket = &create_socket( $addr, $port );
      
    if ( my $fd = fileno( $socket ) ) {
      $Instance->accept_on_fd( $fd );
      $Instance->set_server_name_and_port( $addr, $port );
      $Instance->{ 'socket' } = $socket;
      $Instance->request_handler( &load_app() );
      return;
    }

    AE::log fatal => "Could not retrieve fileno %s:%d: %s",
      $addr, $port, $!;
  }


=item B<stop_httpd>()

Stops Feersum.

=cut

  
  sub stop_httpd() {
    if ( ref $Instance eq 'Feersum' ) {
      $Instance->request_handler( \&_503 );
      $Instance->unlisten();
      close( delete $Instance->{ 'socket' } )
        or AE::log error => "Close listen socket: %s", $!;
    }
  }
}

sub _405 {
  $_[0]->send_response
  (
    405,
    [ 'Content-Type' => 'text/html' ],
    [ "Method Not Allowed" ],
  );
}

sub _500 {
  $_[0]->send_response
  (
    500,
    [ 'Content-Type' => 'text/html' ],
    [ 'Internal Server Error' ],
  );
}

sub _501 {
  $_[0]->send_response
  (
    501,
    [ 'Content-Type' => 'text/html' ],
    [ 'Not Implemented' ],
  );
}

sub _503 {
  $_[0]->send_response
  (
    503,
    [ 'Content-Type' => 'text/html' ],
    [ 'Service Unavailable' ],
  );
}


=item $sock = B<create_socket>( $addr, $port )

Creates SOCK_STREAM listener socket with next options:

=over

=item *

SO_REUSEADDR

=item *

SO_KEEPALIVE

=back

=cut


sub create_socket($$) {
  my ( $addr, $port ) = @_;

  my $proto = &AnyEvent::Socket::getprotobyname( 'tcp' );

  socket
  (
    my $socket,
    &Socket::PF_INET,
    &Socket::SOCK_STREAM,
    $proto,
  ) or do {
    AE::log fatal => "Could not create socket %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };
  
  setsockopt
  (
    $socket,
    &Socket::SOL_SOCKET(),
    &Socket::SO_REUSEADDR(),
    pack( "l", 1 ),
  ) or AE::log error => "Could not setsockopt SO_REUSEADDR %s:%d: %s",
    $addr,
    $port,
    $!,
  ;
  
  setsockopt
  (
    $socket,
    &Socket::SOL_SOCKET(),
    &Socket::SO_KEEPALIVE(),
    pack( "I", 1 ),
  ) or AE::log error => "Could not setsockopt SO_KEEPALIVE %s:%d: %s",
    $addr,
    $port,
    $!,
  ;
  
  &AnyEvent::Util::fh_nonblocking( $socket, 1 );

  my $sa = &AnyEvent::Socket::pack_sockaddr
  (
    $port,
    &AnyEvent::Socket::aton( $addr ),
  );
  
  bind( $socket, $sa ) or do {
    AE::log fatal => "Could not bind %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };
  
  listen( $socket, $CURRENT_SETTINGS{ 'SOMAXCONN' } ) or do {
    AE::log fatal => "Could not listen %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };
  
  return $socket;
}


=item ( $addr, $port ) = B<parse_listen>()

Returns IP address $addr and port $port to listen.

=cut


sub parse_listen() {
  my ( $cur_addr, $cur_port ) = split ':', $CURRENT_SETTINGS{ 'LISTEN' };
  my ( $def_addr, $def_port ) = split ':', $DEFAULT_SETTINGS{ 'LISTEN' };
  
  $cur_addr ||= $def_addr;
  $cur_port ||= $def_port;
  
  return( $cur_addr, $cur_port );
}


=item $app = B<load_app>()

Try to load an application for Feersum. Returns a
reference to subroutine application. If the application unable
to load returns a predefined subroutine with 500 HTTP code.

=cut


sub load_app() {
  my $file = $CURRENT_SETTINGS{ 'APP_NAME' } || $DEFAULT_SETTINGS{ 'APP_NAME'};
  my $app = do( $file );
  
  if ( ref $app eq 'CODE' ) {
    return $app;
  }
      
  if ( $@ ) {
    AE::log error => "Couldn't parse %s: %s", $file, "$@";
  }
      
  if ( $! && !defined $app ) {
    AE::log error => "Couldn't do %s: %s", $file, $!;
  }
      
  if ( !$app ) {
    AE::log error => "Couldn't run %s", $file;
  }
  
  return \&_500;
}


=item B<debug_settings()>

Prints settings to output log.

=cut


sub debug_settings() {  
  my @envopts =
  (
    join( '_', uc( $PROGRAM_NAME ), 'WWW_DIR' ),
    join( '_', uc( $PROGRAM_NAME ), 'BASEDIR' ),
    join( '_', uc( $PROGRAM_NAME ), 'PIDFILE' ),
  );
  
  # print ENV values
  AE::log debug => "%s = %s", $_, $ENV{ $_ } || "" for ( @envopts );
  
  # print program settings
  AE::log debug => "%s = %s", $_, $CURRENT_SETTINGS{ $_ }
    for ( sort keys %CURRENT_SETTINGS );  
}


=item B<write_pidfile>()

Creates a pidfile. If an error occurs stops the program.

=cut


sub write_pidfile() {
  my $file = $CURRENT_SETTINGS{ 'PIDFILE' } || return;

  open( my $fh, ">", $file )
    or AE::log fatal => "open pidfile %s: %s", $file, $!;
  syswrite( $fh, $$ )
    or AE::log fatal => "write pidfile %s: %s", $file, $!;
  close( $fh )
    or AE::log fatal => "close pidfile %s: %s", $file, $!;
}


=item B<unlink_pidfile>()

Removes a pidfile from a disk.

=cut


sub unlink_pidfile() {
  my $file = $CURRENT_SETTINGS{ 'PIDFILE' } || return;
  unlink( $file )
    or AE::log error => "unlink pidfile %s: %s", $file, $!;
}


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

EV::run; scalar "Gameboy Megamix!";
