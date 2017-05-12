#!/usr/bin/perl
use constant PATH=>'${HOME}/NetNDInfo';
use constant DEBUG=>0;
BEGIN{unshift @INC,PATH}
use strict;
use Myfuncs;
use Mylog;
use File::Copy qw(move);
use File::Basename;
use Data::Dumper;
my @first_exec = qw( IfId IfSpeed );

# 切换目录
chdir PATH or die "$!\n";
my $mylog = Mylog->new(log_name => 'beta.log');

sub make_tok{
    my $dict = shift;
    my $dev  = shift;
    my $func = shift;
    my $kpi  = shift;
    my $is_exec = can_exec(@{$dict->{$kpi}}{qw(coll_unit collcyc)});
    #$is_exec = 1;
    if(exists $dict->{$kpi} && $is_exec){
        $mylog->write_file("采集kpi:$_");
        my $oid = $dict->{$kpi}->{oid};
        my $tok = $dev->{session}->hostname."_${kpi}_netdevice.tok";
        $mylog->write_file("type:$dict->{$kpi}->{type},oid:",ref $oid eq "ARRAY" ? "@{$oid}" : "$oid");
        my $ret = eval{$dev->${$func}($dict->{$kpi}->{type},
             $oid =~ /\|/ ? [ split /\|/,$oid ] : $oid,
             $dict->{$kpi}->{calculation},
            )};
        if($@){
            $mylog->write_file( "wrong get value $@ ",$dev->{'error'} );
            next;
        }
        elsif(! defined $ret){
            $mylog->write_file( $dev->{'error'} );
        }
        else{
            open FW,'>',$tok or die "$!\n";
            # 写入tok
            # 修改端口标识和端口速率每天10点写入到tok
            my ($mi,$hh) = (localtime())[1,2];
            if( $kpi =~ /IfId/ ){
                $ret = {} unless 10 == $hh && $mi < 5 ;
            }
            if( $kpi =~ /IfSpeed/ ){
                $ret = {} unless 8 == $hh && $mi < 5 ;
            }
            for(keys %{$ret}){
                print FW $_,"|",$kpi,"|",$ret->{$_}->{$kpi},"|",get_now,"\n";
            }
            close FW;
            move $tok,"${HOME}/netdevice" unless DEBUG;
        }
        #$mylog->write_file("-"x30);
        delete $dict->{$kpi};
    }
}

$mylog->write_file("="x50);
$mylog->write_file("开始采集");
while(<./config/*.cfg>){
    my $cfg = $_;
    $mylog->write_file( "读取配置文件:$cfg" );
    my $dict = read_ini($cfg);
    (my $host = $cfg ) =~ s/\.cfg//;
    $host = basename($host);
    print Dumper($dict) if DEBUG;
    $mylog->write_file("获取主机:$host");
    $ENV{VENDOR} = lc $dict->{global}->{vendor};
    
    my $subpid = fork();
    if(!defined $subpid){
        $mylog->write_file("fork ERROR!");
    }
    elsif(0 == $subpid){
        # 引入package;
        require "Netdevice.pm";
        my $funcs = Netdevice->get_funcs;
        print "funcs:$funcs\n" if DEBUG;
        my $dev = Netdevice->new(
            debug       => 1,
            host        => $host,
            version     => $dict->{global}->{version},
            community   => $dict->{global}->{community},
            id_to_name  => $dict->{global}->{id_to_name},
            );
        for(@first_exec){
            make_tok($dict,$dev,\$funcs->{$_},$_);
        }
        for(keys %{$funcs}){
            if(exists $dict->{$_}){
                make_tok($dict,$dev,\$funcs->{$_},$_);
            }
        }
        $dev->DESTORY;
        exit;
    }
    else {
        waitpid ($subpid, 0);
    }
    $mylog->write_file("="x50);
}