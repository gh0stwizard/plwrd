=encoding utf-8

=head1 NAME

Feersum application for plwrd

=cut

use strict;
use common::sense;
use AnyEvent;
use HTTP::Body ();
use JSON::XS ();
use Math::BigInt ();
use Local::DB::UnQLite;
use vars qw( $PROGRAM_NAME );

# body checks
my $MIN_BODY_SIZE = 4;
my $MAX_BODY_SIZE = 524288;

# http headers for responses
my @HEADER_JSON = 
( 
  'Content-Type' => 'application/json; charset=UTF-8',
);
my @HEADER_PLAIN =
( 
  'Content-Type' => 'text/plain',
);
#my @ERRORS =
#(
#  'No error',
#  'Bad request',
#  'Not implemented',
#  '',
#);

sub NO_ERROR        { 0 }
sub BAD_REQUEST     { 1 }
sub NOT_IMPLEMENTED { 2 }

# www dir with index.html (standalone mode)
my $WWW_DIR = $ENV{ join( '_', uc( $PROGRAM_NAME ), 'WWW_DIR' ) };


=head1 FUNCTIONS

=over 4

=item app( $request )

The main application function. Accepts one argument with
request object $request.

=cut

sub app {
  my ( $req ) = @_;

  my $env = $req->env();
  my $method = $env->{ 'REQUEST_METHOD' };

  if ( $method eq 'POST' ) {
    my $type = $env->{ 'CONTENT_TYPE' };
    my $len = $env->{ 'CONTENT_LENGTH' };
    my $r = delete $env->{ 'psgi.input' };
    
    my $w = $req->start_streaming( 200, \@HEADER_JSON );
    $w->write( &store_data( $r, $len, $type ) );
    $w->close();
  } elsif ( $method eq 'GET' ) {
    if ( my $query = $env->{ 'QUERY_STRING' } ) {
      AE::log trace => "query: %s", $query;

      #if ( $query =~ /^json=(\w{1,16})$/ ) {
      #  my $w = $req->start_streaming( 200, \@HEADER_JSON );
      #  $w->write( &load_post( $1 ) );
      #  $w->close();
      #} else {
        &_501( $req );
      #}
    } else {
      # when working standalone, i.e. without nginx
      #require Local::Feersum::Tiny;
      #&Local::Feersum::Tiny::send_file( $WWW_DIR, $req );
      &_500( $req );
    }
  } else {
    &_405( $req );
  }
  
  return;
}

=item get_params( $request, $length, $content_type )

Reads HTTP request body. Returns hash reference with request parameters.
A key represents a name of parameter and it's value represents an actual value.

=cut

sub get_params($$$) {
  my ( $r, $len, $content_type ) = @_;
  
  # reject empty, small or very big requests
  return if ( ( $len < $MIN_BODY_SIZE ) || ( $len > $MAX_BODY_SIZE ) );

  my $body = HTTP::Body->new( $content_type, $len );
  
  # TODO: $body->tmpdir( $TMP_DIR );
  
  $body->cleanup( 1 );
  
  my $pos = 0;
  my $rbuf_size = 32768;
  my $chunk_len = ( $len > $rbuf_size ) ? $rbuf_size : $len;

  while ( $pos < $len ) {
    $r->read( my $buf, $chunk_len ) or last;
    $body->add( $buf );
    $pos += $chunk_len;
  }

  $r->close();
  
  return $body->param();
}

=item store_data( $request, $length, $content_type )

Stores data to DB by request. Actual value for data depends on $request.

=cut

sub store_data($$$) {
  my $params = &get_params( @_ )
    or return &JSON::XS::encode_json( { 'err' => &BAD_REQUEST() } );
  
  AE::log trace => " %s => %s", $_, $params->{ $_ } for keys %$params;

  my %response = ( 'err' => &NOT_IMPLEMENTED() );
  my $action = $params->{ 'action' } || "";
  
  if ( $action eq 'addApp' ) {
    
  }
  
  return &JSON::XS::encode_json( \%response ); 
}

=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

=cut

\&app;
