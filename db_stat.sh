#!/usr/bin/ksh
if [ $# -ne 4 ];then
    echo "Usage:$0 db_name db_user db_pass db_ip"
    exit 1
fi

db_name=$1
db_user=$2
db_pass=$3
db_ip=$4

log=./log/db_stat_${db_name}_`date +%Y%m%d`.log
tmp_tnsping=${db_name}_${db_ip}_db_stat_tnsping.tmp
tmp_result=${db_name}_${db_ip}_db_stat_result.tmp
tok=${db_name}_${db_ip}_db_stat_`date +%Y%m%d%H%M%S`.tok
# д��־
wlog(){
    echo "`date +%Y-%m-%d' '%H:%M:%S`: $* ">>$log
}
 
###########################################################################
# �ɼ����� get_perf
get_perf(){
    listen_stat=$1
    timestamp=`date +%Y%m%d%H%M%S`
sqlplus ${db_user}/${db_pass}@${db_name}<<EOF
    set heading off feedback off newpage none  pagesize 0 echo off termout off  trimout on trims off
    set trimspool on 
    set linesize 800
    spool ${tmp_result}
    
    /* �����״̬*/
    select '${db_ip}*${db_name}_LE_DBS|db_lsnr_state|${listen_stat}|${timestamp}'
    From dual;
    
    /* ���ݿ�״̬ */
    select '${db_ip}*${db_name}_LE_DBS|FM-00-03-001-01|'||status||'|${timestamp}'
    From v\$instance;
               
    spool off
    quit
EOF
}
###########################################################################
# ��ʱɱ������
timeout() {
    waitsec=15
    ($*) & commandpid=$!
    (
        sleep $waitsec
        subpid=`ps -ef |grep -v grep|grep $commandpid |awk -vppid=$commandpid '{if($3 == ppid)print $2}'`
        kill -0 $commandpid && kill $commandpid
        [ -n "$subpid" ] && kill -0 $subpid >/dev/null 2>&1 && kill -9 $subpid >/dev/null 2>&1 
     ) & watchdog=$!
    if wait $commandpid ;then
        kill $watchdog > /dev/null 2>&1
        return 0
    fi
    return 1
}
###########################################################################
db_stat="OK"
wlog "======tnsping ${db_name} start======="
for i in 1 2 3
do
    tnsping ${db_name} > $tmp_tnsping
    cat $tmp_tnsping >> $log
    db_stat=`tail -1 $tmp_tnsping | awk '{if($1=="OK") {print $1} else {print $0}}'`
    if [ "$db_stat" = "OK" ] ; then
        wlog "${db_name}:�������ݿ⣬�ɼ��ļ�"
        timeout get_perf $db_stat
        if [ $? -eq 0 ];then
            wlog "�ɼ���������ִ��"
        else
            wlog "�ɼ����̳�ʱ����ǿ���˳�"
        fi
        grep "^${db_ip}" ${tmp_result} > $tok
        break;
    elif [ $i -eq 3 ];then
        wlog "��${i}��tnspingʧ��,����"
        break;
    else
        wlog "��${i}��tnspingʧ��,3����ٴγ���"
        sleep 3
    fi
done
wlog "------tnsping ${db_name} end-------"
wlog "tnsping stat : $db_stat"
is_success=0
## ����һ�βɼ��쳣ʱ��3�����ڶ��βɼ�
for i in 1 2 3
do
    if [ -s $tok ];then
        wlog "${db_name}����tok�ļ�����"
        cat $tok >> $log
        is_success=1
        break
    elif [ $i -eq 3 ];then
        wlog "��${i}�βɼ�����ֵʧ��,����"
        break
    else
        wlog "��${i}�βɼ�����ֵʧ��,3����ٴγ���"
        sleep 3
        timeout get_perf $db_stat
        if [ $? -eq 0 ];then
            wlog "�ɼ���������ִ��"
        else
            wlog "�ɼ����̳�ʱ����ǿ���˳�"
        fi
        grep "^${db_ip}" ${tmp_result} > $tok
    fi
done
# ���ս��
chk_time=`date +%Y%m%d%H%M%S`
if [ $is_success -eq 0 ];then
    wlog "${db_name}����tok�ļ��쳣"
    #�����״̬
    echo "${db_ip}*${db_name}_LE_DBS|db_lsnr_state|${db_stat}|${chk_time}" > $tok
    #���ݿ�״̬
    echo "${db_ip}*${db_name}_LE_DBS|FM-00-03-001-01|conn to database timeout|${chk_time}"  >> $tok
    cat $tok >> $log
fi

[ -e $tmp_tnsping ] && rm -rf $tmp_tnsping
[ -e $tmp_result ]  && rm -rf $tmp_result
wlog ">>>>>>>>> ${db_name} �ɼ����� <<<<<<<<<<"