package XML::TMX::CWB;

use warnings;
use strict;
use Lingua::PT::PLNbase;
use XML::TMX::Reader;
use XML::TMX::Writer;
use CWB::CL::Strict;
use File::Spec::Functions;
use Encode;

use POSIX qw(locale_h);
setlocale(&POSIX::LC_ALL, "pt_PT");
use locale;

=head1 NAME

XML::TMX::CWB - TMX interface with Open Corpus Workbench

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';


=head1 SYNOPSIS

    XML::TMX::CWB->toCWB( tmx => $tmxfile,
                          from => 'PT', to => 'EN',
                          corpora => "/corpora",
                          corpus_name => "foo",
                          tokenize_source => 1,
                          tokenize_target => 1,
                          verbose => 1,
                          registry => '/path/to/cwb/registry' );

    XML::TMX::CWB->toTMX( source => 'sourcecorpus',
                          target => 'targetcorpus',
                          source_lang => 'PT',
                          target_lang => 'ES',
                          verbose => 1,
                          output => "foobar.tmx");


=head1 METHODS

=head2 toTMX

Fetches an aligned pair of corpora on CWB and exports it as a TMX
file.

=cut

sub toTMX {
    shift if $_[0] eq 'XML::TMX::CWB';
    my %ops = @_;

    die "Source and target corpora names are required.\n" unless $ops{source} and $ops{target};

    my $Cs = new CWB::CL::Corpus uc($ops{source});
    die "Can't find corpus [$ops{source}]\n" unless $Cs;
    my $Ct = new CWB::CL::Corpus uc($ops{target});
    die "Can't find corpus [$ops{target}]\n" unless $Ct;

    my $align = $Cs->attribute(lc($ops{target}), "a");
    my $count = $align->max_alg;

    my $Ws = $Cs->attribute("word", "p");
    my $Wt = $Ct->attribute("word", "p");

    my $tmx = new XML::TMX::Writer();
    $tmx->start_tmx( $ops{output} ? (OUTPUT => $ops{output}) : (),
                     TOOL => 'XML::TMX::CWB',
                     TOOLVERSION => $VERSION);
    for my $i (0 .. $count-1) {
        my ($s1, $s2, $t1, $t2) = $align->alg2cpos($i);
        my $source = join(" ",$Ws->cpos2str($s1 .. $s2));
        my $target = join(" ",$Wt->cpos2str($t1 .. $t2));
	Encode::_utf8_on($source);
	Encode::_utf8_on($target);
        $tmx->add_tu($ops{source_lang} => $source,
                     $ops{target_lang} => $target);
    }
    $tmx->end_tmx();
}

=head2 toCWB

Imports a TMX file (just two languages) to a parallel corpus on CWB.

=cut


sub _RUN {
    my $command = shift;
    print STDERR "Running [$command]\n";
    `$command`;
}

sub toCWB {
    shift if $_[0] eq 'XML::TMX::CWB';
    my %ops = @_;

    my $tmx = $ops{tmx} or die "tmx file not specified.\n";

    my $corpora = $ops{corpora} || "/corpora";
    die "Need a corpora folder" unless -d $corpora;

    die "Can't open [$tmx] file for reading\n" unless -f $tmx;

    # Create reader object
    my $reader = XML::TMX::Reader->new($tmx);

    # Detect what languages to use
    my ($source, $target) = _detect_languages($reader,
                                              ($ops{from} || undef),
                                              ($ops{to}   || undef));

    # Detect corpus registry
    my $registry = $ops{registry} || $ENV{CORPUS_REGISTRY};
    chomp( $registry = `cwb-config -r` ) unless $registry;
    die "Could not detect a suitable CWB registry folder.\n" unless $registry && -d $registry;

    my $cname = $ops{corpus_name} || $tmx;

    $cname =~ s/[.-]/_/g;

    _tmx2cqpfiles($reader, $cname, $source, $target,
                  $ops{tokenize_source} || 0,
                  $ops{tokenize_target} || 0,
                  $ops{verbose}
                 );

    _encode($cname, $corpora, $registry, $source, $target);

    unlink "source.cqp";
    unlink "target.cqp";
    unlink "align.txt";
}

