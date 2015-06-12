package Local::DB::UnQLite;

=encoding utf-8

=head1 NAME

UnQLite database interface for simple apps.

=cut

=head1 DESCRIPTION

This is a simple interface to L<UnQLite> module for
small applications.

It is using the "cache" technique when database instances (or
database descriptors) are not closed automatically while 
an application is running. That's mean that you are able
to call C<<< Local::DB::UnQLite->new( 'mydb' ) >>> and forget to
keep a reference to it's object. The database will not
be closed until you call C<<< $db->close( 'mydb' ) >>> or
C<<< $db->closealldb() >>> methods.

Such implementation will helps keeping your code as simple
as possible (at least, I hope so).

=cut


use strict;
use UnQLite;
use Encode ();
use File::Spec::Functions qw( catfile canonpath );
use JSON::XS qw( decode_json );


our $VERSION = '1.003'; $VERSION = eval $VERSION;


=head1 FUNCTIONS

=over 4

=item $unqlite = B<initdb>( $name )

Initialize a database instance. Creates database with a
file name "<DB_HOME>/$name.db". Where is <DB_HOME> is
value returned by function B<get_db_home>().

A value $name should not contains any file extention.
The file name extention is hardcoded and always equals
to ".db".

The function calls C<die()> if an error has been occured.

=cut


{
  my %DBS;
  
  sub new {
    my ( $class, $name ) = @_;
    
    my $self = bless \$name, $class;
    &initdb( $name ) if ( not exists $DBS{ $name } );
    
    return $self;
  }

  sub initdb($) {
    my $name = shift || "none";
    
    #
    # UnQLite <= 0.05 does not check file permissions
    # and does not throw errors about that.
    #
    # We have to be sure that able to open (read, write) file.
    #

    my $db_home = &get_db_home();
    my $db_file = catfile( $db_home, "${name}.db" );
    my $db_flags = &UnQLite::UNQLITE_OPEN_READWRITE();
  
    if ( -e $db_file ) {
      # file exists, check perms
      unless ( -r $db_file && -w $db_file && -o $db_file ) {
        die "Check permissions on $db_file: $!";
      }
    } else {
      # file does not exists, try to create file
      open ( my $fh, ">", $db_file )
        or die "Failed to open $db_file: $!";
      close( $fh )
        or die "Failed to close $db_file: $!";
      unless ( -r $db_file && -w $db_file && -o $db_file ) {
        die "Check permissions on $db_file: $!";
      }
      unlink( $db_file )
        or die "Failed to remove $db_file: $!";

      # auto create database file
      $db_flags |= &UnQLite::UNQLITE_OPEN_CREATE();
    }
  
    $DBS{ $name } = UnQLite->open( $db_file, $db_flags );
    return $DBS{ $name };
  }


=item B<closedb>( $name )

Closes a database handler identified by $name.

=cut


  sub closedb($) {
    my $name = shift || "none";
  
    delete $DBS{ $name } if ( exists $DBS{ $name } );
    return;
  }


=item B<closealldb>()

Closes all database handlers.

=cut


  sub closealldb() {
    delete $DBS{ $_ } for keys %DBS;
    return;
  }

  sub _get_instance($) {
    return $DBS{ "$_[0]" } if exists $DBS{ "$_[0]" };
    return;
  }
}


=item $db_home = B<get_db_home>()

Returns DB home directory. Default is ".";

=cut


{
  my $DB_HOME_DIR = '.';

  sub get_db_home() {
    return canonpath( $DB_HOME_DIR );
  }


=item $db_home = B<set_db_home>( $string )

Sets DB home directory to specified value $string.

=cut

  
  sub set_db_home($) {
    $DB_HOME_DIR = "$_[0]" if ( $_[0] );
    $DB_HOME_DIR;
  }
}


=back

=head1 METHODS

=over 4

=item $db = B<new>( $name )

Creates or returns existing dabatase instance object.
See a B<initdb>() function for details.


=item $rv = B<store>( $key, $value )

Calls kv_store( $key, $value ). Returns true if successed.

=cut


sub store($$$) {
  #my ( $self, $key, $data ) = @_;
  
  my $db = _get_instance ${ $_[0] };
  # returns 1 if success or undef if failed
  return $db->kv_store( $_[1], $_[2] );
}


=item $data = B<fetch>( $key )

Calls kv_fetch( $key ).

=cut


sub fetch($$) {
  #my ( $self, $key ) = @_;
  
  my $db = _get_instance ${ $_[0] };
  my $entry = $db->kv_fetch( $_[1] ) || return;
  
  return ( &Encode::is_utf8( $entry ) )
    ? &Encode::decode_utf8( $entry )
    : $entry;
}


=item $data = B<fetch_json>( $key )

Calls kv_fetch( $key ). An entry will be decoded by
C<JSON::XS::decode_json()> function.

=cut


sub fetch_json($$) {
  #my ( $self, $key ) = @_;
  
  my $db = _get_instance ${ $_[0] };
  my $entry = $db->kv_fetch( $_[1] ) || return;
  
  return ( &Encode::is_utf8( $entry ) )
    ? decode_json( &Encode::decode_utf8( $entry ) )
    : decode_json( $entry );  
}


=item $rv = B<delete>( $key )

Delete entry specified by a key $key from a database.
Calls kv_delete( $key ).

=cut


sub delete( $key ) {
  #my ( $self, $key ) = @_;
  
  my $db = _get_instance ${ $_[0] };
  return $db->kv_delete( $_[1] );
}


=item $num_deleted = B<delete_all>()

Deletes all entries from database.

=cut


sub delete_all($) {
  my $db = _get_instance ${ $_[0] };
  my $cursor = $db->cursor_init();

  my $num_deleted = 0;
  for ( $cursor->first_entry();
        $cursor->valid_entry(); )
  {
    $cursor->delete_entry() && $num_deleted++;
  }
  
  return $num_deleted;
}


=item $num = B<entries>()

Returns a number of entries stored in a database.

=cut


sub entries($) {
  my $db = _get_instance ${ $_[0] };
  my $cursor = $db->cursor_init();
  
  my $entries = 0;
  for ( $cursor->first_entry();
        $cursor->valid_entry();
        $cursor->next_entry() )
  {
    $entries++;
  }
  
  return $entries;
}


=item $ary = B<all>()

Returns all entries as an array reference.

=cut


sub all($) {
  my $db = _get_instance ${ $_[0] };
  my $cursor = $db->cursor_init();
  
  my @list;
  for ( $cursor->first_entry();
        $cursor->valid_entry();
        $cursor->next_entry() )
  {
    push @list, &Encode::decode_utf8( $cursor->data() );
  }
  
  return \@list;
}

=item $ary = B<all_json>()

Returns all entries as an array reference. Each entry will be
decoded by C<JSON::XS::decode_json()> function.

=cut


sub all_json($) {
  my $db = _get_instance ${ $_[0] };
  my $cursor = $db->cursor_init();
  
  my @list;
  for ( $cursor->first_entry();
        $cursor->valid_entry();
        $cursor->next_entry() )
  {
    push @list,
      decode_json( &Encode::decode_utf8( $cursor->data() ) );
  }
  
  return \@list;
}


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

scalar "Cold Chord (Human Element Remix)";
