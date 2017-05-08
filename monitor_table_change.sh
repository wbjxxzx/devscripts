#!/usr/bin/ksh
###############################################################################
# 查询列配置，保存在./cfg/tablename.new 比较 tablename.new和tablename.ini 不一致则告警
# 查询目的数据库,以"|"分割导出所有数据,保存在./data/tablename.new
# 比较 tablename.new和tablename.old 不一致则告警
# 重命名 tablename.new -> tablename.old
# ./cfg 存放相关配置
# ./log 存放相关日志
###############################################################################

DEBUG="false"
if [ $DEBUG = "true" ];then
    orig_dir="."
else
    cd
    . ./.profile
    orig_dir="${HOME}/scrcoldispoy/checkBOSS3/DEM_BOMC_AA_20150901_161022776"
fi
v_date=`date +%Y%m%d%H%M%S`
tok=DEM_BOMC_AA_20150410_154039464.tok
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
substr() {
    str="${1:?missing string from which you want to get the sub string}"
    typeset -i len=${#str}
    typeset -i index="${2:-0}"
    typeset -i sublen="${3:-$len}"
    typeset -i rlen=len-index
    typeset -R$rlen substr=$str
    typeset -L$sublen substr=$substr
    echo $substr
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
    set  heading off feedback off newpage none pagesize 0 echo off termout off trimout on trimspool on linesize 4000
    #set colsep '|' heading off feedback off newpage none pagesize 0 echo off termout off trimout on trimspool on linesize 4000
    conn ${db_user}/${db_pass}@${db_name}
    spool ${data_file} 
      $sql_line;
    spool off
    quit
EOF
}
###############################################################################
# 函数:dbms_data 查询数据
# 由dbms_output.put生成数据
# 传递参数:用户名 密码 数据库名 数据文件名 表所有者 查询语句 表名
dbms_data(){
        db_user=$1
    db_pass=$2
    db_name=$3
    data_file=$4
    tb_own=$5
    sql_line=$6
    tb_name=$7
    sql_line="$sql_line from ${tb_own}.${tb_name}"
# DEM_BOMC_AA_20160120_140816698 对xg.sys_para增加过滤条件
    case `echo ${tb_own}.${tb_name} | tr a-z A-Z` in
        XG.SYS_PARA)
        sql_line="$sql_line where param_code not in ('JOB_AUTO_ASSIGN_ONOFF','DTIVR_STATUS','GPRS_STATUS','ZY_GPRS_STATUS','huawei_port') "
        ;;
    esac
    wlog "sql_line:$sql_line"
        dbms_line="dbms_output.put("
        cat ./cfg/${sname}.ini|grep -v '^[ ]$'|grep -v '^#'|while read column col_type
    do
        dbms_line="${dbms_line} ccrec.$column;"
    done
    dbms_line=${dbms_line%;*}
    dbms_line=`echo $dbms_line | sed "s/;/||'|'||/g"`
    dbms_line="$dbms_line )"
sqlplus -S /nolog<<EOF
    set  heading off feedback off newpage none pagesize 0 echo off termout off trimout on trimspool on linesize 8000
    set serveroutput on;
    conn ${db_user}/${db_pass}@${db_name}
    spool ${data_file} 
    
        declare
                cursor cc is $sql_line ;
                ccrec cc%rowtype;
                begin
        for ccrec in cc loop
                $dbms_line;
                dbms_output.new_line;
                end loop;       
    end;
    /
    
    spool off
    quit
EOF
}

###############################################################################
# 函数:diff_data 对比数据
# 传递参数:用户名 密码 数据库名 表所有者 表名 res_name ip
diff_data() {
        dbuser=$1
        dbpass=$2
        dbname=$3
        suser=$4
        sname=$5
        res_name=$6
        ip=$7
        wlog "根据./cfg/${sname}.ini拼接查询sql..."
    line="select "
    cat ./cfg/${sname}.ini|grep -v '^[ ]$'|grep -v '^#'|while read column col_type
    do
        wlog "$column $col_type"
        case $col_type in
            NUMBER|VARCHAR|VARCHAR2|CHAR)
                line="${line} replace(replace($column,chr(10)),chr(13)) $column;" ;;
                #line="${line} $column;" ;;
            DATE)
                line="${line} to_char($column,'yyyymmddhh24miss') $column;" ;;
            *)
                wlog "未识别的类型:$col_type" ;;
        esac
    done
    [ $DEBUG = "true" ] && wlog "line:$line"
    line=${line%;*}
    line=`echo $line | sed "s/;/,/g"`
    [ $DEBUG = "true" ] && wlog "line:$line"
        
    # 查询数据
    dbms_data $dbuser $dbpass $dbname ./data/${sname}.new $suser "$line" $sname
        
    # 首次执行，将${sname}.new添加至${sname}.old
    [ ! -e ./data/${sname}.old ] &&  cat ./data/${sname}.new > ./data/${sname}.old
    
    # 对比文件
    if [ -s ./data/${sname}.old ];then
        awk 'NR==FNR{if($0 !~ /^[ \t]*$/)arr[$0]+=1;next}{if($0 in arr || $0 ~ /^[ \t]*$/);else print;}' ./data/${sname}.old ./data/${sname}.new > ./data/${sname}.more
        awk 'NR==FNR{if($0 !~ /^[ \t]*$/)arr[$0]+=1;next}{if($0 in arr || $0 ~ /^[ \t]*$/);else print;}' ./data/${sname}.new ./data/${sname}.old > ./data/${sname}.less
    fi
    val=OK
    more_lines=`awk 'END{print NR}' ./data/${sname}.more`
    less_lines=`awk 'END{print NR}' ./data/${sname}.less`
    if [ $more_lines -eq 0 -a $less_lines -eq 0 ];then
        wlog "${sname}无数据更新"
    elif [ $more_lines -ne 0 -a $less_lines -eq 0 ];then
        wlog "${sname}有新增数据:"
                cat ./data/${sname}.more >> $log
        val="${sname}有${more_lines}行数据新增" 
                val=${val}":"`cat ./data/${sname}.more`
    elif [ $more_lines -eq 0 -a $less_lines -ne 0 ];then 
        wlog "${sname}有数据被删除:"
                cat ./data/${sname}.less >> $log
        val="${sname}有${less_lines}行数据被删除"              
                val=${val}":"`cat ./data/${sname}.less`
        else
                wlog "${sname}有数据变化:"
                wlog "原始数据:"
                cat ./data/${sname}.less >> $log
                wlog "变化后:"
                cat ./data/${sname}.more >> $log
                val="${sname}有${less_lines}行数据有变化"
                text=`awk 'NR==FNR{arr[FNR]=$0}{if(arr[FNR]!=$0){len=split(arr[FNR],old,"|");split($0,new,"|");for(i=1;i<=len;i++){if(old[i]==new[i]){printf("%s",old[i])}e
lse{printf("原数据【%s】-更新为【%s】",old[i],new[i])};if(i!=len)printf("@")}print ""}}' ./data/${sname}.less ./data/${sname}.more`
                val="${val}:$text"
    fi
        val=`echo "$val" | tr -d '\012\015'`
        val=`substr "$val" 0 450`
    # 当查询异常时不产生告警
    if [ "`head -1 ./data/${sname}.old`" = "SP2-0640: Not connected" -o "`head -1 ./data/${sname}.new`" = "SP2-0640: Not connected" ];then
        val=OK
    fi
        # 执行完毕，更新${sname}.old为${sname}.new
        cat ./data/${sname}.new > ./data/${sname}.old
    echo "${ip}*${res_name}[$sname]|PM-02-80-144-01|$val|$v_date" >> $tok
}