sub _encode {
    my ($cname, $corpora, $registry, $l1, $l2) = @_;
    my ($name, $folder, $reg);

    $name = lc("${cname}_$l1");
    $folder = catfile($corpora,  $name);
    $reg    = catfile($registry, $name);
    mkdir $folder;
    _RUN("cwb-encode -c utf8 -d $folder -f source.cqp -R $reg -S tu+id");
    _RUN("cwb-make -r $reg -v " . uc($name));

    $name = lc("${cname}_$l2");
    $folder = catfile($corpora,  $name);
    $reg    = catfile($registry, $name);
    mkdir $folder;
    _RUN("cwb-encode -c utf8 -d $folder -f target.cqp -R $reg -S tu+id");
    _RUN("cwb-make -r $reg -v " . uc($name));

    _RUN("cwb-align-import -r $reg -v align.txt");
    _RUN("cwb-align-import -r $reg -v -inverse align.txt");
}

sub _tmx2cqpfiles {
    my ($reader, $cname, $l1, $l2, $t1, $t2, $v) = @_;
    open F1, ">:utf8", "source.cqp" or die "Can't create cqp outfile\n";
    open F2, ">:utf8", "target.cqp" or die "Can't create cqp outfile\n";
    open AL, ">:utf8", "align.txt"  or die "Can't create alignment file\n";
    my $i = 1;

    printf AL "%s\t%s\ttu\tid_{id}\n", uc("${cname}_$l1"), uc("${cname}_$l2");

    print STDERR "Processing..." if $v;

    my $proc = sub {
        my ($langs) = @_;
        return unless exists $langs->{$l1} && exists $langs->{$l2};

        $langs->{$l1} =~ s/</&lt/g;
        $langs->{$l2} =~ s/</&lt/g;
        $langs->{$l1} =~ s/>/&gt/g;
        $langs->{$l2} =~ s/>/&gt/g;

        my @S = $t1 ? tokenize($langs->{$l1}) : split /\s+/, $langs->{$l1};
        my @T = $t2 ? tokenize($langs->{$l2}) : split /\s+/, $langs->{$l2};

        print STDERR "\rProcessing... $i translation units" if $v && $i%1000==0;

        print AL "id_$i\tid_$i\n";
        print F1 "<tu id='$i'>\n", join("\n", @S), "\n</tu>\n";
        print F2 "<tu id='$i'>\n", join("\n", @T), "\n</tu>\n";
        ++$i;
    };

    $reader->for_tu2( $proc );
    print STDERR "\rProcessing... $i translation units\n" if $v;
}

sub _detect_languages {
    my ($reader, $from, $to) = @_;
    my @languages = $reader->languages();

    die "Language $from not available\n" if $from and !grep{$_ eq $from}@languages;
    die "Language $to not available\n"   if $to   and !grep{$_ eq $to } @languages;

    return ($from, $to) if $from and $to;

    if (scalar(@languages) == 2) {
        $to = grep { $_ ne $from } @languages if $from and not $to;
        $from = grep { $_ ne $to } @languages if $to and not $from;
        ($from, $to) = @languages if not ($to or $from);
        return ($from, $to) if $from and $to;
    }
    die "Can't guess what languages to use!\n";
}





=head1 AUTHOR

Alberto Simoes, C<< <ambs at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-xml-tmx-cwb at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=XML-TMX-CWB>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc XML::TMX::CWB


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=XML-TMX-CWB>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/XML-TMX-CWB>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/XML-TMX-CWB>

=item * Search CPAN

L<http://search.cpan.org/dist/XML-TMX-CWB/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Alberto Simoes.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of XML::TMX::CWB
