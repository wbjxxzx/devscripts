package Netdevice::Base;
use strict;
use Net::SNMP;
use Math::BigInt;
use List::Util qw( sum );

sub get_funcs {
    return {
    'IfId'              => 'getIfId',
    'IfState'           => 'getIfState',
    'IfSpeed'           => 'getIfSpeed',
    'ifInOctets'        => 'getIfInOctets',
    'ifOutOctets'       => 'getIfOutOctets',
    'DeviceCacheUtil'   => 'getDeviceCacheUtil',
    'DeviceCpuUtil'     => 'getDeviceCpuUtil',
    'DeviceMemUtil'     => 'getDeviceMemUtil',
    'FwSession'         => 'getFwSession',
    };
}

sub IF_ID           { '1.3.6.1.2.1.2.2.1.2'  }
sub IF_STATE        { '1.3.6.1.2.1.2.2.1.8'  }
sub IF_SPEED        { '1.3.6.1.2.1.2.2.1.5'  }
sub IF_IN_OCTETS    { '1.3.6.1.2.1.2.2.1.10' }
sub IF_OUT_OCTETS   { '1.3.6.1.2.1.2.2.1.16' }

{
    my @support = qw (
        id_to_name  cpu_method  mem_method  if_in   if_out
        fw_session  base_num    
    );
sub new {
    my $class = shift;
    my %options = @_;
    my ($session, $error) = Net::SNMP->session(
        -hostname  => $options{host},
        -version   => $options{version},
        -community => $options{community},
    );
    if( ! defined $session ){
        return wantarray ? (undef,$error) : undef;
    }
    my $self = bless {
        'session'  => $session,
        'error'    => '',
        'debug'    => 0,
        'if_id'    => undef,
        'if_speed' => undef,
    },$class;
    # support args : id_to_name
    foreach my $key(keys %options){
        $self->{$key} = $options{$key};
    }
    wantarray ? ( $self,'') : $self;
}
}

sub debug_msg {
    my $self = shift;
    print "@_\n" if($self->{'debug'});
}

sub err_msg {
    my $self = shift;
    $self->{'error'} = "[ERROR] @_";
    require Carp;
    Carp::croak("@_");
}

sub _getValue {
    my ($self,$type,@args) = @_;
    $self->debug_msg( (caller 0)[2], (caller 1)[3] );
    $self->debug_msg("_getValue:接收参数:@_");
    my $result = undef;
    if( 'base' eq $type ){
        $result = $self->{'session'}->get_table( -baseoid => $args[0], );
    }
    elsif( 'list' eq $type ){
        $result = $self->{'session'}->get_request( -varbindlist => [@args], );
    }
    else {
        $self->err_msg("no support type : $type");
        return undef;
    }
    if(! defined $result){
        $self->err_msg("wrong getvalue:",$self->{'session'}->error);
        return undef;
    }
    $result; 
}

sub getIfId {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    foreach(keys %{$result}){
        my $id = (split /\./)[-1];
        $ret->{"ND_${res_name}_IF_${id}"}->{'IfId'} = $result->{$_};
    }
    # 保存指向 if_id 的引用，方便以后替换id为接口名称
    $self->{'if_id'} = $ret;
    $ret;
}

sub getIfState {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    foreach(keys %{$result}){
        my $id = (split /\./)[-1];
        if(exists $self->{'id_to_name'} && $self->{'id_to_name'}){
            $id = '(' . $self->{'if_id'}->{"ND_${res_name}_IF_${id}"}->{'IfId'} . ')';
        }
        my $val = $result->{$_};
        $val = ($val =~ /up|1/) ? 'UP' : 'DOWN';
        $ret->{"ND_${res_name}_IF_${id}"}->{'IfState'} = $val;
    }
    $ret;
}

sub getIfSpeed {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    foreach(keys %{$result}){
        my $id = (split /\./)[-1];
        if(exists $self->{'id_to_name'} && $self->{'id_to_name'}){
            $id = '(' . $self->{'if_id'}->{"ND_${res_name}_IF_${id}"}->{'IfId'} . ')';
        }
        my $val = $result->{$_};
        if($val =~ /0x/i){
            my $bn=Math::BigInt->new($val);
            $bn->as_hex();
            $val=$bn;
        }
        $ret->{"ND_${res_name}_IF_${id}"}->{'IfSpeed'} = $val;
    }
    # 保存指向 if_speed 的引用，方便以后获取接口速率
    $self->{'if_speed'} = $ret;
    $ret;   
}

