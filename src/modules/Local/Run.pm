package Local::Run;

# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.

use strict;
use warnings;
use AnyEvent::Log;
use POSIX qw( :signal_h );


our $VERSION = '1.006'; $VERSION = eval "$VERSION";


=encoding utf-8

=head1 NAME

Executing programs with AnyEvent::Fork, AnyEvent::Fork::Pool.

=head1 SYNOPSYS

  # create pool
  my $pool = AnyEvent::Fork->new()
    ->require( "Local::Run" )
    ->AnyEvent::Fork::Pool::run
      (
        'Local::Run::execute',
        on_event => sub { AE::log $_[0] => $_[1] },
      )
  ;
  
  # execute command
  $pool->( $cmd, @params, sub {
    my ( $rv, $output ) = @_;

  } );

=cut


# disable self logging.
# sends log messages to a parent proccess.
$AnyEvent::Log::LOG->fmt_cb
(
  sub {
    my ( $timestamp, $orig_ctx, $level, $message ) = @_;

    if ( defined &AnyEvent::Fork::RPC::event ) {
      AnyEvent::Fork::RPC::event( $level, "PID = $$ " . $message );
    }

    AnyEvent::Log::default_format $timestamp, $orig_ctx, $level, $message;
  }
);

$AnyEvent::Log::LOG->log_cb( sub { } );


=head1 FUNCTIONS

=over 4

=item B<execute>( $command, [ @args ], $cb )

An interface for AnyEvent::Fork[::Pool] programs.
Executes a command $command with arguments @args (if present).
Calls a callback $cb when executing a program is finished.

=cut


sub execute(@ ) {
  AE::log trace => "execute():\n@_";

  &exec_cmd( @_ );
}


=item B<execute_logged>( %setup, $cb )

An interface for AnyEvent::Fork[::Pool] programs.
See B<exec_cmd_logged>() for details about a hash %setup.
Calls a callback $cb when executing a program is finished.

=cut


sub execute_logged(@) {
  AE::log trace => "execute_logged():\n@_";

  &exec_cmd_logged( @_ );
}


=item B<execute_logged_safe>( %setup, $cb )

An interface for AnyEvent::Fork[::Pool] programs.
See B<exec_cmd_logged_safe>() for details about a hash %setup.
Calls a callback $cb when executing a program is finished.

=cut


sub execute_logged_safe(@) {
  AE::log trace => "execute_logged_safe():\n@_";

  &exec_cmd_logged_safe( @_ );
}


=item ( $rv, $out ) = B<exec_cmd>( $command, [ @args ] )

Executes a command $command with additional passed argmuments @args
(if present).

Returns a status $rv (1: success, 0: failed ) and 
an output of a command or an error string $out.

=cut


sub exec_cmd ($;@) {
  my ( $do, @opt ) = @_;

  my $prog = &get_cmd_path( $do, @opt );

  $do = join( ' ', $prog, @opt ) if ( @opt );

  my $output = qx( $do 2>&1 ) || return ( 0, $! );
  my $result = $?;
  my $exit   = $result >> 8;
  my $signal = $exit & 127;
  my $cdump  = $exit & 128 ? "with core dump " : "";

  if ( $signal or $cdump ) {
    return ( 0, sprintf
      (
        "\`%s\' failed %s[exit=%d, signal=%d, result=%d]:\n%s",
        $do,
        $cdump,
        $exit,
        $signal,
        $result,
        $output || '',
      )
    );
  }
  
  return ( 1, $output );
}


=item B<exec_cmd_logged>( %setup )

Same as B<exec_cmd>(), but you have to pass additional arguments.
The structure of hash setup %setup supposed to be like that:

  %setup = 
  (
    stdout => '/path/to/stdout.log', # when missing using /dev/null or NUL on MSWin32
    stderr => '/path/to/stderr.log', # when missing redirect to stdout
    command => $command,
  );

Returns

=cut

sub exec_cmd_logged(%) {  
  my %setup = @_;
  
  my $do = $setup{ 'command' };
  my $prog = &get_cmd_path( $do );

  my $stdout = $setup{ 'stdout' }; # ( $^O eq 'MSWin32' ) ? 'NUL' : '/dev/null';
  my $stderr = $setup{ 'stderr' } || '&1';
  
  qx( $do 1>$stdout 2>$stderr );
  my $rv = $?;
  
  AE::log trace => "$do 1>$stdout 2>$stderr %s",
    ( $rv ) ? 'failed' : 'completed successfully',
    $rv
  ;

  return $rv == 0;
}


=item B<exec_cmd_logged_safe>( %setup )

Same as B<exec_cmd_logged>() but with additional arguments:

=over

=item timeout

Limit command execution by timeout value in seconds.
Default is 10.

=item euid

Calls B<seteuid>() system call to change an effective user id.

Use this only combined with B<chroot> parameter.

=item chroot

