package Local::Funcs;
use strict;
use POSIX qw{strftime};
use Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT = qw(read_ini write_ini get_now get_day read_cfg can_exec );
@EXPORT_OK= qw(get_now get_day );
%EXPORT_TAGS = (
    all => [@EXPORT, @EXPORT_OK],
    get_now => [qw{get_now}],
    get_day => [qw{get_day}],
);

# 解析ini文件，传入文件，返回指向hash的引用
sub read_ini{
    my $file = shift;
    my $dict = {};
    my $this = $dict;

    open FR,'<',"$file" or die "$!\n";
    while(<FR>){
        chomp;
        #解释行和空白行跳过不做处理
        if(/^\s*#|^\s*$/){
            next;
        }
        #将[ ]作为头做处理，如有重复将覆盖
        elsif(/^\s*\[(.*)\]\s*$/){
            (my $section = $1) =~ s/^\s*|\s*$//g;
            if(exists $dict->{$section}){    
                $this = $dict->{$section};
            }
            else{
                $dict->{$section} = {};
                $this = $dict->{$section};
            }
        }
        #定义处理，如有重复将合并
        elsif(/^\s*([^ ]+)\s*=\s*([^ ]+)$/){
            if(exists $this->{$1}){
                if(ref($this->{$1}) eq "ARRAY"){
                    push @{$this->{$1}},$2;
                }
                else{
                    $this->{$1} = [ $this->{$1} ];
                    push @{$this->{$1}},$2;   
                }
            }
            else{
                $this->{$1} = $2;
            }
        }
        #不符合INI文件定义则报错
        else{
            print "Line format error: $_";
        }   
    }
    close FR;
    $dict;
}
###############################################################################
# 写入ini文件，传入目标文件，hash引用
sub write_ini{
    my $file = shift;
    my $dict = shift;
    open FH,'>',"$file" or die "$!\n";    
    foreach my $section(keys %$dict){
        if( ref($dict->{$section}) eq "HASH" ){
            print FH "[",$section,"]\n";
            foreach my $key(keys %{$dict->{$section}}){
                if( ref($dict->{$section}->{$key}) eq "ARRAY" ){
                    print FH "$key=$_\n" for @{$dict->{$section}->{$key}};
                }
                else{
                    print FH "$key=",$dict->{$section}->{$key},"\n";
                }
            }
        }
        else{
            print FH "$section=$dict->{$section}\n";
        }
    }
    close FH;
}
###############################################################################
# 返回时间格式: yyyymmddhh24miss,如:20150113170000
sub get_now{
    strftime("%Y%m%d%H%M%S",localtime());
}
###############################################################################
# 返回日期格式: yyyymmdd,如:20150113,无参数返回今天,N返回N天前
sub get_day{
    my $days = ($_[0]) ? $_[0] : 0;
    my $sec = time - 86400 * $days;
    strftime("%Y%m%d",localtime($sec));
}
###############################################################################
# 判断采集时间,传递参数:采集频率,采集时间
sub can_exec{
    my ($cyc,$col_time) = @_;
    my $is_exec = 0;
    if($cyc =~ /min/){
        my @col_h = split(/,/,$col_time);
        my ($mi,$hh) = (localtime())[1,2];
        $is_exec = 1 if ($mi % $col_time) < 5;
    }
    $is_exec;
}

1;