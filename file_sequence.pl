#!/usr/bin/env perl
###############################################################################
# ����������ȫ���ɼ��������к��Ƿ����������ͬ������Ų���������������2������ָ澯��
# Ƶ�� 30���� kpi: checkJFserial ����Ƿ�������������ļ����кŲ�����
# ����CNGO ���βɼ�ȱ�����к� 99������ȱ��99Ϊ1�Σ�
#     �´βɼ�ʱ������ȱ��99����澯
# ���� cnt_ok �βŸ澯
###############################################################################
# ���汾�βɼ�������кš�����ȱ�����к�,������Ƿ�ȱ��ͷ��β���к�
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
# ��ȡ����·��
sub get_fullname {
    my $in = shift;
    $ymd = get_day;
    $lfh->write_file("����:$in");
    (my $out = $in) =~ s/#YYYYMMDD#/$ymd/g;
    $out =~ tr/.//d;
    $lfh->write_file("���:$out");
    $out;
}

# ��ȡȫ�����кţ�����hash������hash������
sub get_serials {
    my $fullname = shift;
    my $path = dirname($fullname);
    my $filename = basename($fullname);
    my $serials = {};
    $lfh->write_file("��ȡĿ¼:$path");
    $lfh->write_file("�ļ�:$filename");
    opendir DIR,$path or $lfh->write_file("[WRONG] open $path $!");
    for(readdir DIR){
        #print '$_:',$_,"\n" if DEBUG;
        if(/$filename\.?(\d+)/){
            $serials->{"$1"} = 1;
            $lfh->write_file("�ļ���:$_ ����:$1") if DEBUG;
        }
    }
    closedir DIR;
    $serials;
}

# �ж����к��Ƿ�����������hash���ã���������
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

# �ж��ϴ�ȱ�ٵ����к��Ƿ��Ѿ�����,���������=0�������������+1
sub last_absence_exists {
    my $dict = shift;
    my $last_absence = shift;
    for(keys %{$last_absence}){
        if(exists $dict->{$_} || $_ eq ''){
            $last_absence->{$_} = 0;
            # ���δ������кţ���hashɾ��
            delete $last_absence->{$_};
        }
        else{
            $last_absence->{$_}++;
        }
    }
    $last_absence;
}
# ��ȡ�ļ�
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

# ����ת��Ϊhash
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

# hashתΪ����
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
            # �Ȳ��ұ���ȱʧ�����浽hash
            @cur_absence = is_continuation($ref_serials,
                        $last_collect->{$fullpath}->{last_num}
                        );
            # �ж��ϴ�ȱʧ
            $last_collect->{$fullpath}->{last_absence} = last_absence_exists($ref_serials,
                        arr_to_hash($last_collect->{$fullpath}->{last_absence})
                        );
            my @ret = ();
            print Dumper($last_collect->{$fullpath}->{last_absence}) if DEBUG;
            for(keys %{$last_collect->{$fullpath}->{last_absence}}){
                # �������βŸ澯
                push @ret,$_ if defined $_ and $last_collect->{$fullpath}->{last_absence}->{$_} > $cnt_ok;
            }
            $last_collect->{$fullpath}->{last_absence} = hash_to_arr($last_collect->{$fullpath}->{last_absence});
            $lfh->write_file("����ȱʧ���к�:@cur_absence");
            #map{push @{$last_collect->{$fullpath}->{last_absence}},sprintf("%04d:1",$_)}@cur_absence if(@cur_absence);
            map{push @{$last_collect->{$fullpath}->{last_absence}},"$_:1"}@cur_absence if(@cur_absence);
            $last_collect->{$fullpath}->{last_num} = max keys %{$ref_serials};
            #print Dumper($last_collect) if DEBUG;
            print Dumper(\@ret) if DEBUG;
            my $value = 'OK';
            if(@ret){
                $value = "ȱ�����к�:".join',',@ret;
            }
            $lfh->write_file("$fullpath:\n$value");
            print TOK "$res_name|checkJFserial|$value|@{[+get_now]}\n";
        }
        close TOK;
        write_ini('./data',{map{$_=>$last_collect->{$_}}grep{/$ymd/}keys %$last_collect});
        move "$tok_head.tok",'${HOME}/perfsrcfils/' unless DEBUG;
    }
    else{
        $lfh->write_file("�����ļ�:file.cfg������");
    }
    $lfh->close_file;
}
&main;