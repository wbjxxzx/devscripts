#!/usr/bin/bash

#1.A 数据库统计数据
#
#begin_date  大于等于本月1日0点0分0秒
#end_date    小于等于下月1日0点0分0秒
#update_time 截取前8位大于等于昨天日期
#提取出id（用户ID），gb（流量GB值），update_time（最近使用时间）
#2.使用步骤1中的id去 B 的 v视图中找到bill_id
#select bill_id from v
#where effective_date <= sysdate and expire_date >= sysdate and user_id in (步骤1中的aimdb_owner_id);
#3.COMMONDB 提取bill_id用户号码
#select bill_id from t where effective_date <= sysdate and expire_date >= sysdate;
#如果有步骤2中的bill_id不在步骤3的bill_id中，那么则告警
#告警短信内容：
#2级告警，每天9点30分运行一次，每月1号不运行
# I must get water on the brain with bash

DEBUG="false"
if [ $DEBUG = "true" ];then
    orig_dir="."
else
    cd
    . ./.profile
    orig_dir="${HOME}/"
fi

# 日志文件，大于20M时压缩半数行
cd $orig_dir
log="$orig_dir/alpha.log"
if [ -e $log ];then
    log_size=`ls -l $log | awk '{printf("%d",$5)}'`
    if [ -n "$log_size" -a $log_size -gt 20971520 ];then
        half_line=`awk 'END{printf("%d",NR/2)}' $log`
        perl -ni -e "print if(\$.>$half_line)" $log
    fi
fi

tok=DEM_BOMC_20170412_110026091.tok
# 写日志
wlog() {
    echo "`date +%Y-%m-%d' '%H:%M:%S`: $*">>$log
}

wlog "===============start==============="
dd=`date +%d`
if [ $dd -eq 1 ];then
    wlog "1号不运行"
    wlog "-----------------end------------"
    exit 0
fi
# 索引数组定义
user_ids=""
yydb_user_ids=""
# hash数组定义
declare -A bill_id
# 结果定义
r_cnt=0
ret=""

common_bill_id_sql="select bill_id from t where effective_date <= sysdate and expire_date >= sysdate;"
wlog "select_sql:$common_bill_id_sql"
common_user_ids=`~/db common "$common_bill_id_sql"`
wlog "data:$ggdb_user_ids"
while read txt
do
    if [ -n "$txt" ];then
        bill_id["x$txt"]=1
    fi
done << DATA
 $common_user_ids
DATA

this_mon=`date +"%Y%m01000000"`
next_mon=`perl -e '($mm,$yyyy)=(localtime())[4,5];$yyyy+=1900;$mm+=1;$mm==12 and ($mm=0,$yyyy++);$mm++;printf("%4d%02d01000000",$yyyy,$mm)'`
yesterday=`perl -MPOSIX -e 'print strftime("%Y%m%d",localtime(time-24*3600))'`
jf_sql="select id||'|'||gb||'|'||update_time from (
select a.id,round(a.value/1024/1024/1024,2) gb,a.update_time
  from t a
 where a.begin_date >= ${this_mon}
   and a.end_date <= ${next_mon}
   and a.item_code = 40565321
   and a.value > 50.5*1024*1024*1024
   and substr(a.update_time,1,8) >= '$yesterday')
  order by gb;"
wlog "select_sql:$jf_sql"
xbjf_data=`~/db jf "$jf_sql"`
wlog "data:$jf_data"

cnt=0
idx=0
while read txt
do
    if echo "$txt" | grep "|" 1>/dev/null 2>&1;then
        if [ -z "${user_ids[$idx]}" ];then
            user_ids[$idx]="${txt%%|*}"
        else
            user_ids[$idx]="${user_ids[$idx]},${txt%%|*}"
        fi
        cnt=`expr $cnt + 1`
    fi
    # oracle in 语法超过 1000 项时会报错
    # 大于 500 分行
    if [ $cnt -ge 500 ];then
        idx=`expr $idx + 1`
        cnt=0
    fi
done << DATA
 $jf_data
DATA

for k in ${!user_ids[@]}
do
    if [ -n "${user_ids[$k]}" ];then
        bill_id_sql="select bill_id from v 
where effective_date <= sysdate and expire_date >= sysdate and user_id in (${user_ids[$k]});"
        wlog "select_sql:$yydb_bill_id_sql"
        bill_user_ids[$k]=`~/db bill "$bill_id_sql"`
        wlog "data:${bill_user_ids[$k]}"
    fi
done

for k in ${!bill_user_ids[@]}
do
    while read txt
    do
        [ -z "$txt" ] && continue
        wlog "检查号码:$txt"
        if [ 0${bill_id["x$txt"]} -ne 1 ];then
            r_cnt=`expr $r_cnt + 1`
            ret="${ret} ${bill_id}"
        fi
done << DATA
    ${bill_user_ids[$k]}
DATA
done

if [ $r_cnt -eq 0 ];then
    ret="OK"
else
    ret="具体号码为:${ret}"
fi

if [ ${#ret} -gt 300 ];then
    ret=`expr substr $ret 1 300`
    ret="${ret}...已截断"
fi   
v_date=`date +%Y%m%d%H%M%S`
[ "$DEBUG" = "false" ] && mv $tok dir
wlog "-----------------end------------"