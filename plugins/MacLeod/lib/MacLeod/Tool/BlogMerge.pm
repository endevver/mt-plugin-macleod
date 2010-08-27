package MacLeod::Tool::BlogMerge;
use strict; use warnings; use Carp; use Data::Dumper;

use vars qw( $VERSION );
$VERSION = '1.0';

use Pod::Usage;
use File::Spec;
use MT::Util qw( caturl );
use Cwd qw( realpath );

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();

use base qw( MT::App::CLI );
# use MacLeod::Util;

$| = 1;
our %classes_seen;

sub usage { 
    return <<EOD;
Usage: $0 [options] SRC_BLOG TARGET_BLOG
Options:
    --perms      Also merge user/group associations (i.e. permissions)
    --cats FILE  Also merge categories/folders, w/ optional CSV control file
    --dryrun     Run through without modifying anything
    --force      Don't prompt for confirmation of actions
    --verbose    Output more progress information
    --man        Output the man page for the utility
    --help       Output this message
EOD
}

sub help { q{ This is a blog merging script } }

sub option_spec {
    return ( 'dryrun|d', 'perms|p', 'cats|c=s', 'force|f',
               $_[0]->SUPER::option_spec()    );
}

sub init_options {
    my $app = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    $app->show_usage() unless @ARGV;

    $app->SUPER::init_options(@_) or return;
    my $opt = $app->options || {};
    my $inst = $app->registry('merge_instructions');

    $opt->{verbose}++ if $opt->{dryrun};

    unless ( $opt->{srcblog} && $opt->{targetblog} ) {
        @ARGV == 2 or return $app->error(
            'You must specify two and only two blogs '
            .'by their ID or the full, exact name' );

        ( $opt->{srcblog}, $opt->{targetblog} )
            = map { $app->load_by_name_or_id( 'blog', $_ ) } @ARGV;

        return unless $opt->{srcblog} && $opt->{targetblog};
    }

    if ( $opt->{cats} ) {
        require Text::CSV;
        my $csv = Text::CSV->new({ binary => 1 })  # should set binary attribute.
            or die "Cannot use CSV: ".Text::CSV->error_diag ();
        open my $fh, "<:encoding(utf8)", $opt->{cats}
            or die $opt->{cats}.": $!";
        $opt->{catcsv} = $fh;
        delete $inst->{$_}{skip} foreach qw( category placement ping_cat );
    }

    if ( $opt->{perms} ) {
        print 'BEFORE $inst->{association}{skip}: '
              .$inst->{association}{skip}."\n";
        delete $inst->{association}{skip};
        delete $inst->{permission}{skip};
        # print 'AFTER $inst->{association}{skip}: '.$inst->{association}{skip}."\n";
        
        unless ( $opt->{dryrun} ) {
            my $cb = sub { 
                ###l4p $logger->info('In TakeDown callback removing old blog perms');
                $app->model('permission')->remove({
                    blog_id => $opt->{srcblog}->id
                });
            };
            ###l4p $logger->info('Adding TakeDown callback for removing permissions from old blog');
            MT->add_callback( 'take_down', 1, $app, $cb );
        }
    }
    ###l4p $logger->debug('$opt: ', l4mtdump( $opt ));
    1;
}

sub mode_default {
    my $app    = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $opt            = $app->options();
    my ($src, $target) = ( $opt->{srcblog}, $opt->{targetblog} );

    $MT::DebugMode = 11 if $opt->{verbose};

    my $obj_to_merge = $app->_populate_obj_to_merge( $src->id );
    ###l4p $logger->debug('obj_to_merge: ', l4mtdump($obj_to_merge));

    my $continue = $opt->{force};
    $continue  ||= $app->confirm_merge_blog_data( $obj_to_merge, 
                                                  $src, $target );
    my $out;
    if ( $continue ) {
        $app->merge_blog_data( $obj_to_merge, $src, $target );
        $out = 'You can find a list of asset and entry redirects '
             . 'by filtering your log4mt logfile for the phrase '
             . '"REDIRECT URL"';
        return "All requested merge operations complete. $out";
    }
    else {
        return "Merge of blog data aborted";
    }
}

sub merge_blog_data {
    my ( $app, $obj_to_merge, $src, $target ) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $opt  = $app->options();
    my $inst = $app->registry('merge_instructions');

    $| = 1;
    foreach my $objhash ( @$obj_to_merge ) {
        while ( my ($class, $loadargs) = each %$objhash ) {
            my $total = $class->count( $loadargs->{terms},
                                       $loadargs->{args}   );
            my $line_header = ($opt->{dryrun} ? '(Mock)' : '')
                            . "Upgrading $total $class objects";
            $logger->info( $line_header );

            my $obj_cnt = 0;
            my $iter = $class->load_iter(   $loadargs->{terms},
                                            $loadargs->{args}   );
            while ( my $obj = $iter->() ) {
                $app->print("\r$line_header: ".++$obj_cnt);
                $obj->merge_operation( $src, $target )
                    unless $opt->{dryrun};
            }

            # Final reporting for object type
            my $final_msg
                =  $obj_cnt ?   " records "
                              . ($opt->{dryrun} ? 'would be ' : '')
                              . 'modified'
                            : "$line_header: None";
            $app->print("$final_msg\n");
            $logger->info("$class results: $obj_cnt $final_msg\n");
        }
    }
}

