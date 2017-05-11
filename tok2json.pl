sub listdir {
    my $rootdir = shift;
    my $ref_arr = shift;
    opendir DIR,$rootdir;
    for my $name(readdir DIR){
        if( -d "$rootdir/$name" ){            
            listdir("$rootdir/$name",$ref_arr) unless $name =~ /^\.{1,2}$/;
        }
        else{
            if( 500 > @{$ref_arr} && $name =~ /\.tok$/i ){
                push @{$ref_arr},"$rootdir/$name";
            }
        }
    }
    closedir DIR;
}
sub get_tokfiles {
    my $path = "$ENV{HOME}/perfbackfils";
    my $tokfiles = [];
    listdir($path,$tokfiles);
    $tokfiles;
}
sub clearup {
    my $ref_arr = shift;
    unlink "$_" for @{$ref_arr};
}
sub get_now {
    my ($ss,$mi,$HH,$dd,$mm,$yyyy) = localtime();
    $yyyy += 1900;
    $mm += 1;
    sprintf("%4d-%02d-%02d %02d:%02d:%02d",$yyyy,$mm,$dd,$HH,$mi,$ss);
}
sub timefmt {
    my $str = shift;
    # 不满足时间格式或老旧数据
    if(length($str) != 14 || $str < 20160901090000 ){
        return '';
    }
    else{
        my $yyyy = substr($str,0,4);
        my $mm   = substr($str,4,2);
        my $dd   = substr($str,6,2);
        my $HH   = substr($str,8,2);
        my $mi   = substr($str,10,2);
        my $ss   = substr($str,12,2);
        sprintf("%4d-%02d-%02d %02d:%02d:%02d",$yyyy,$mm,$dd,$HH,$mi,$ss);
    }
}
sub escape_char { 
    my $str = shift;
    $str =~ s/\\/\\\\/g;
    $str =~ s/"/\\"/g;
    $str;
}
sub simple_json {
    my ($val,$str) = @_;
    my $type = ref $val;
    if( 'HASH' eq $type ){
        $$str .= '{';
        my $comma = '';
        for(keys %{$val}){
            my $valid_key = escape_char($_);
            $$str .= $comma . qq{"$valid_key":};
            simple_json($val->{$_},$str);
            $comma = ',';
        }
        $$str .= '}';
    }
    elsif( 'ARRAY' eq $type ){
        $$str .= '[';
        my $comma = '';
        for(@{$val}){
            $$str .= $comma;
            simple_json($_,$str);
            $comma = ',';
        }
        $$str .= ']';
    }
    else {
        $val = escape_char($val);
        $$str .= qq{"$val"};
    }
}
sub my_json {
    my $dict = shift->{resources};
    if(0 == @{$dict}){
        print '"resources":[]';
        }
    else{
        print '"resources":',simple_json($dict);
    }
}
sub output_json {
    #use JSON qw(to_json);
    print '"resources":',to_json(shift->{'resources'});
}
sub pharse_tok {
    my $ref_arr = shift;
    my $resources = {};
    for(@{$ref_arr}){
        my $tokfile = $_;
        my $d_res = {};
        open FR,'<',$tokfile or next;
        my $line = '';
        while($line = <FR>){
            next if $line =~ /^\s*$/;
            $line =~ s/^\s*|\s*$//g;
            my ($res_filter,$kpi,$val,$timestamp) = split /\|/,$line;
            $val =~ s/^\s*|\s*$//g;
            $val = 0 == length($val) ? undef : $val;
            
            # 对每个 res_filter ，将时间戳相同的 kpi,val 合并入匿名数组
            # 并丢弃 val 为空的值
            if("x$val" ne "x"){
                push @{$d_res->{$res_filter}->{$timestamp}},[$kpi,$val];
            }
        }
        close FR;
        
        for my $res(keys %{$d_res}){
            my $dn = {};
            $dn->{'dn'} = $res;   
            for my $timestr(keys %{$d_res->{$res}}){
                my @ret = @{$d_res->{$res}->{$timestr}};
                my $cnt = scalar @ret;
                my $kpistr = join "|",map{$ret[$_][0]}0..$#ret;
                my $valstr = join "|",map{$ret[$_][1]}0..$#ret;
                #$valstr =~ s/"/\\"/g;
                push @{$dn->{'performances'}},
                    { 'time'        => timefmt($timestr),
                      'columnCount' => $cnt,
                      'keyColumn'   => -1,
                      'seperator'   => '|',
                      'data'        => "$kpistr|$valstr"
                    };
            }
            push @{$resources->{'resources'}},$dn;
        }        
    }
    $resources;
}
sub main {
    my $ref_arr = get_tokfiles;
    my_json(pharse_tok($ref_arr));
    clearup($ref_arr);
}