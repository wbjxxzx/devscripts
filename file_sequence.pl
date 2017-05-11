#!/usr/bin/env perl
###############################################################################
# 需求描述：全量采集话单序列号是否连续，如果同样的序号不连续，连续出现2次则呈现告警。
# 频率 30分钟 kpi: checkJFserial 检查是否出现语音话单文件序列号不连续
# 例：CNGO 本次采集缺少序列号 99，保存缺少99为1次，
#     下次采集时若还是缺少99，则告警
# 超过 cnt_ok 次才告警
###############################################################################
# 保存本次采集最大序列号、本次缺少序列号,不检查是否缺少头、尾序列号
BEGIN {unshift @INC,'${HOME}/local_perl_lib'}
use strict;
use constant DEBUG=>0;
use File::Copy qw(move);
use File::Basename;
use Local::Funcs;
use Local::Log;
use List::Util qw(max);
use Data::Dumper;
use vars qw($orig_dir $tok_head $lfh $htn $ymd $cnt_ok);

sub init {
    $orig_dir = '${HOME}/scrcoldispoy/checklog/DEM_BOMC_AA_20160129_163159229';
    $orig_dir = '.' if DEBUG;
    chdir $orig_dir or die "$!\n";
    $tok_head = 'DEM_BOMC_AA_20160129_163159229';
    chomp($htn = `hostname`);
    $lfh = Local::Log->new(debug => DEBUG);
    $cnt_ok = 2;
}
# 获取绝对路径
sub get_fullname {
    my $in = shift;
    $ymd = get_day;
    $lfh->write_file("接收:$in");
    (my $out = $in) =~ s/#YYYYMMDD#/$ymd/g;
    $out =~ tr/.//d;
    $lfh->write_file("输出:$out");
    $out;
}

# 获取全部序列号，存入hash，返回hash的引用
sub get_serials {
    my $fullname = shift;
    my $path = dirname($fullname);
    my $filename = basename($fullname);
    my $serials = {};
    $lfh->write_file("读取目录:$path");
    $lfh->write_file("文件:$filename");
    opendir DIR,$path or $lfh->write_file("[WRONG] open $path $!");
    for(readdir DIR){
        #print '$_:',$_,"\n" if DEBUG;
        if(/$filename\.?(\d+)/){
            $serials->{"$1"} = 1;
            $lfh->write_file("文件名:$_ 捕获:$1") if DEBUG;
        }
    }
    closedir DIR;
    $serials;
}

# 判断序列号是否连续，传入hash引用，返回数组
sub is_continuation {
    my $dict = shift;
    my $begin = shift;
    my @serials = sort keys %{$dict}; 
    my @ret = ();    
    for(my $idx = $begin; $idx < $#serials; $idx++){
        if(1 != $serials[$idx + 1] - $serials[$idx]){
            my $len = length($serials[$idx]);
            push @ret,sprintf("%0${len}d",$serials[$idx] + 1);
        }
    }
    @ret;
}

# 判断上次缺少的序列号是否已经存在,存在则次数=0，不存在则次数+1
sub last_absence_exists {
    my $dict = shift;
    my $last_absence = shift;
    for(keys %{$last_absence}){
        if(exists $dict->{$_} || $_ eq ''){
            $last_absence->{$_} = 0;
            # 本次存在序列号，从hash删除
            delete $last_absence->{$_};
        }
        else{
            $last_absence->{$_}++;
        }
    }
    $last_absence;
}
# 读取文件
sub read_cfg {
    my $cfg_file = shift;
    my $ref_arr = undef;
    open FR,'<',$cfg_file or die "$!\n";
    while(<FR>){
        chomp;
        push @{$ref_arr},$_ unless /^#|^\s*$/;
    }
    $ref_arr;
}

# 数组转换为hash
sub arr_to_hash {
    my $ref_arr = shift;
    my $ref_hash = {};
    $ref_arr = ref $ref_arr ? $ref_arr : [$ref_arr];
    for(@$ref_arr){
        my ($key,$value) = split /:/,$_;
        $ref_hash->{$key} = $value;
    }
    $ref_hash;
}

# hash转为数组
sub hash_to_arr {
    my $ref_hash = shift;
    my $ref_arr = [];
    for(keys %{$ref_hash}){
        push @{$ref_arr},"$_:$ref_hash->{$_}";
    }
    $ref_arr;
}

sub main {
    init;
    my $last_collect = eval{read_ini('./data')};
    my $ref_cfg = read_cfg('./file.cfg');
    if(defined $ref_cfg){
        open TOK,'>',"$tok_head.tok" or die "$!\n";
        for(@$ref_cfg){
            my ($fullpath) = (split /;/,$_)[0];
            my $res_name = "${htn}_checkJFserial_$fullpath";
            $fullpath = get_fullname($fullpath);
            my $ref_serials = get_serials($fullpath);
            my @cur_absence = ();
            unless(exists $last_collect->{$fullpath}){
                 $last_collect->{$fullpath}->{last_num} = 0;
                 $last_collect->{$fullpath}->{last_absence} = [];
            }
            # 先查找本次缺失，保存到hash
            @cur_absence = is_continuation($ref_serials,
                        $last_collect->{$fullpath}->{last_num}
                        );
            # 判断上次缺失
            $last_collect->{$fullpath}->{last_absence} = last_absence_exists($ref_serials,
                        arr_to_hash($last_collect->{$fullpath}->{last_absence})
                        );
            my @ret = ();
            print Dumper($last_collect->{$fullpath}->{last_absence}) if DEBUG;
            for(keys %{$last_collect->{$fullpath}->{last_absence}}){
                # 超过几次才告警
                push @ret,$_ if defined $_ and $last_collect->{$fullpath}->{last_absence}->{$_} > $cnt_ok;
            }
            $last_collect->{$fullpath}->{last_absence} = hash_to_arr($last_collect->{$fullpath}->{last_absence});
            $lfh->write_file("本次缺失序列号:@cur_absence");
            #map{push @{$last_collect->{$fullpath}->{last_absence}},sprintf("%04d:1",$_)}@cur_absence if(@cur_absence);
            map{push @{$last_collect->{$fullpath}->{last_absence}},"$_:1"}@cur_absence if(@cur_absence);
            $last_collect->{$fullpath}->{last_num} = max keys %{$ref_serials};
            #print Dumper($last_collect) if DEBUG;
            print Dumper(\@ret) if DEBUG;
            my $value = 'OK';
            if(@ret){
                $value = "缺少序列号:".join',',@ret;
            }
            $lfh->write_file("$fullpath:\n$value");
            print TOK "$res_name|checkJFserial|$value|@{[+get_now]}\n";
        }
        close TOK;
        write_ini('./data',{map{$_=>$last_collect->{$_}}grep{/$ymd/}keys %$last_collect});
        move "$tok_head.tok",'${HOME}/perfsrcfils/' unless DEBUG;
    }
    else{
        $lfh->write_file("配置文件:file.cfg不存在");
    }
    $lfh->close_file;
}
&main;