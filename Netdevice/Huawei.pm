package Netdevice::Huawei;
use Netdevice::Base;
use Data::Dumper;
use vars qw(@ISA);
@ISA = qw(Netdevice::Base);

# override method
sub getDeviceMemUtil {
    my ($self,$type,$oid,$calculation) = @_;
    my $result_a = Netdevice::Base::_getValue($self,
                           $type,
                           $oid->[0],
                           );
    my $result_b = Netdevice::Base::_getValue($self,
                           $type,
                           $oid->[1],
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    my $val = 0;
    my @res_a = map{$result_a->{$_}}sort keys %{$result_a};
    my @res_b = map{$result_b->{$_}}sort keys %{$result_b};
    @res_a = map{sprintf("%.2f",100 * $res_a[$_] / $res_b[$_])}0..$#res_a;
    $val += $_ foreach(@res_a);
    $val = sprintf("%.2f",100 - $val / (scalar @res_a));
    $ret->{"ND_${res_name}"}->{'DeviceMemUtil'} = $val;
    $ret;
}
1;