sub confirm_merge_blog_data {
    my ( $app, $obj_to_merge, $src, $target ) = @_;
    my $opt = $app->options();
    
    my %unhandled_classes = %classes_seen;

    print "----------------------------------------------------\n";
    printf "Please review the following carefully:\n"
          ."  Source blog: %s, (ID:%s)\n"
          ."  Target blog: %s, (ID:%s)\n\n",
           $src->name, $src->id, $target->name, $target->id;

    print "Blog objects of the following classes will migrated from the "
        . "source blog to the target blog, in this order:\n";
    foreach my $objhash ( @$obj_to_merge ) {
        my ($hashclass) = keys %$objhash;
        print "\t$hashclass\n" ;
        delete $unhandled_classes{$hashclass};
    }

    foreach my $uhclass ( sort keys %unhandled_classes ) {
        my $props = $uhclass->properties() || {};
        next unless $props->{class_type};
        print "\t$uhclass\n" ;
        delete $unhandled_classes{$uhclass};
    }

    print "\nObjects of the following classes will NOT BE MIGRATED:\n";
    foreach my $uhclass ( sort keys %unhandled_classes ) {
        next unless $uhclass->has_column('blog_id');
        printf "\t%s %s\n",
            $uhclass, ($uhclass->has_column('blog_id') ? '' 
                                                       : ' -- no blog ID column')
    }

    return $app->confirm_action(
        "Would you like to continue with this operation? (Y/n) "
    );
}

sub _populate_obj_to_merge {
    my $pkg = shift;
    my ($blog_id) = @_;

    my %populated;

    my @object_hashes;
    my $types        = MT->registry('object_types');
    my $instructions = MT->registry('merge_instructions');
    foreach my $obj_type (keys %$types) {
        next if $obj_type =~ /\w+\.\w+/; # skip subclasses
        my $class             = MT->model( $obj_type );
        next unless $class and $class->has_column('blog_id'); # Nothing to merge
        $classes_seen{$class} = 1;                      # Note class for logging
        my $type_inst         = $instructions->{$obj_type} || {};
        my $order             = $type_inst->{order} ? $type_inst->{order} : 500;

        # Skip object types marked as skip or those we've already dealt with
        next if $type_inst->{skip} or exists $populated{"$class"};

        my $terms_args = $class->can('merge_terms_args')
                      || $pkg->can('merge_terms_args');
        push @object_hashes, {
            $class => $terms_args->( $blog_id ),
            order  => $order
        };
        $populated{ $class } = 1;
    }

    @object_hashes = sort { $a->{order} <=> $b->{order} } @object_hashes;
    my @obj_to_merge;
    foreach my $hash ( @object_hashes ) {
        delete $hash->{order};
        push @obj_to_merge, $hash;
    }
    return \@obj_to_merge;
}

sub merge_terms_args {
    my ( $blog_id ) = @_;
    return {
        terms       => ($blog_id ? { blog_id => $blog_id } : ()),
        args        => { no_class => 1 },
    };
}
    
sub handler_category {
    die "Not yet implemented";
    # my 
    # $opt->{catcsv} = $fh;
}


1;


package MT::Object;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    $obj->blog_id( $target->id );
    unless ( $obj->save ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->logerror(
            sprintf "Save error for %s object: ", ref $obj, $obj->errstr
        );
    }
}


package MT::Entry;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    my $oldlink = $obj->permalink;
    $obj->blog_id( $target->id );
    unless ( $obj->save ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->logerror(
            sprintf "Save error for %s object: ", ref $obj, $obj->errstr
        );
    }
    $obj->clear_cache();
    my $newlink = $obj->permalink;
    if ( $oldlink ne $newlink ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->info( "ENTRY REDIRECT URL: $oldlink $newlink" );
    }
}


package MT::Asset;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    my $oldlink = $obj->url;
    $obj->blog_id( $target->id );
    unless ( $obj->save ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->logerror(
            sprintf "Save error for %s object: ", ref $obj, $obj->errstr
        );
    }
    $obj->clear_cache();
    my $newlink = $obj->url;
    if ( $oldlink ne $newlink ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->info( "ASSET REDIRECT URL: $oldlink $newlink" );
    }
}

package MT::Association;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    my $holder = $obj->user() || $obj->group();
    my $role   = $obj->role();
    MT::Association->unlink( $holder, $role, $src );
    MT::Association->link( $holder, $role, $target)->rebuild_permissions();
}

package MT::Permission;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    $obj->rebuild();
}

__END__

# sub init_request {
#     my $app = shift;
#     ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
#     $app->SUPER::init_request(@_) or return;
# 
#     my $blog = $app->load_by_name_or_id( 'blog', $app->param('blog') )
#         or return;
#     $app->param( 'blog_id', $blog->id );
#     # print STDERR 'I just set $app->param( blog_id ) to '
#     #            . $app->param( 'blog_id' ).": ".Dumper($app->blog());
#         
#     # $app->blog( $app->param('blog') );
# }

