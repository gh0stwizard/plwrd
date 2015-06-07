package Local::DB::UnQLite;

=encoding utf-8

=head1 NAME

UnQLite database interface for simple apps.

=cut

use strict;
use UnQLite;
use Encode ();
use File::Spec::Functions qw( catfile canonpath );


our $VERSION = '1.000'; $VERSION = eval $VERSION;


=head1 FUNCTIONS

=over 4

=item initdb( $name )

Initialize database instance. Creates database with a
file name "<DB_HOME>/$name.db". Where is <DB_HOME> is
value returned by function get_db_home().

A value $name should not contains any file extention.
The file name extention is hardcoded and always equals
to ".db".

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

=item closedb( $name )

Closes a database handler identified by $name.

=cut

  sub closedb($) {
    my $name = shift || "none";
  
    delete $DBS{ $name };
    return;
  }

=item closealldb()

Closes database handlers.

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

=item get_db_home()

Returns DB home directory. Default is ".";

=cut

{
  my $DB_HOME_DIR = '.';

  sub get_db_home() {
    return canonpath( $DB_HOME_DIR );
  }

=item set_db_home( $string )

Sets DB home directory to specified value $string.

=cut
  
  sub set_db_home($) {
    $DB_HOME_DIR = "$_[0]" if ( $_[0] );
  }
}

=back

=head1 METHODS

=over 4

=item new( $name )

Creates or returns existing dabatase instance object.
See opendb() function for details.

=item store( $key, $value )

Calls kv_store( $key, $value ).

=cut

sub store($$$) {
  #my ( $self, $post_id, $data ) = @_;
  
  my $db = _get_instance ${ $_[0] };
  # returns 1 if success or undef if failed
  return $db->kv_store( $_[1], $_[2] );
}

=item fetch( $key )

Calls kv_fetch( $key).

=cut

sub fetch($) {
  #my ( $self, $post_id ) = @_;
  
  my $db = _get_instance ${ $_[0] };
  return &Encode::decode_utf8( $db->kv_fetch( $_[1] ) );
}

=item delete_all()

Deletes all entries from database.

=cut

sub delete_all($) {
  my $db = _get_instance ${ $_[0] };
  my $cursor = $db->cursor_init();

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

=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

=cut

scalar "Cold Chord (Human Element Remix)";
