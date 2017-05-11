#!/usr/bin/bash

#1.A ���ݿ�ͳ������
#
#begin_date  ���ڵ��ڱ���1��0��0��0��
#end_date    С�ڵ�������1��0��0��0��
#update_time ��ȡǰ8λ���ڵ�����������
#��ȡ��id���û�ID����gb������GBֵ����update_time�����ʹ��ʱ�䣩
#2.ʹ�ò���1�е�idȥ B �� v��ͼ���ҵ�bill_id
#select bill_id from v
#where effective_date <= sysdate and expire_date >= sysdate and user_id in (����1�е�aimdb_owner_id);
#3.COMMONDB ��ȡbill_id�û�����
#select bill_id from t where effective_date <= sysdate and expire_date >= sysdate;
#����в���2�е�bill_id���ڲ���3��bill_id�У���ô��澯
#�澯�������ݣ�
#2���澯��ÿ��9��30������һ�Σ�ÿ��1�Ų�����
# I must get water on the brain with bash

DEBUG="false"
if [ $DEBUG = "true" ];then
    orig_dir="."
else
    cd
    . ./.profile
    orig_dir="${HOME}/"
fi

# ��־�ļ�������20Mʱѹ��������
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
# д��־
wlog() {
    echo "`date +%Y-%m-%d' '%H:%M:%S`: $*">>$log
}

wlog "===============start==============="
dd=`date +%d`
if [ $dd -eq 1 ];then
    wlog "1�Ų�����"
    wlog "-----------------end------------"
    exit 0
fi
# �������鶨��
user_ids=""
yydb_user_ids=""
# hash���鶨��
declare -A bill_id
# �������
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
    # oracle in �﷨���� 1000 ��ʱ�ᱨ��
    # ���� 500 ����
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
        wlog "������:$txt"
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
    ret="�������Ϊ:${ret}"
fi

if [ ${#ret} -gt 300 ];then
    ret=`expr substr $ret 1 300`
    ret="${ret}...�ѽض�"
fi   
v_date=`date +%Y%m%d%H%M%S`
[ "$DEBUG" = "false" ] && mv $tok dir
wlog "-----------------end------------"