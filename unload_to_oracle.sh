#!/usr/bin/ksh
#某数据库有几张表更新，本地数据库增量更新数据，用脚本定时执行实现。
#　　由于无blob/clob字段,使用sqlldr导入数据:查询目的数据库,以"|"分割导出所有数据,保存在./data/tablename.new
#　　比较 tablename.new和tablename.old，将 tablename.new有,而tablename.old没有的数据更新至目的数据库，并添加至tablename.old
#　　./data/tablename.ctl存放sqlldr控制文件
#　　./log 存放相关日志
#　　执行时发现bash中的while创建了子shell，不能保存变量的值，解决办法：
#　　1、使用其他shell，如：ksh
#　　2、形如 while read line ;do ... ;done < file
#　　代码如下：

DEBUG="false"
if [ $DEBUG = "true" ];then
    orig_dir="."
else
    cd
    . ./.profile
    orig_dir="${HOME}"
fi
v_date=`date +%Y%m%d%H%M%S`
###############################################################################
# 日志文件，大于20M时压缩半数行
cd $orig_dir
log="$orig_dir/log/alpha.log"
[ ! -d $orig_dir/log ] && mkdir $orig_dir/log
[ ! -d $orig_dir/cfg ] && mkdir $orig_dir/cfg
[ ! -d $orig_dir/data ] && mkdir $orig_dir/data
if [ -e $log ];then
    log_size=`ls -l $log | awk '{printf("%d",$5)}'`
    if [ -n "$log_size" -a $log_size -gt 20971520 ];then
        half_line=`awk 'END{printf("%d",NR/2)}' $log`
        perl -ni -e "print if(\$.>$half_line)" $log
    fi
fi
###############################################################################
# 写日志
wlog() {
    echo "`date +%Y-%m-%d' '%H:%M:%S`: $*">>$log
}
###############################################################################
# 函数:get_col_type 获取列、类型 
# 传递参数:用户名 密码 数据库名 表所有者 表名
 get_col_type() {
    db_user=$1
    db_pass=$2
    db_name=$3
    tb_own=$4
    tb_name=$5
    tmp=./cfg/${tb_name}.tmp
    tb_name="${tb_own}.${tb_name}"
sqlplus ${db_user}/${db_pass}@${db_name}<<EOF
    set heading off feedback off pagesize 0 verify off echo off
    spool $tmp
        desc ${tb_name};
    spool off
    quit
EOF
}
###############################################################################
# 函数:make_ctl 生成控制文件
# 传递参数:目的表名
 make_ctl() {
    d_name=$1
    ctl_file=./data/${d_name}.ctl
    echo "load data" > $ctl_file
    echo "infile './data/${d_name}.unl'" >> $ctl_file
    echo "append into table ${d_name}" >> $ctl_file
    echo "fields terminated by '|'" >> $ctl_file
    echo "(" >> $ctl_file
    cat ./cfg/${d_name}.ini|grep -v '^[ \t]*$'|grep -v '^#'|while read column col_type
    do
        case $col_type in
            NUMBER|VARCHAR|VARCHAR2) 
                echo "$column," >> $ctl_file ;;
            DATE)
                echo "$column \"to_date(:$column,'yyyymmddhh24miss')\"," >> $ctl_file ;;
            *)
                wlog "未识别的类型:$col_type" ;;
        esac
    done
    echo ")" >> $ctl_file
    # 替换末尾的,)为)
    perl -pi -e 'undef $/;s/,\r?\n\)/\n\)/' $ctl_file
}

###############################################################################
# 函数:select_sql 查询数据
# 传递参数:用户名 密码 数据库名 数据文件名 表所有者 查询语句 表名
# select CALL_ID||'|'||to_char(END_TIME,'yyyymmddhh24miss')||'|'||CALLER||'|'||SERVICE_NO||'|'||CALL_PURPOSE from tablename; 
 select_sql() {
    db_user=$1
    db_pass=$2
    db_name=$3
    data_file=$4
    tb_own=$5
    sql_line=$6
    tb_name=$7
    sql_line="$sql_line from ${tb_own}.${tb_name}"
    wlog "查询sql:$sql_line"
    # set closep '|'
sqlplus -S /nolog<<EOF
    set heading off feedback off newpage none pagesize 0 echo off termout off trimout on trimspool on linesize 800
    conn ${db_user}/${db_pass}@${db_name}
    spool ${data_file} 
      $sql_line;
    spool off
    quit
EOF
}

