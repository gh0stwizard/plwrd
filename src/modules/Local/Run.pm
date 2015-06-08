package Local::Run;

=encoding utf-8

=head1 NAME

Execute programs with AnyEvent::Fork, AnyEvent::Fork::Pool!

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
  $pool->( $cmd, @params );

=cut

use strict;
use warnings;
use AnyEvent::Log;
use POSIX qw( :signal_h );


our $VERSION = '1.001'; $VERSION = eval "$VERSION";


# disable self logging.
# sends log messages to a parent proccess.
$AnyEvent::Log::LOG->fmt_cb
(
  sub {
    my ( $timestamp, $orig_ctx, $level, $message ) = @_;

    if ( defined &AnyEvent::Fork::RPC::event ) {
      AnyEvent::Fork::RPC::event( $level, $message );
    }

    AnyEvent::Log::default_format $timestamp, $orig_ctx, $level, $message;
  }
);

$AnyEvent::Log::LOG->log_cb( sub { } );

=head1 FUNCTIONS

=over 4

=item execute( $command, [ @args ] )

An interface for AnyEvent::Fork[::Pool] programs.
Executes a command $command with arguments @args (if present).

=cut


sub execute(@) {
  AE::log trace => "PID=$$ executing:\n@_";

  &exec_cmd( @_ );
}

=item $result = exec_cmd( $command, [ @args ] )

Executes a command $command with additional passed argmuments @args
(if present).

Returns output of a command or an error string.

=cut


sub exec_cmd ($;@) {
  my ( $do, @opt ) = @_;

  my $prog = &fix_cmd( $do, @opt );

  -e $prog or return ( AE::log error => "%s: %s", $prog, $! );

  $do = join( ' ', $prog, @opt ) if ( @opt );

  my ( $result, $status, $exit, $signal, $cdstr );

  eval {
    $result = qx( $do 2>&1 );
    $status = $?;
    $exit   = $status >> 8;
    $signal = $exit & 127;
    $cdstr  = $exit & 128 ? "with core dump " : "";

    if ( $signal or $cdstr ) {
      die sprintf
        (
          "\%s\' failed %s[exit=%d, signal=%d, result=%d]:\n%s",
          $do,
          $cdstr,
          $exit,
          $signal,
          $status,
          $result,
        )
      ;
    }
  };

  return $@ ? ( 0, $@ ) : ( 1, $result );
}


=item $program = fix_cmd( $command, [ \@arggs ] )

Extracts from a string $command an executable filename and returns it.
If the string $command contains additional arguments, 
e.g. 'my_prog arg1 arg2', they will be added via unshift to 
the \@args array reference to begining of the array.

=cut


sub fix_cmd ($;\@) {
  my ( $prog, @user_args ) = split( " ", shift );

  if ( my $args = shift ) {
    chomp @user_args;
    unshift @$args, @user_args if ( @user_args );
  }

  return $prog;
}


=item $sa = set_sa()

Creates sigaction as hash reference.
A hash reference contains next keys:

 m: signal settings for SIGALRM
 a: new action for signal SIGALRM
 o: old action

=cut


sub set_sa() {
  my %settings;

  # POSIX sigaction
  $settings{ 'm' } = POSIX::SigSet->new( SIGALRM );
  $settings{ 'a' } = POSIX::SigAction->new
  (
    sub { die "timeout\n"; }, $settings{ 'm' }
  );
  $settings{ 'o' } = POSIX::SigAction->new();

  return \%settings;
}


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

=cut

1;