###############################################################################
# 函数:handle 处理数据
# 传递参数:配置文件
 handle() {
    table_name=$1
    cat $table_name|grep -v '^#'|while read suser sname dbname dbuser res_name ip
    do
                case $dbname in
                        zwdb) dbpass=aizw_246;;
                        jfdb) dbpass=aijf_235;;
                        jsdb) dbpass=aijs_258;;
                        njyydb) dbpass=aiyy_135;;
                        njggdb) dbpass=aigg_134;;
                        dzqd) dbpass=bomc_123;;
                esac
        sname=`echo $sname | tr 'A-Z' 'a-z'`
    wlog "开始获取${sname}列配置..."
    get_col_type $dbuser $dbpass $dbname $suser $sname
        cat ./cfg/${sname}.tmp|grep -v "^SQL>" |grep -v " Name " |grep -v " -------" | tr -d '\015'|awk '{gsub(/[0-9]?\([0-9]+\)/,"",$0);print $1,$NF}' > ./cfg/${sname}.co
l        
        if [ ! -e ./cfg/${sname}.ini ];then
        cat ./cfg/${sname}.col > ./cfg/${sname}.ini
    fi
    exist_table=`grep 'does not exist' ./cfg/${sname}.tmp | wc -l | awk '{printf("%d",$1)}'`
    if [ $exist_table -ne 0 ];then
        echo "${ip}*${res_name}[$sname]|PM-02-80-144-01|表${sname}不存在|$v_date" >> $tok
    else
        awk 'NR==FNR{if($0 !~ /^[ \t]*$/)arr[$1]+=1;next}{if($1 in arr || $0 ~ /^[ \t]*$/);else print;}' ./cfg/${sname}.ini ./cfg/${sname}.col > ./cfg/${sname}.new
        new_cols=`awk 'END{print NR}' ./cfg/${sname}.new`
        awk 'NR==FNR{if($0 !~ /^[ \t]*$/)arr[$1]+=1;next}{if($1 in arr || $0 ~ /^[ \t]*$/);else print;}' ./cfg/${sname}.col ./cfg/${sname}.ini > ./cfg/${sname}.old
        old_cols=`awk 'END{print NR}' ./cfg/${sname}.old`
        diff_cols=`expr $new_cols - $old_cols`
                if [ $diff_cols -eq 0 ];then
                        wlog "${sname}字段配置正常，开始判断数据..."
                        diff_data $dbuser $dbpass $dbname $suser $sname $res_name $ip
                elif [ $diff_cols -lt 0 ];then
                        diff_col=`awk '{print $1}' ./cfg/${sname}.old`
                        wlog "${sname}有字段被删除:$diff_col"
                        echo "${ip}*${res_name}[$sname]|PM-02-80-144-01|${sname}有字段被删除:$diff_col|$v_date" >> $tok
                        rm -rf ./data/${sname}.old
                else
                        diff_col=`awk '{print $1}' ./cfg/${sname}.new`
                        wlog "${sname}有新增字段:$diff_col"
                        echo "${ip}*${res_name}[$sname]|PM-02-80-144-01|${sname}有新增字段:$diff_col|$v_date" >> $tok
                        rm -rf ./data/${sname}.old
                fi
        fi
        wlog "============================================================"
        done
}
###############################################################################
# main
 main() {
    wlog "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    wlog "开始执行"
    handle $1
        [ "$DEBUG" = "false" ] && mv $tok $HOME/perfsrcfils/boss9
    wlog "执行完毕"
    wlog "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
}

if [ $# -ne 1 ];then
    echo "Usage $0 file"
    exit 1
else
    main $1
fi
