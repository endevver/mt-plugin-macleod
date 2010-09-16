package MacLeod::Tool::BlogDelete;
use strict; use warnings; use Carp; use Data::Dumper;

use Pod::Usage;
use File::Spec;
use Data::Dumper;
use MT::Util qw( caturl );
use Cwd qw( realpath );

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
our $logger = MT::Log::Log4perl->new();

use Devel::TraceMethods qw( __PACKAGE__ MT::Object Data::ObjectDriver::Driver::DBI );

my @traced = qw( __PACKAGE__::remove_fastlog __PACKAGE__::remove_children_fastlog MT::Object::remove MT::Object::remove_meta MT::Object::remove_scores MT::Object::remove_children Data::ObjectDriver::Driver::DBI::remove Data::ObjectDriver::Driver::DBI::direct_remove Data::ObjectDriver::Driver::BaseCache::remove_from_cache Data::ObjectDriver::Driver::BaseCache::remove Data::ObjectDriver::Driver::BaseCache::uncache_object Data::ObjectDriver::Driver::Cache::Cache::remove_from_cache Data::ObjectDriver::Driver::Cache::RAM::remove_from_cache MT::Asset::remove MT::Asset::remove_cached_files MT::Association::remove MT::Association::sub rebuild_permissions MT::Trackback::remove MT::TemplateMap::remove MT::Tag::remove MT::Tag::remove_tags MT::Tag::pre_remove_tags MT::Role::remove MT::PluginData::remove MT::Entry::remove MT::Category::remove MT::Blog::remove MT::Author::remove MT::Author::remove_role MT::Author::remove_group MT::Author::remove_sessions );

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
      code => 'remove_children_fastlog',
      into => 'MT::Object',
      as   => 'remove_children',
    });

    Sub::Install::reinstall_sub({
      code => 'remove_fastlog',
      into => 'MT::Object',
      as   => 'remove',
    });

    if ( $opt->{verbose} ) {
        $app->config('DebugMode', 7);
        require MT;
        $MT::DebugMode = 7;
        $app->init_debug_mode();
    }

    Devel::TraceMethods->callback(sub {
        my ( $meth, @args ) = @_;
        return unless grep { /$meth/ } @traced;
        $logger->info('METH: '.$meth.', ARGS: ', l4mtdump(\@args));
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
                    map { $blog->$_ || 'NONE' } @{ $opt->{cols} };
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
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();s
    my $opt   = $app->options();
    my $count = 0;
    my $plugin = $app->component('MacLeod');

    foreach my $blog ( @$blogs ) {
        my $status = 'DELETING';
        my $blog_line = sprintf "%-5s %-30s %s",
                            map { $blog->$_ || 'NONE' } @{ $opt->{cols} };
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

sub remove_fastlog {
    my $obj = shift;
    my (@args) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    ###l4p $logger->debug("Removing $obj!");
    if (!ref $obj) {
        print Dumper($args[1]) if $args[1];
        $args[1] ||= {};
        $args[1]->{nofetch} = 1;
        for my $which (qw( meta summary )) {
            my $meth = "remove_$which";
            my $has = "has_$which";
            $obj->$meth( @args ) if $obj->$has;
        }
        $obj->remove_scores( @args ) if $obj->isa('MT::Scorable');
        MT->run_callbacks($obj . '::pre_remove_multi', @args);
        return $obj->driver->direct_remove($obj, @args);
    } else {
        return $obj->driver->remove($obj, @args);
    }
}

sub remove_children_fastlog {
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

mysql> delete from mt_log where log_blog_id NOT IN (select blog_id from mt_blog where blog_name NOT LIKE "%'s blog")

package MT::Object;

sub remove {
    my $obj = shift;
    my(@args) = @_;
    if (!ref $obj) {
        $obj->remove_meta( @args ) if $obj->has_meta;
        $obj->remove_scores( @args ) if $obj->isa('MT::Scorable');
        return $obj->driver->direct_remove($obj, @args);
    } else {
        return $obj->driver->remove($obj, @args);
    }
}

sub remove_meta {
    my $obj = shift;
    my $mpkg = $obj->meta_pkg or return;
    if ( ref $obj ) {
        my $id_field = $obj->datasource . '_id';
        return $mpkg->remove({ $id_field => $obj->id });
    } else {
        # static invocation
        my ($terms, $args) = @_;
        $args = { %$args } if $args; # copy so we can alter
        my $meta_id = $obj->datasource . '_id';
        my $offset = 0;
        $args ||= {};
        $args->{fetchonly} = [ 'id' ];
        $args->{join} = [ $mpkg, $meta_id ];
        $args->{no_triggers} = 1;
        $args->{limit} = 50;
        while ( $offset >= 0 ) {
            $args->{offset} = $offset;
            if (my @list = $obj->load( $terms, $args )) {
                my @ids = map { $_->id } @list;
                $mpkg->driver->direct_remove( $mpkg, { $meta_id => \@ids });
                if ( scalar @list == 50 ) {
                    $offset += 50;
                } else {
                    $offset = -1; # break loop
                }
            } else {
                $offset = -1;
            }
        }
        return 1;
    }
}

sub remove_scores {
    my $class = shift;
    require MT::ObjectScore;
    my ($terms, $args) = @_;
    $args = { %$args } if $args; # copy so we can alter
    my $offset = 0;
    $args ||= {};
    $args->{fetchonly} = [ 'id' ];
    $args->{join} = [ 'MT::ObjectScore', 'object_id', {
        object_ds => $class->datasource } ];
    $args->{no_triggers} = 1;
    $args->{limit} = 50;
    while ( $offset >= 0 ) {
        $args->{offset} = $offset;
        if (my @list = $class->load( $terms, $args )) {
            my @ids = map { $_->id } @list;
            MT::ObjectScore->driver->direct_remove( 'MT::ObjectScore', {
                object_ds => $class->datasource, 'object_id' => \@ids });
            if ( scalar @list == 50 ) {
                $offset += 50;
            } else {
                $offset = -1; # break loop
            }
        } else {
            $offset = -1;
        }
    }
    return 1;
}

sub remove_children {
    my $obj = shift;
    return 1 unless ref $obj;

    my ($param) = @_;
    my $child_classes = $obj->properties->{child_classes} || {};
    my @classes = keys %$child_classes;
    return 1 unless @classes;

    $param ||= {};
    my $key = $param->{key} || $obj->datasource . '_id';
    my $obj_id = $obj->id;
    for my $class (@classes) {
        eval "# line " . __LINE__ . " " . __FILE__ . "\nno warnings 'all';require $class;";
        $class->remove({ $key => $obj_id });
    }
    1;
}



package Data::ObjectDriver::Driver::DBI;

sub remove {
    my $driver = shift;
    my $orig_obj = shift;

    ## If remove() is called on class method and we have 'nofetch'
    ## option, we remove the record using $term and won't create
    ## $object. This is for efficiency and PK-less tables
    ## Note: In this case, triggers won't be fired
    ## Otherwise, Class->remove is a shortcut for search+remove
    unless (ref($orig_obj)) {
        if ($_[1] && $_[1]->{nofetch}) {
            return $driver->direct_remove($orig_obj, @_);
        } else {
            my $result = 0;
            my @obj = $driver->search($orig_obj, @_);
            for my $obj (@obj) {
                my $res = $obj->remove(@_) || 0;
                $result += $res;
            }
            return $result || 0E0;
        }
    }

    return unless $orig_obj->has_primary_key;

    ## Use a duplicate so the pre_save trigger can modify it.
    my $obj = $orig_obj->clone_all;
    $obj->call_trigger('pre_remove', $orig_obj);

    my $tbl = $driver->table_for($obj);
    my $sql = "DELETE FROM $tbl\n";
    my $stmt = $driver->prepare_statement(ref($obj), $obj->primary_key_to_terms);
    $sql .= $stmt->as_sql_where;
    my $dbh = $driver->rw_handle($obj->properties->{db});
    $driver->start_query($sql, $stmt->{bind});
    my $sth = $dbh->prepare_cached($sql);
    my $result = $sth->execute(@{ $stmt->{bind} });
    $sth->finish;
    $driver->end_query($sth);

    $obj->call_trigger('post_remove', $orig_obj);

    $orig_obj->{__is_stored} = 1;
    return $result;
}

sub direct_remove {
    my $driver = shift;
    my($class, $orig_terms, $orig_args) = @_;

    ## Use (shallow) duplicates so the pre_search trigger can modify them.
    my $terms = defined $orig_terms ? { %$orig_terms } : {};
    my $args  = defined $orig_args  ? { %$orig_args  } : {};
    $class->call_trigger('pre_search', $terms, $args);

    my $stmt = $driver->prepare_statement($class, $terms, $args);
    my $tbl  = $driver->table_for($class);
    my $sql  = "DELETE from $tbl\n";
       $sql .= $stmt->as_sql_where;

    # not all DBD drivers can do this.  check.  better to die than do
    # unbounded DELETE when they requested a limit.
    if ($stmt->limit) {
        Carp::croak("Driver doesn't support DELETE with LIMIT")
            unless $driver->dbd->can_delete_with_limit;
        $sql .= $stmt->as_limit;
    }

    my $dbh = $driver->rw_handle($class->properties->{db});
    $driver->start_query($sql, $stmt->{bind});
    my $sth = $dbh->prepare_cached($sql);
    my $result = $sth->execute(@{ $stmt->{bind} });
    $sth->finish;
    $driver->end_query($sth);
    return $result;
}


package Data::ObjectDriver::Driver::BaseCache;

sub remove_from_cache       { Carp::croak("NOT IMPLEMENTED") }

sub remove {
    my $driver = shift;
    my($obj) = @_;
    return $driver->fallback->remove(@_)
        if $driver->Disabled;

    if ($_[2] && $_[2]->{nofetch}) {
        ## since direct_remove isn't an object method, it can't benefit
        ## from inheritance, we're forced to keep things a bit obfuscated here
        ## (I'd rather have a : sub direct_remove { die "unavailable" } in the driver
        Carp::croak("nofetch option isn't compatible with a cache driver");
    }
    if (ref $obj) {
        $driver->uncache_object($obj);
    }
    $driver->fallback->remove(@_);
}

sub uncache_object {
    my $driver = shift;
    my($obj) = @_;
    my $key = $driver->cache_key(ref($obj), $obj->primary_key);
    return $driver->modify_cache(sub {
        delete $obj->{__cached};
        $driver->remove_from_cache($key);
        $driver->fallback->uncache_object($obj);
    });
}



package Data::ObjectDriver::Driver::Cache::Cache;

sub remove_from_cache { shift->cache->remove(@_) }

package Data::ObjectDriver::Driver::Cache::RAM;

sub remove_from_cache {
    my $driver = shift;

    $driver->start_query('RAMCACHE_DELETE ?', \@_);
    my $ret = delete $Cache{$_[0]};
    $driver->end_query(undef);

    return if !defined $ret;
    return $ret;
}


package MT::Asset;

# Removes the asset, associated tags and related file.
# TBD: Should we track and remove any generated thumbnail files here too?
sub remove {
    my $asset = shift;
    if (ref $asset) {
        my $blog = MT::Blog->load($asset->blog_id);
        require MT::FileMgr;
        my $fmgr = $blog ? $blog->file_mgr : MT::FileMgr->new('Local');
        my $file = $asset->file_path;
        $fmgr->delete($file);
        $asset->remove_cached_files;

        # remove children.
        my $class = ref $asset;
        my $iter = __PACKAGE__->load_iter({ parent => $asset->id, class => '*' });
        while(my $a = $iter->()) {
            $a->remove;
        }

        # Remove MT::ObjectAsset records
        $class = MT->model('objectasset');
        $iter = $class->load_iter({ asset_id => $asset->id });
        while (my $o = $iter->()) {
            $o->remove;
        }
    }

    $asset->SUPER::remove(@_);
}

sub remove_cached_files {
    my $asset = shift;
 
    # remove any asset cache files that exist for this asset
    my $blog = $asset->blog;
    if ($asset->id && $blog) {
        my $cache_dir = $asset->_make_cache_path;
        if ($cache_dir) {
            require MT::FileMgr;
            my $fmgr = $blog->file_mgr || MT::FileMgr->new('Local');
            if ($fmgr) {
                my $basename = $asset->file_name;
                my $ext = '.'.$asset->file_ext;
                $basename =~ s/$ext$//;
                my $cache_glob = File::Spec->catfile($cache_dir,
                    $basename . '-thumb-*' . $ext);
                my @files = glob($cache_glob);
                foreach my $file (@files) {
                    $fmgr->delete($file);
                }
            }
        }
    }
    1;
}

package MT::Association;

sub remove {
    my $assoc = shift;
    my $res = $assoc->SUPER::remove(@_) or return;
    if (ref $assoc) {
        $assoc->rebuild_permissions;
    }
    $res;
}

sub rebuild_permissions {
    my $assoc = shift;
    require MT::Permission;
    MT::Permission->rebuild($assoc);
}

package MT::Trackback;

sub remove {
    my $tb = shift;
    $tb->remove_children({ key => 'tb_id' }) or return;
    $tb->SUPER::remove(@_);
}

package MT::TemplateMap;

sub remove {
    my $map = shift;
    $map->remove_children({ key => 'templatemap_id' });
    my $result = $map->SUPER::remove(@_);

    if (ref $map) {
        my $remaining = MT::TemplateMap->load(
          {
            blog_id => $map->blog_id,
            archive_type => $map->archive_type,
            id => [ $map->id ],
          },
          {
            limit => 1,
            not => { id => 1 }
          }
        );
        if ($remaining) {
            $remaining->is_preferred(1);
            $remaining->save;
        }
        else {
            my $blog = MT->model('blog')->load($map->blog_id)
                or return;
            my $at   = $blog->archive_type;
            if ( $at && $at ne 'None' ) {
                my @newat = map { $_ } grep { $map->archive_type ne $_ } split /,/, $at;
                $blog->archive_type(join ',', @newat);
                $blog->save;
            }
        }
    }
    else {
        my $blog_id;
        if ( $_[0] && $_[0]->{template_id} ) {
            my $tmpl = MT::Template->load( $_[0]->{template_id} );
            if ( $tmpl ) {
                return $result unless $tmpl->blog_id; # global template does not have maps
                $blog_id = $tmpl->blog_id;
            }
        }

        my $maps_iter = MT::TemplateMap->count_group_by(
            { ( defined $blog_id ? ( blog_id => $blog_id ) : () ) },
            { group => [ 'blog_id', 'archive_type' ] }
        );
        my %ats;
        while ( my ( $count, $blog_id, $at ) = $maps_iter->() ) {
            my $ats = $ats{$blog_id};
            push @$ats, $at if $count > 0;
            $ats{$blog_id} = $ats;
        }
        my $iter;
        if ( $blog_id ) {
            my $blog = MT::Blog->load( $blog_id );
            $iter = sub { my $ret = $blog; $blog = undef; $ret; }
        } else {
            $iter = MT::Blog->load_iter();
        }
        while ( my $blog = $iter->() ) {
            $blog->archive_type( $ats{ $blog->id } ? join ',', @{ $ats{ $blog->id } } : '' );
            $blog->save;
            for my $at ( @{ $ats{ $blog->id } } ) {
                unless ( __PACKAGE__->exist({
                    blog_id => $blog->id, archive_type => $at, is_preferred => 1 
                }) ) {
                    my $remaining = __PACKAGE__->load(
                      {
                        blog_id => $blog->id,
                        archive_type => $at,
                      },
                      {
                        limit => 1,
                      }
                    );
                    if ($remaining) {
                        $remaining->is_preferred(1);
                        $remaining->save;
                    }
                }
            }
        }
    }
    $result;
}

package MT::Tag;

sub remove {
    my $tag = shift;
    my $n8d_tag;
    if (ref $tag) {
        if (!$tag->n8d_id) {
            # normalized tag! we can't delete if others reference us
            my $child_tags = MT::Tag->exist({n8d_id => $tag->id});
            return $tag->error(MT->translate("This tag is referenced by others."))
                if $child_tags;
        } else {
            $n8d_tag = MT::Tag->load($tag->n8d_id);
        }
    }
    $tag->remove_children({key => 'tag_id'});
    $tag->SUPER::remove(@_)
        or return $tag->error($tag->errstr);
    # check for an orphaned normalized tag and delete if necessary
    if ($n8d_tag) {
        # Normalized tag, no longer referenced by other tags...
        if (!MT::Tag->exist({n8d_id => $n8d_tag->id})) {
            # Noramlized tag that no longer has any object tag associations
            require MT::ObjectTag;
            if (!MT::ObjectTag->exist({tag_id => $n8d_tag->id})) {
                $n8d_tag->remove
                    or return $tag->error($n8d_tag->errstr);
            }
        }
    }
    1;
}

sub remove_tags {
    my $obj = shift;
    my (@tags) = @_;
    if (@tags) {
        my @etags = $obj->tags;
        my %uniq;
        @uniq{@etags} = ();
        delete $uniq{$_} for @tags;
        if (keys %uniq) {
            $obj->set_tags(keys %uniq);
            return;
        }
    }
    require MT::ObjectTag;
    my @et = MT::ObjectTag->load({ object_id => $obj->id,
                                   object_datasource => $obj->datasource });
    $_->remove for @et;
    $obj->{__tags} = [];
    delete $obj->{__save_tags};
    MT::Tag->clear_cache(datasource => $obj->datasource,
        ($obj->blog_id ? (blog_id => $obj->blog_id) : ())) if @et;

    require MT::Memcached;
    MT::Memcached->instance->delete( $obj->tag_cache_key );
}

sub pre_remove_tags {
    my $class = shift;
    my ($obj) = @_;
    $obj->remove_tags if ref $obj;
}

package MT::Role;

sub remove {
    my $role = shift;
    if (ref $role) {
        $role->remove_children({ key => 'role_id' }) or return;
    }
    $role->SUPER::remove(@_);
}

package MT::PluginData;

sub remove {
    my $pd = shift;
    return $pd->SUPER::remove(@_) if ref($pd);

    # class method call - might have blog_id parameter
    my ($terms, $args) = @_;
    $pd->SUPER::remove(@_) unless $terms && exists($terms->{blog_id});

    my $blog_ids = delete $terms->{blog_id};
    if ( 'ARRAY' ne ref($blog_ids) ) {
        $blog_ids = [ $blog_ids ];
    }

    my @keys = map { "configuration:blog:$_" } @$blog_ids;
    $terms->{key} = \@keys;
    $pd->SUPER::remove($terms, $args);
}

package MT::Entry;

sub remove {
    my $entry = shift;
    if (ref $entry) {
        $entry->remove_children({ key => 'entry_id' }) or return;

        # Remove MT::ObjectAsset records
        my $class = MT->model('objectasset');
        $class->remove({ object_id => $entry->id, object_ds => $entry->class_type });
    }

    $entry->SUPER::remove(@_);
}

package MT::Category;

sub remove {
    my $cat = shift;
    $cat->remove_children({ key => 'category_id' });
    if (ref $cat) {
        my $pkg = ref($cat);
        # orphan my children up to the root level
        my @children = $cat->children_categories;
        if (scalar @children) {
            foreach my $child (@children) {
                $child->parent(($cat->parent) ? $cat->parent : '0');
                $child->save or return $cat->error($child->save);
            }
        } else {
            $pkg->clear_cache('blog_id' => $cat->blog_id);
        }
    }
    $cat->SUPER::remove(@_);
}

package MT::Blog;

sub remove {
    my $blog = shift;
    $blog->remove_children({ key => 'blog_id'});
    my $res = $blog->SUPER::remove(@_);
    if ((ref $blog) && $res) {
        require MT::Permission;
        MT::Permission->remove({ blog_id => $blog->id });
    }
    $res;
}

package MT::Author;

sub remove {
    my $auth = shift;
    $auth->remove_sessions if ref $auth;
    $auth->remove_children({ key => 'author_id' }) or return;
    $auth->SUPER::remove(@_);
}

sub remove_role {
    my $author = shift;
    require MT::Association;
    MT::Association->unlink($author, @_);
}

sub remove_group {
    my $author = shift;
    require MT::Association;
    MT::Association->unlink($author, @_);
}

sub remove_sessions {
    my $auth = shift;
    require MT::Session;
    my $sess_iter = MT::Session->load_iter({ kind => 'US' });
    my @sess;
    while (my $sess = $sess_iter->()) {
        my $id = $sess->get('author_id');
        next unless $id == $auth->id;
        push @sess, $sess;
    }
    $_->remove foreach @sess;
}




