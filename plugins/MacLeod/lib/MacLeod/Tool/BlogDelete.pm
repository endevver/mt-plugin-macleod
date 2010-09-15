package MacLeod::Tool::BlogDelete;
use strict; use warnings; use Carp; use Data::Dumper;

use Pod::Usage;
use File::Spec;
use Data::Dumper;
use MT::Util qw( caturl );
use Cwd qw( realpath );

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
our $logger = MT::Log::Log4perl->new();

use base qw( MT::App::CLI );
# use MacLeod::Util;

$| = 1;
our ( %classes_seen, $opt );

sub usage { 
    return <<EOD;
Usage: $0 [options] BLOG_NAME_PATTERN
Options:
    --cols      Comma-separated list of columns to show in output.
                Default is "id,name,site_url"
    --force     Don't prompt for confirmation of actions
    --verbose   Output more progress information. 
                Can be used multiple times for more logging.
    --man       Output the man page for the utility
    --help      Output this message
EOD
}

sub help { q{ This is a blog deletion script } }

sub option_spec {
    return ( 'cols:s', $_[0]->SUPER::option_spec() );
}

sub init_options {
    my $app = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    # $app->show_usage() unless @ARGV;

    $app->SUPER::init_options(@_) or return;
    $opt = $app->options || {};
    $opt->{cols} = ref $opt->{cols} eq 'ARRAY' 
                 ? $opt->{cols} 
                 : [ split( /\s*,\s*/, ($opt->{cols} || 'id,name,site_url') )];

    $opt->{ipatt} = shift @ARGV if @ARGV;

    require Sub::Install;
    Sub::Install::reinstall_sub({
      code => 'remove_children_logged',
      into => 'MT::Object',
      as   => 'remove_children',
    });

    ###l4p $logger->debug('$opt: ', l4mtdump( $opt ));
    1;
}

sub mode_default {
    my $app    = shift;
    my $opt   = $app->options();
    my $blogs = $app->blog_list();

    @$blogs or return "No blogs matched your specifications";

    my $continue = $opt->{force};
    $continue  ||= $app->confirm_delete_blogs( $blogs );
    my $out;
    if ( $continue ) {
        my $count = $app->delete_blogs( $blogs );
        return "$count blogs deleted.";
    }
    else {
        return "Blog deletion aborted";
    }
}

sub confirm_delete_blogs {
    my ( $app, $blogs_to_delete ) = @_;
    my $opt = $app->options();

    print "----------------------------------------------------\n";
    print "The following blogs will be deleted: \n";
    foreach my $blog ( @$blogs_to_delete ) {
        printf "%-5s %-30s %s\n", 
                    map { $blog->$_ } @{ $opt->{cols} };
    }

    return $app->confirm_action(
        "Would you like to delete the blogs above? (y/N) "
    );
}

sub blog_list {
    my ( $app ) = @_;
    my $opt = $app->options();
    my $patt = $opt->{ipatt};
    require MT::Blog;
    my $iter = MT::Blog->load_iter();
    my @blogs;
    while (my $blog = $iter->()) {
        next if defined $patt and $blog->name !~ m/^$patt$/i;
        push @blogs, $blog;
    }
    return @blogs ? \@blogs : [];
}

sub delete_blogs {
    my $app   = shift;
    my $blogs = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $opt   = $app->options();
    my $count = 0;
    my $plugin = $app->component('MacLeod');

    foreach my $blog ( @$blogs ) {
        my $status = 'DELETING';
        my $blog_line = sprintf "%-5s %-30s %s",
                            map { $blog->$_ } @{ $opt->{cols} };
        my $update = sprintf( "%-12s %s\n", $status, $blog_line );
        ###l4p $logger->info( $update );
        print $update;

        if ($blog->remove({ nofetch => 1 })) {
            $status = 'DELETED';
            $count++;
        }
        else {
            $status = 'NOT DELETED';
        }
        $update = sprintf( "%-12s %s\n", $status, $blog_line );
        ###l4p $logger->info( $update );
        print $update;
    }
    return $count;
}

sub remove_children_logged {
    my $obj = shift;
    return 1 unless ref $obj;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    my ($param) = @_;
    my $child_classes = $obj->properties->{child_classes} || {};
    my @classes = keys %$child_classes;
    return 1 unless @classes;

    $param ||= {};
    my $key = $param->{key} || $obj->datasource . '_id';
    my $obj_id = $obj->id;
    for my $class (@classes) {
        eval "# line " . __LINE__ . " " . __FILE__ . "\nno warnings 'all';require $class;";
        my $msg;
        if ( $opt->{verbose} > 1 ) {
            my $child_cnt = $class->count({ $key => $obj_id }) || 0;
            $msg = "REMOVING $child_cnt $class records";
        }
        elsif ( $opt->{verbose} ) {
            $msg = "REMOVING $class records";
        }
        if ( $msg ) {
            ###l4p $logger->info( $msg );
            print $msg."\n" if $msg;
        }
        $class->remove({ $key => $obj_id }, { nofetch => 1 });
    }
    1;
}

1;

__END__
