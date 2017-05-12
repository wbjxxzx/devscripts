package Netdevice;
use strict;
use vars qw(@ISA $VERSION);

$VERSION = '1.0';
$VERSION =~ tr/_//;

my %vendor = (
    cisco   => 'Cisco',
    huawei  => 'Huawei',
    h3c     => 'H3C',
    );
print $ENV{VENDOR},"\n";
my $vendor = $vendor{$ENV{VENDOR}} || 'Base';

require "Netdevice/$vendor.pm";
@ISA = ("Netdevice::$vendor");

1;