###############################################################################
# 函数:handle 处理数据
# 传递参数:配置文件
 handle() {
    table_name=$1
    cat $table_name|grep -v '^#'|while read suser sname dname
    do
        # 如果dname为空,默认使用sname
        [ -z "$dname" ] && dname=$sname
        sname=`echo $sname | tr 'A-Z' 'a-z'`
        dname=`echo $dname | tr 'A-Z' 'a-z'`
    
        [ -e ./log/${dname}.log ] && : > ./log/${dname}.log
        [ -e ./log/${dname}.bad ] && : > ./log/${dname}.bad
        [ -e ./log/${dname}.unl ] && : > ./log/${dname}.unl

        if [ ! -e ./cfg/${dname}.ini ];then
            wlog "不存在./cfg/${dname}.ini,开始获取${dname}列配置..."
            get_col_type dest_db_user dest_db_pass DBNAME dest_db_user $dname
            cat ./cfg/${dname}.tmp|grep -v "^SQL>" |grep -v " Name " |grep -v " -------" | tr -d '\015'|awk '{gsub(/[0-9]?\([0-9]+\)/,"",$0);print $1,$NF}' > ./cfg/${dname}.ini    
        fi        
        wlog "根据./cfg/${dname}.ini拼接查询sql..."
        wlog "${dname}列配置为:"
        line="select"
        cat ./cfg/${dname}.ini|grep -v '^[ \t]*$'|grep -v '^#'|while read column col_type
        do
            wlog "$column $col_type"
            case $col_type in
                NUMBER|VARCHAR|VARCHAR2)
                    line="${line} $column;" ;;
                DATE)
                    line="${line} to_char($column,'yyyymmddhh24miss');" ;;
                *)
                    wlog "未识别的类型:$col_type" ;;
            esac
        done
        [ $DEBUG = "true" ] && wlog "line:$line"
        # 去掉最后一个分号，替换所有分号为|
        line=${line%;*}
        line=${line//,/"||'|'||"}
        [ $DEBUG = "true" ] && wlog "line:$line"
        
        # 不存在$sname.old时创建$sname.old
        [ ! -e ./data/${sname}.old ] && touch ./data/${sname}.old
        
        if [ ! -s ./data/${sname}.old ];then
            wlog "./data/${sname}.old为空，从目的表获取数据..."
            select_sql dest_db_user dest_db_pass DBNAME ./data/${sname}.old dest_db_user "$line" $dname
            wlog "目的表数据获取成功,从源表获取数据..."
        fi
            
        select_sql source_db_user source_db_pass SDBNAME ./data/${sname}.new $suser "$line" $sname
        # 对比文件，选出在new中但不在old中的行
    if [ -s ./data/${sname}.old ];then
        awk 'NR==FNR{if($0 !~ /^[ \t]*$/)arr[$0]+=1;next}{if($0 in arr || $0 ~ /^[ \t]*$/);else print;}' ./data/${sname}.old ./data/${sname}.new > ./data/${dname}.unl
    else
        cp ./data/${sname}.new ./data/${dname}.unl 
    fi        
        data_lines=`awk 'END{print NR}' ./data/${dname}.unl`        
        if [ ! -e ./data/${dname}.ctl ];then
            wlog "不存在./data/${dname}.ctl,开始生成./data/${dname}.ctl "
            make_ctl ${dname}
        fi

        if [ $data_lines -eq 0 ];then
            wlog "本次无数据需要更新"
        else
            wlog "本次需要更新${data_lines}条数据"
            wlog "执行sqlldr..."
            sqlldr dest_db_user/dest_db_pass@DBNAME control=./data/${dname}.ctl direct=true log=./log/${dname}.log bad=./log/${dname}.bad
            succ_cnt=`grep successfully ./log/${dname}.log | awk '{print $1}'`
            bad_cnt=0
            [ -e ./log/${dname}.bad ] && bad_cnt=`wc -l ./log/${dname}.bad | awk '{print $1}'`
            wlog "成功更新:${succ_cnt}条数据,${bad_cnt}条失败"
        fi

        # 执行完毕，将${dname}.unl添加至${sname}.old
        cat ./data/${dname}.unl >> ./data/${sname}.old
    done
}
###############################################################################
# main
 main() {
    wlog "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    wlog "开始执行"
    handle $1
    wlog "执行完毕"
    wlog "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
}

if [ $# -ne 1 ];then
    echo "Usage $0 file"
    exit 1
else
    main $1
fi
