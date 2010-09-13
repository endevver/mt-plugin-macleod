package MacLeod::Tool::BlogList;
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
Usage: $0 [options]
Options:
    --cols      Comma-separated list of columns to show in output. 
                Default is "id,name,site_url"
    --verbose   Output more progress information
    --man       Output the man page for the utility
    --help      Output this message
EOD
}

sub help { q{ This is a blog listing script } }

sub option_spec {
    return ( 'cols:s', $_[0]->SUPER::option_spec() );
}

sub init_options {
    my $app = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    # $app->show_usage() unless @ARGV;

    $app->SUPER::init_options(@_) or return;
    my $opt = $app->options || {};
    $opt->{cols} = ref $opt->{cols} eq 'ARRAY' 
                 ? $opt->{cols} 
                 : [ split( /\s*,\s*/, ($opt->{cols} || 'id,name,site_url') )];
    ###l4p $logger->debug('$opt: ', l4mtdump( $opt ));
    1;
}

sub mode_default {
    my $app    = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    my $opt            = $app->options();


    my $blogs = $app->blog_list();
    my @out;
    foreach my $blog (@$blogs) {
        push(@out, sprintf "%-5s %-30s %s", 
                    map { $blog->{$_} } @{ $opt->{cols} });
    }
    return join("\n", @out);

}

sub blog_list {
    my ( $app ) = @_;
    my $opt = $app->options();
    require MT::Blog;
    my $iter = MT::Blog->load_iter();
    my @blogs;
    while (my $blog = $iter->()) {
        my %data;
        %data = map { $_ => $blog->$_ } @{ $opt->{cols} };
        push @blogs, \%data;
    }
    return @blogs ? \@blogs : [];
}

sub relative_url {
    my $host = shift;
    return '' unless defined $host;
    if ($host =~ m!^https?://[^/]+(/.*)$!) {
        return $1;
    } else {
        return '';
    }
}

1;

__END__