sub getIfInOctets {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    my $dict = read_ini('./data_in') if (10 == $calculation);
    foreach(keys %{$result}){
        my $id = (split /\./)[-1];
        if(exists $self->{'id_to_name'} && $self->{'id_to_name'}){
            $id = '(' . $self->{'if_id'}->{"ND_${res_name}_IF_${id}"}->{'IfId'} . ')';
        }
        my $val = $result->{$_};
        if($val =~ /0x/i){
            my $bn=Math::BigInt->new($val);
            $bn->as_hex();
            $val=$bn;
        }
       ## (本次采样1.3.6.1.2.1.2.2.1.10.X-上次采样1.3.6.1.2.1.2.2.1.10.X）×8÷（采样间隔秒）÷(1.3.6.1.2.1.2.2.1.5.X)
        if(10 == $calculation ){
            my ($sec,$old) = split /\|/,$dict->{$res_name}->{$_};
            my $new_sec = time;
            $sec = $sec ? $sec : $new_sec - 600;
            $old = $old ? $old : $val;
            my $ifspeed = $self->{'if_speed'}->{"ND_${res_name}_IF_${id}"};
            $ifspeed = ( 0 == $ifspeed ) ? 1000000000 : $ifspeed ;
            $dict->{$res_name}->{$_} = "$new_sec|$val";
            $val = sprintf("%.2f", 100 * ( $val - $old ) * 8 / ( $new_sec - $sec ) / $ifspeed );
        }
        $ret->{"ND_${res_name}_IF_${id}"}->{'ifInOctets'} = $val;
    }
    write_ini('./data_in',$dict) if (10 == $calculation);
    $ret;   
}
sub getIfOutOctets {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    my $dict = read_ini('./data_out') if (10 == $calculation);
    foreach(keys %{$result}){
        my $id = (split /\./)[-1];
        if(exists $self->{'id_to_name'} && $self->{'id_to_name'}){
            $id = '(' . $self->{'if_id'}->{"ND_${res_name}_IF_${id}"}->{'IfId'} . ')';
        }
        my $val = $result->{$_};
        if($val =~ /0x/i){
            my $bn=Math::BigInt->new($val);
            $bn->as_hex();
            $val=$bn;
        }
        if(10 == $calculation){
            my ($sec,$old) = split /\|/,$dict->{$res_name}->{$_};
            my $new_sec = time;
            $sec = $sec ? $sec : $new_sec - 600;
            $old = $old ? $old : $val;
            my $ifspeed = $self->{'if_speed'}->{"ND_${res_name}_IF_${id}"};
            $ifspeed = ( 0 == $ifspeed ) ? 1000000000 : $ifspeed ;
            $dict->{$res_name}->{$_} = "$new_sec|$val";
            $val = sprintf("%.2f", 100 * ( $val - $old ) * 8 / ( $new_sec - $sec ) / $ifspeed );
        }
        $ret->{"ND_${res_name}_IF_${id}"}->{'ifOutOctets'} = $val;
    }
    write_ini('./data_out',$dict) if (10 == $calculation);
    $ret;  
}

#
# 值计算方式: 1--直接取值   2--计算取值 a/b  3--计算取值 a/(a+b)  4--平均值  5--任一值为0时取0
# 6--
sub getDeviceCacheUtil {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    my $val = undef;
    $calculation = $calculation ? $calculation : 1;
    if( 1 == $calculation ){
        $val = $result->{$oid};
    }
    elsif( 2 == $calculation || 3 == $calculation ){
        my ($a_val,$b_val) = @{$result}{@{$oid}};
        $val = (2 == $calculation) ? sprintf("%.2f",$a_val/$b_val*100) : sprintf("%.2f",$a_val/($a_val+$b_val)*100);
    }
    elsif( 4 == $calculation || 5 == $calculation ){
        $val = sum(values %{$result});
        $val = sprintf("%.2f",$val / (scalar keys %{$result}) );
        if( 5 == $calculation ){
            for(values %{$result}){
                if( 0 == $_ ){
                    $val = 0;
                    last;
                }
            }
        }
    }
    else{
        $self->err_msg("undefined method calculation : $calculation");
        return undef;
    }
    # DeviceCacheUtil
    foreach(keys %{$result}){
        $ret->{"ND_${res_name}"}->{'DeviceCacheUtil'} = $val;
    }
    $ret;
}
sub getDeviceCpuUtil {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    my $val = undef;
    $calculation = $calculation ? $calculation : 1;
    if( 1 == $calculation ){
        $val = $result->{$oid};
    }
    elsif( 2 == $calculation || 3 == $calculation ){
        my ($a_val,$b_val) = @{$result}{@{$oid}};
        $val = (2 == $calculation) ? sprintf("%.2f",$a_val/$b_val*100) : sprintf("%.2f",$a_val/($a_val+$b_val)*100);
    }
    elsif( 4 == $calculation || 5 == $calculation ){
        $val = sum(values %{$result});
        $val = sprintf("%.2f",$val / (scalar keys %{$result}) );
        if( 5 == $calculation ){
            for(values %{$result}){
                if( 0 == $_ ){
                    $val = 0;
                    last;
                }
            }
        }
    }
    else{
        $self->err_msg("undefined method calculation : $calculation");
        return undef;
    }
    foreach(keys %{$result}){
        $ret->{"ND_${res_name}"}->{'DeviceCpuUtil'} = $val;
    }
    $ret;
}
sub getDeviceMemUtil {
    my ($self,$type,$oid,$calculation) = @_;
    my $result = _getValue($self,
                           $type,
                           ref $oid eq 'ARRAY' ? @{$oid} : $oid,
                           );
    my $res_name = $self->{session}->hostname;
    my $ret = undef;
    my $val = undef;
    $calculation = $calculation ? $calculation : 1;
    if( 1 == $calculation ){
        $val = $result->{$oid};
    }
    elsif( 2 == $calculation || 3 == $calculation ){
        my ($a_val,$b_val) = @{$result}{@{$oid}};
        $val = (2 == $calculation) ? sprintf("%.2f",$a_val/$b_val*100) : sprintf("%.2f",$a_val/($a_val+$b_val)*100);
    }
    elsif( 4 == $calculation || 5 == $calculation ){
        $val = sum(values %{$result});
        $val = sprintf("%.2f",$val / (scalar keys %{$result}) );
        if( 5 == $calculation ){
            for(values %{$result}){
                if( 0 == $_ ){
                    $val = 0;
                    last;
                }
            }
        }
    }
    else{
        $self->err_msg("undefined method calculation : $calculation");
        return undef;
    }
    foreach(keys %{$result}){
        $ret->{"ND_${res_name}"}->{'DeviceMemUtil'} = $val;
    }
    $ret;
}
sub getFwSession { }

sub DESTORY {
    my $self = shift;
    foreach(keys %{$self}){
        undef $self->{$_} if defined $self->{$_};
    }
    return;
}

1;