Chroot to a specified directory. The B<chroot>() system call
used only at first time because there is too much work to
escape chroot environment.

Use this only combined with B<euid> parameter.

=back

=cut


sub exec_cmd_logged_safe(%) {
  my %setup = @_;
  
  my $ename = $setup{ 'euid' };
  my $chroot_dir = $setup{ 'chroot' };
  
  if ( $ename and $chroot_dir ) {
    &set_euid( $ename, $chroot_dir )
      or AE::log error => "set_euid %s failed", $ename;
  }
  
  my $do = $setup{ 'command' };
  my $prog = &get_cmd_path( $do );

  my $stdout = $setup{ 'stdout' } || '/dev/null';
  my $stderr = $setup{ 'stderr' } || '/dev/null';
  my $timeout = $setup{ 'timeout' } || 10;
  my $rv;
  
  local $@;
  local $SIG{__DIE__} = sub {
    my $msg = "$_[0]";
    
    if ( $msg =~ /^::timeout::/o ) {
      AE::log trace => $msg;
      # write an error message to log file
      $msg = "killed because of execution timeout ($timeout)";
    }

    # write error message to logfile
    &_write_msg_file( $stderr, $msg );
    
    # remove SIGDIE handler
    $SIG{__DIE__} = undef;
    # an command execution has failed
    $rv = 1;
  };    
  
  my $sa = &set_sa();

  sigaction( SIGALRM, $sa->{ 'a' }, $sa->{ 'o' } );

  eval {
    eval {
      alarm $timeout;
      qx( $do 1>$stdout 2>$stderr );
      $rv = $?;
    };
    
    alarm 0;
    die $@ if $@;
  };
  
  sigaction( SIGALRM, $sa->{ 'o' } );
  
  AE::log trace => "$do 1>$stdout 2>$stderr %s [%d]",
    ( $rv ) ? 'failed' : 'completed successfully',
    $rv
  ;
  
  return ( $rv == 0 );
}


=item $program = B<get_cmd_path>( $command, [ \@arggs ] )

Extracts from a string $command an executable filename and returns it.
If the string $command contains additional arguments, 
e.g. 'my_prog arg1 arg2', they will be added via unshift to 
the \@args array reference to begining of the array.

=cut


sub get_cmd_path($;\@) {
  my ( $prog, @user_args ) = split( " ", shift );

  if ( my $args = shift ) {
    chomp @user_args;
    unshift @$args, @user_args if ( @user_args );
  }

  return $prog;
}


=item $sa = B<set_sa>()

Creates a sigaction for the signal SIGALRM as hash reference.
The hash reference contains next keys:

 m: the signal settings for SIGALRM
 a: a new action for signal SIGALRM
 o: an old action
 
When a signal SIGALRM approaches a new action calls
subroutine C<<< die "::timeout::" >>>.

=cut


sub set_sa() {
  my %settings;

  # POSIX sigaction
  $settings{ 'm' } = POSIX::SigSet->new( SIGALRM );
  $settings{ 'a' } = POSIX::SigAction->new
  (
    sub { die "::timeout::"; }, $settings{ 'm' }
  );
  $settings{ 'o' } = POSIX::SigAction->new();

  return \%settings;
}


sub _write_msg_file($$) {
  my ( $file, $msg ) = @_;
  
  if ( open( my $fh, '>>', $file ) ) {
    syswrite $fh, "$msg";
    close $fh;
  } else {
    AE::log error => "open %s: %s", $file, $!;
  }
  
  return;
}


=item B<set_euid>( $euid, $chroot_dir ) 

Sets an effective user id I<$euid>. This works only under
I<superuser> account. The type of I<$euid> is a number.

Returns true on success.

=cut


sub set_euid($$) {
  my ( $ename, $chroot_dir ) = @_;
  
  AE::log trace => "\$< = %s, \$> = %s", $<, $>;

  $> == 0 or return 1; # seteuid() already done
  $< == 0 or return 0;
  
  # remember $euid
  my ( $name, undef, $euid ) = getpwnam( $ename );
  
  defined( $euid ) or do {
    AE::log error => "set_euid getpwnam failed: %s", $!;
    return 0;
  };
  
  # chroot
  chroot( $chroot_dir ) or do {
    AE::log error => "set_euid chroot( %s ): %s",
      $chroot_dir,
      $!
    ;
    return 0;
  };
    
  # chdir to root directory
  chdir( '/' ) or do {
    AE::log error => "set_euid chdir( / ): %s", $!;
    return 0;
  };

  # seteuid
  
  $> = $euid;
  $< = $euid unless $!;

  if ( $! ) {
    AE::log error => "set_euid NAME = %s, EUID = %d: %s",
      $ename,
      $euid || 'NaN',
      $!
    ;
    return 0;
  } else {
    AE::log debug => "real uid = %d, effective uid = %d", $<, $>;
    return 1;
  }

}


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

1;
