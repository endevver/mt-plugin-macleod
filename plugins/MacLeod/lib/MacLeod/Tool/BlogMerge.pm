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
    --perms     Migrate user/group associations (i.e. permissions)
    --dryrun    Run through without modifying anything
    --force     Don't prompt for confirmation of actions
    --verbose   Output more progress information
    --man       Output the man page for the utility
    --help      Output this message
EOD
}

sub help { q{ This is a blog merging script } }

sub option_spec {
    return ( 'dryrun|d', 'perms|p', 'force|f',
               $_[0]->SUPER::option_spec()    );
}


sub init_options {
    my $app = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    $app->show_usage() unless @ARGV;

    $app->SUPER::init_options(@_) or return;
    my $opt = $app->options || {};

    unless ( $opt->{srcblog} && $opt->{targetblog} ) {
        @ARGV == 2 or return $app->error(
            'You must specify two and only two blogs '
            .'by their ID or the full, exact name' );

        ( $opt->{srcblog}, $opt->{targetblog} )
            = map { $app->load_by_name_or_id( 'blog', $_ ) } @ARGV;

        return unless $opt->{srcblog} && $opt->{targetblog};
    }

    if ( $opt->{perms} ) {
        my $inst = $app->registry('merge_instructions');
        print 'BEFORE $inst->{association}{skip}: '
              .$inst->{association}{skip}."\n";
        delete $inst->{association}{skip};
        delete $inst->{permission}{skip};
        # print 'AFTER $inst->{association}{skip}: '.$inst->{association}{skip}."\n";
        
        unless ( $opt->{dryrun} ) {
            my $cb = sub { 
                ###l4p $logger->debug('In TakeDown callback removing old blog perms');
                $app->model('permission')->remove({
                    blog_id => $opt->{srcblog}->id
                });
            };
            ###l4p $logger->debug('Adding TakeDown callback for removing permissions from old blog');
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

    if ( $continue ) {
        $app->merge_blog_data( $obj_to_merge, $src, $target );
    }
    else {
        $app->print("Merge of blog data aborted\n");
    }

    return "All requested merge operations complete";
}

sub merge_blog_data {
    my ( $app, $obj_to_merge, $src, $target ) = @_;
    my $opt = $app->options();
    
    foreach my $objhash ( @$obj_to_merge ) {
        while ( my ($class, $loadargs) = each %$objhash ) {
            $app->print("Upgrading $class objects: ");
            my $obj_cnt = 0;
            my $iter = $class->load_iter(   $loadargs->{terms},
                                            $loadargs->{args}   );
            while ( my $obj = $iter->() ) {
                $obj_cnt++;
                if ( ($obj_cnt % 100) == 0 ) {
                    $app->print($obj_cnt.' ');
                }
                $obj->merge_operation( $src, $target )
                    unless $opt->{dryrun};
            }

            # Final reporting for object type
            if ( $obj_cnt ) {
                $app->print( "$obj_cnt records "
                           . ($opt->{dryrun} ? 'would be ' : '')
                           . "modified\n");
            }
            else {
                $app->print("None\n");
            }
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

    print "\nObjects of the following classes will NOT BE MIGRATED:\n";
    foreach my $unhandled ( sort keys %unhandled_classes ) {
        next unless $unhandled->has_column('blog_id');
        print "\t$unhandled"
        .($unhandled->has_column('blog_id') ? '' : ' -- no blog ID column')
        ."\n";
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
    foreach my $key (keys %$types) {
        next if $key =~ /\w+\.\w+/; # skip subclasses
        my $class = MT->model($key);
        next unless $class;
        $classes_seen{$class} = 1;
        next unless $class->has_column('blog_id');
        next if exists($instructions->{$key})
             && exists($instructions->{$key}{skip})
             && $instructions->{$key}{skip};
        next if exists $populated{$class};
        my $order = exists($instructions->{$key})
                 && exists($instructions->{$key}{order})
            ? $instructions->{$key}{order}
            : 500;
        $pkg->_create_obj_to_merge(
            $class, $blog_id, \@object_hashes, \%populated, $order);
    }
    @object_hashes = sort { $a->{order} <=> $b->{order} } @object_hashes;
    my @obj_to_merge;
    foreach my $hash ( @object_hashes ) {
        delete $hash->{order};
        push @obj_to_merge, $hash;
    }
    return \@obj_to_merge;
}

sub _create_obj_to_merge {
    my $pkg = shift;
    my ($class, $blog_id, $obj_to_merge, $populated, $order) = @_;

    my $instructions = MT->registry('merge_instructions');
    my $columns = $class->column_names;
    foreach my $column (@$columns) {
        if ( $column =~ /^(\w+)_id$/ ) {
            my $parent = $1;
            my $p_class = MT->model($parent);
            next unless $p_class;
            $classes_seen{$p_class} = 1;
            next unless $p_class->has_column('blog_id');
            next if exists $populated->{$p_class};
            next if exists($instructions->{$parent})
                 && exists($instructions->{$parent}{skip})
                 && $instructions->{$parent}{skip};
            my $p_order = exists($instructions->{$parent})
                       && exists($instructions->{$parent}{order})
                ? $instructions->{$parent}{order}
                : 500;
            $pkg->_create_obj_to_merge(
                $p_class, $blog_id, $obj_to_merge, $populated, $p_order);
        }
    }
    
    if ( $class->can('merge_terms_args') ) {
        push @$obj_to_merge, {
            $class  => $class->merge_terms_args($blog_id),
            'order' => $order
        };
    }
    else {
        push @$obj_to_merge, 
            $pkg->_default_terms_args($class, $blog_id, $order);
    }

    $populated->{$class} = 1;
}

sub _default_terms_args {
    my $pkg = shift;
    my ($class, $blog_id, $order) = @_;

    if ($blog_id) {
        return {
            $class => {
                terms => { 'blog_id' => $blog_id }, 
                args => undef
            },
            'order' => $order,
        };
    }
    else {
        return {
            $class  => { terms => undef, args => undef },
            'order' => $order,
        };
    }
}
    

1;


package MT::Object;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    $obj->blog_id( $target->id );
    $obj->save or warn "Save error: ".$obj->errstr;
}


package MT::Entry;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $oldlink = $obj->permalink;
    $obj->blog_id( $target->id );
    $obj->save or warn "Save error: ".$obj->errstr;
    $obj->clear_cache();
    my $newlink = $obj->permalink;
    ###l4p $logger->info( "ENTRY REDIRECT URL: $oldlink $newlink" )
    ###l4p      if $oldlink ne $newlink;
}


package MT::Asset;

sub merge_operation {
    my ( $obj, $src, $target ) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $oldlink = $obj->url;
    $obj->blog_id( $target->id );
    $obj->save or warn "Save error: ".$obj->errstr;
    $obj->clear_cache();
    my $newlink = $obj->url;
    ###l4p $logger->info( "ASSET REDIRECT URL: $oldlink $newlink" )
    ###l4p      if $oldlink ne $newlink;
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

