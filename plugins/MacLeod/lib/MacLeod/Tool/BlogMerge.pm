package MacLeod::Tool::BlogMerge;
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
our %classes_seen;

sub usage { 
    return <<EOD;
Usage: $0 [options] SRC_BLOG TARGET_BLOG
Options:
    --perms      Also merge user/group associations (i.e. permissions)
    --cats FILE  Also merge categories/folders, w/ optional CSV control file
    --catscheck FILE  
                 Skip all merge steps, test the category CSV map file then quit
    --dryrun     Run through without modifying anything
    --force      Don't prompt for confirmation of actions
    --verbose    Output more progress information
    --man        Output the man page for the utility
    --help       Output this message
EOD
}

sub help { q{ This is a blog merging script } }

sub option_spec {
    return ( 'dryrun|d', 'perms|p', 'cats|c=s', 'catscheck=s', 'force|f',
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

    if ( $opt->{'catscheck'} ) {
        $opt->{force} = $opt->{verbose} = $opt->{dryrun} = 1;
        $opt->{cats} = $opt->{'catscheck'};
        $inst->{$_}{skip} = 1 foreach keys %$inst;
    }

    if ( $opt->{cats} ) {
        require Text::CSV;
        my $csv = Text::CSV->new({ binary => 1, eol => $/ })
            or die "Cannot use CSV: ".Text::CSV->error_diag ();
        open my $fh, "<", $opt->{cats}
            or die $opt->{cats}.": $!";
        MT->add_callback( 'take_down', 1, $app, sub { close $fh } );
        $opt->{csv} = $csv;
        $opt->{csvfh} = $fh;
        delete $inst->{$_}{skip} foreach qw( category placement );
    }

    if ( $opt->{perms} ) {
        # print 'BEFORE $inst->{association}{skip}: '
        #       .$inst->{association}{skip}."\n";
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
        while ( my ($class, $info) = each %$objhash ) {
            next if $opt->{catscheck} and $class ne 'MT::Category'; # Check mode
            my $obj_cnt = 0;
            my $loader = [ $info->{terms}, $info->{args} ]; # Object loader

            # Get the total object count for progress reporting
            # and create a anonymous reporter function 
            my $total = $class->blog_merge_handler( 'count', $loader );
            my $line_header = ($opt->{dryrun} ? '(Mock)' : '')
                            . "Upgrading $total $class objects";
            my $reporter = sub { $app->print("\r$line_header: ".(shift)) };
            $logger->info( $line_header );

            my $mode = $opt->{dryrun} ? 'merge-report' : 'merge';
            $obj_cnt += $class->blog_merge_handler(
                            $mode, $loader, $src, $target, $reporter );

            # Final reporting for object type
            $reporter->( $obj_cnt );
            my $final_msg = sprintf(
                "%s records%s modified",
                ($obj_cnt||'No'), 
                ($opt->{dryrun} ? ' would be' : ''));
            $app->print("\r$line_header: $final_msg\n");
            $logger->info("$class results: $final_msg");
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
    my $app = MT->instance;
    my $opt = $app->options();
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
        next if $type_inst->{skip} or exists $populated{$class};

        my $hdlr = $type_inst->{handler} ;
        my $terms_args = $class->can('merge_terms_args')
                      || $pkg->can('merge_terms_args');
        push @object_hashes, {
            $class => {
                $terms_args->( $blog_id ),
                ($hdlr ? (handler => $hdlr) : ()),
            },
            order  => $order
        };
        $populated{ $class } = 1;
    }

    @object_hashes = map { delete $_->{order}; $_ } 
                        sort { $a->{order} <=> $b->{order} } @object_hashes;
    return \@object_hashes;
}

sub merge_terms_args {
    my ( $blog_id ) = @_;
    return (
        terms       => ($blog_id ? { blog_id => $blog_id } : ()),
        args        => { no_class => 1 },
    );
}
    
1;


package MT::Object;

sub blog_merge_handler {
    my ( $pkg, $mode, $loader, $src, $target, $reporter ) = @_;
    return $pkg->count( @$loader ) if $mode eq 'count';
    my $cnt = 0;
    my $iter = $pkg->load_iter( @$loader );
    while ( my $obj = $iter->() ) {
        $reporter->(++$cnt);
        $obj->switch_blogs( $src, $target ) unless $mode eq 'merge-report'
    }
    return $cnt;
}

sub switch_blogs {
    my ( $obj, $src, $target ) = @_;
    $obj->blog_id( $target->id );
    unless ( $obj->save ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->error(
            sprintf "Save error for %s object: ", ref $obj, $obj->errstr
        );
    }
}


package MT::Entry;

sub switch_blogs {
    my ( $obj, $src, $target ) = @_;
    my $oldlink = $obj->permalink;
    $obj->blog_id( $target->id );
    unless ( $obj->save ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->error(
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

sub switch_blogs {
    my ( $obj, $src, $target ) = @_;
    my $oldlink = $obj->url;
    $obj->blog_id( $target->id );
    unless ( $obj->save ) {
        $logger ||= MT::Log::Log4perl->new();
        $logger->error(
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

sub switch_blogs {
    my ( $obj, $src, $target ) = @_;
    my $holder = $obj->user() || $obj->group();
    my $role   = $obj->role();
    MT::Association->unlink( $holder, $role, $src );
    MT::Association->link( $holder, $role, $target)->rebuild_permissions();
}

package MT::Permission;

sub switch_blogs {
    my ( $obj, $src, $target ) = @_;
    $obj->rebuild();
}

package MT::Category;

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );

sub blog_merge_handler {
    my ( $pkg, $mode, $loader, $src, $target, $reporter ) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $app            = MT->instance;
    my $opt            = $app->options();
    my $csv            = $opt->{csv};
    my $fh             = $opt->{csvfh};
    my $cnt            = 0;
    $logger ||= MT::Log::Log4perl->new();
    my ( @records, @missing_categories, @placement_updates );

    seek( $fh, 0, 0 );
    while ( my $row = $csv->getline( $fh ) ) {
        # print $csv->string();
        if ( $mode eq 'count' ) {
            $cnt += 1 + @$row - 2;
            next;
        }
        my ($canon, @cats);
        my $rec = {
            label    => shift @$row,
            id       => shift @$row,
            mergeids => $row,
        };
        # If we're provided with a category ID in field two,
        # load it as the canonical category.
        if ( $rec->{id} ) {
            ( $canon ) = $pkg->load( $rec->{id}, { no_class => 1 } );
            if ( ! $canon ) {
                push( @missing_categories, { %$rec, row => $csv->string() });
                my $msg = 'No category matched ID '. $rec->{id} .'. '
                        . 'Creating a new one with the label "'.$rec->{label}
                        .'". Line: '.$csv->string()."\n";
                $logger->warn($msg);
            }
        }
        # If no category ID is provided in field two, search for it by label
        # first in the target blog and then in the source blog.
        else {
            my $terms = [
                   { blog_id => $target->id, label => $rec->{label} }
                => '-or'
                => { blog_id => $src->id,    label => $rec->{label} } 
            ];
            @cats = $pkg->load( $terms, { no_class => 1 });
            foreach my $bid ( $target->id, $src->id ) {
                ( $canon ) = grep { $_->blog_id == $bid } @cats;
                last if $canon;
            }
        }

        next if $canon and $canon->id == $rec->{id}
                       and $canon->label eq $rec->{label}
                       and $canon->blog_id == $target->id;
                       
        # If we still do not have a canonical category,
        # create it using the ID in field one if provided
        $canon ||= $pkg->new();
        $canon->id( $rec->{id} ) if $rec->{id} and ! $canon->id;
        # ###l4p $logger->debug('$canon: ', l4mtdump($canon));

        # Update our canonical category with the label
        # from field one and the target blog ID and save.
        $canon->label( $rec->{label} );
        $canon->blog_id( $target->id );
        unless ( $mode eq 'merge-report' ) {
            $canon->save or die "Category save error: ".$canon->errstr;
            $cnt++;
        }
        push( @placement_updates, { 
            canon_id  => $canon->id, 
            blog_id   => $target->id, 
            merge_ids => $rec->{mergeids},
        });
    }
    $csv->eof or $csv->error_diag();
    $app->request( 'merge_placement_updates', \@placement_updates )
        if @placement_updates;
    # TODO Delete @mergeid cats (maybe)
    return $cnt;
}

package MT::Placement;

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );

sub blog_merge_handler {
    my ( $pkg, $mode, $loader, $src, $target, $reporter ) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $app     = MT->instance;
    my $updates = $app->request('merge_placement_updates') || [];
    $logger->debug('$updates: ', l4mtdump($updates));    
    my $cnt     = 0;
    foreach my $update ( @$updates ) {
        if ( $mode eq 'count' ) {
            $cnt += 1 + @{ $update->{merge_ids} };
            next;
        }
        my $plc_terms = [];
        push( @$plc_terms, { category_id => $_ } )
            foreach ( $update->{canon_id}, @{ $update->{merge_ids} } );
        my $plc_iter = $pkg->load_iter( $plc_terms );
        while ( my $plc = $plc_iter->() ) {
            next if $plc->blog_id     == $update->{blog_id}
                and $plc->category_id == $update->{canon_id};
            $plc->blog_id(      $update->{blog_id}  );
            $plc->category_id(  $update->{canon_id} );
            if ( $mode eq 'merge-report' ) {
                $cnt++;
            }
            else {
                if ($plc->save) {
                    $cnt++;
                }
                else {
                    warn "Error saving category placement: ".$plc->errstr;
                }
            }
        }
    }
    return $cnt;
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

