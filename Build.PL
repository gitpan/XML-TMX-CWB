use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new
  (
   module_name         => 'XML::TMX::CWB',
   license             => 'perl',
   dist_author         => q{Alberto Simoes <ambs@cpan.org>},
   dist_version_from   => 'lib/XML/TMX/CWB.pm',
   requires => {
                'XML::TMX'            => '0.17',
                'Lingua::PT::PLNbase' => '0.21',
                'CWB::CL'             => '2.002102',
               },
   build_requires => {
                      'Test::More' => 0,
                     },
   script_files => ['bin/cwb2tmx', 'bin/tmx2cwb'],
   add_to_cleanup      => [ 'XML-TMX-CWB-*' ],
   meta_merge => {
     resources => {
       repository => {
         url => 'https://natura.di.uminho.pt/svn/main/xml/XML-TMX-CWB/',
         type => 'svn',
       },
     }
   },
  );

$builder->create_build_script();
