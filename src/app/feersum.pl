#!/usr/bin/perl

# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.

=encoding utf-8

=head1 NAME

Application for plwrd written with Feersum backend.

=cut


use strict;
use common::sense;
use AnyEvent;
use HTTP::Body ();
use JSON::XS qw( encode_json decode_json );
use Local::DB::UnQLite;
use Scalar::Util qw();
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

# www dir with index.html (standalone mode)
my $WWW_DIR = $ENV{ join( '_', uc( $PROGRAM_NAME ), 'WWW_DIR' ) };

# set DB home for UnQLite module
my $BASE_DIR = $ENV{ join( '_', uc( $PROGRAM_NAME ), 'BASEDIR' ) };
&Local::DB::UnQLite::set_db_home( $BASE_DIR );


=head1 FUNCTIONS

=over 4

=cut

sub CONNECTION_ERROR  { 0 } # Connection error
sub BAD_REQUEST       { 1 } # Bad request
sub NOT_IMPLEMENTED   { 2 } # Not implemented
sub EINT_ERROR        { 3 } # Internal error
sub DUPLICATE_ENTRY   { 4 } # Duplicate entry in a database
sub NOT_FOUND         { 5 } # Not found


=item B<app>( $request )

The main application function. Accepts one argument with
request object $request.

=cut


sub app {
  my ( $req ) = @_;

  my $env = $req->env();
  my $method = $env->{ 'REQUEST_METHOD' };

  if ( $method eq 'POST' ) {
    # POST methods are using to store data to a database
    my $type = $env->{ 'CONTENT_TYPE' };
    my $len = $env->{ 'CONTENT_LENGTH' };
    my $r = delete $env->{ 'psgi.input' };
    
    my $w = $req->start_streaming( 200, \@HEADER_JSON );
    $w->write( &store_data( $r, $len, $type ) );
    $w->close();
  } elsif ( $method eq 'GET' ) {
    # GET methods are using to retrieve data from a database
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

      # TODO: test code below (should work)
      #
      #require Local::Feersum::Tiny;
      #&Local::Feersum::Tiny::send_file( $WWW_DIR, $req );

      &_500( $req );
    }
  } else {
    &_405( $req );
  }
  
  return;
}


=item B<get_params>( $request, $length, $content_type )

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


=item $json = B<store_data>( $request, $length, $content_type )

Stores data to DB by request. Actual value for data depends on $request.
Returns a JSON string with result.

=cut


sub store_data($$$) {
  my $params = &get_params( @_ )
    or return encode_json( { 'err' => &BAD_REQUEST() } );
  
  AE::log trace => " %s => %s", $_, $params->{ $_ } for keys %$params;

  my %response = ( 'err' => &NOT_IMPLEMENTED() );
  my $action = delete $params->{ 'action' } || "";
  
  if ( $action eq 'addApp' ) {
    my $kv = $params->{ 'name' };
    my $db = Local::DB::UnQLite->new( 'apps' );
    
    if ( ! $db->fetch( $kv ) ) {
      # using 'name' parameter as unique key
      $db->store( $kv, encode_json( $params ) )
        ? ( %response = ( 'id' => $kv ) )
        : ( %response = ( 'err' => &EINT_ERROR() ) );
    } else {
      %response = ( 'err' => &DUPLICATE_ENTRY() );
    }
  } elsif ( $action eq 'delApp' ) {
    my $kv = $params->{ 'name' };
    my $db = Local::DB::UnQLite->new( 'apps' );
    
    if ( $db->fetch( $kv ) ) {
      $db->delete( $kv )
        ? ( %response = ( 'id' => $kv ) )
        : ( %response = ( 'err' => &EINT_ERROR() ) );
    } else {
      %response = ( 'err' => &NOT_FOUND() );
    }    
  } elsif ( $action eq 'wipeApps' ) {
    # remove all entries from apps.db
    my $num = Local::DB::UnQLite->new( 'apps' )->delete_all();
    %response = ( 'wiped' => $num );
  }
  
  return encode_json( \%response ); 
}


=item $json = B<retrieve_data>( $request, $action, $key )

Virtual function: retrieves data from a database, performs action.

When possible returns a JSON string immediatly, when not returns nothing,
but later calls $request->write( $json ) by itself.

=cut


sub retrieve_data(@) {
  my ( $r, $action, $kv ) = @_;
  
  my %response = ( 'err' => &NOT_IMPLEMENTED() );
  
  if ( $action eq 'runApp' ) {  
    # run application

    if ( my $data = Local::DB::UnQLite->new( 'apps' )>fetch( $kv ) ) {
      AE::log trace => "%s: %s", $kv, $data;

      my $cb = sub {
        my ( $rv, $out ) = @_;
        
        &Scalar::Util::weaken( my $r = $r );
        
        my $w = $r->start_streaming( 200, \@HEADER_JSON );
        $w->write( encode_json(
          {
            'action' => 'runApp',
            'name' => $kv,
            'result' => $rv,
            'output' => $out,
          } 
        ) );
        $w->close();
      };
      
      # see backend/feersum.pl
      pool_exec( $data->{ 'cmd' }, $cb );
      
      # deffer response
      return;
    } else {
      %response = ( 'err' => &NOT_FOUND() );
    }
  }
  
  return encode_json( \%response );
}


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

\&app;
