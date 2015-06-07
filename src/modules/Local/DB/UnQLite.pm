package Local::DB::UnQLite;

=encoding utf-8

=head1 NAME

UnQLite database interface for simple apps.

=cut

use strict;
use UnQLite;
use Encode ();
use File::Spec::Functions ();

our $VERSION = '0.002'; $VERSION = eval $VERSION;

my $BASEDIR = ( exists $ENV{ 'PLWRD_BASEDIR' } )
  ? $ENV{ 'PLWRD_BASEDIR' }
  : '.'
;

my $INSTANCE;

{
#
# keep db open all the time
#
  my $db_file = &File::Spec::Functions::catfile( $BASEDIR, 'plwrd.db' );
  my $db_flags = &UnQLite::UNQLITE_OPEN_READWRITE();
  
  #
  # UnQLite <= 0.05 does not check file permissions
  # and does not throw errors.
  #
  # We must be sure that able to open (read, write) file.
  #
  if ( -e $db_file ) {
    # file exists, check perms
    unless ( -r $db_file && -w $db_file && -o $db_file ) {
      die "Check permissions on $db_file: $!";
    }
  } else {
    # file does not exists, try to create file
    open ( my $fh, ">", $db_file )
      or die "Failed to open $db_file: $!";
    syswrite( $fh, "test\n", 5 )
      or die "Failed to write $db_file: $!";
    close( $fh )
      or die "Failed to close $db_file: $!";
    open ( my $fh, "<", $db_file )
      or die "Failed to open $db_file: $!";    
    sysread( $fh, my $buf, 5 )
      or die "Failed to read $db_file: $!";
    close( $fh )
      or die "Failed to close $db_file: $!";
    unlink( $db_file )
      or die "Failed to remove $db_file: $!";
    
    # auto create database file
    $db_flags |= &UnQLite::UNQLITE_OPEN_CREATE();
  }
  
  $INSTANCE = UnQLite->open( $db_file, $db_flags );
}


=head1 METHODS

=over 4

=item store( $key, $value )

Calls kv_store( $key, $value ).

=cut

sub store($$) {
  #my ( $post_id, $data ) = @_;
  
  # returns 1 if success or undef if failed
  return $INSTANCE->kv_store( $_[0], $_[1] );
}

=item fetch( $key )

Calls kv_fetch( $key).

=cut

sub fetch($) {
  #my ( $post_id ) = @_;
  
  return &Encode::decode_utf8( $INSTANCE->kv_fetch( $_[0] ) );
}

=item delete_all()

Deletes all entries from database.

=cut

sub delete_all() {
  my $cursor = $INSTANCE->cursor_init();

  my $num_deleted = 0;  
  for ( $cursor->first_entry();
        $cursor->valid_entry();
        $cursor->next_entry() )
  {
    $cursor->delete_entry();
    $num_deleted++;
  }
  
  return $num_deleted;
}

=item entries()

Returns a number of entries stored in a database.

=cut

sub entries() {
  my $cursor = $INSTANCE->cursor_init();
  
  my $entries = 0;
  for ( $cursor->first_entry();
        $cursor->valid_entry();
        $cursor->next_entry() )
  {
    $entries++;
  }
  
  return $entries;
}

=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

=cut

scalar "Cold Chord (Human Element Remix)";
