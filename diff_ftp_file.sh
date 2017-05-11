#!/usr/bin/bash
#
###############################################################################
# �ȼ�������ܷ�pingͨ������ɨ�� /outgoing/BDC
# �����ܷ�pingͨ    172.16.6.178
# kpi:check_file_undo �ļ��Ƿ��ѹ
###############################################################################
# ʵ�ַ�ʽ��ÿ15���ӵ�½Զ��������ִ�� ls -1 ���ļ������������� curr_filename
# ά���ļ�: last_filename ��¼�ϴγ��ֵ��ļ���
# �Ƚ� curr_filename last_filename,ͬʱ���ֵ���д�� result_filename
# ���� result_filename �� ������ mv curr_filename last_filename
DEBUG="false"
if [ $DEBUG = "true" ];then
    orig_dir="."
else
    cd
    . ./.profile
    orig_dir="${HOME}/scrcoldispoy/checklog/DEM_BOMC_AA_20151228_165722480"
fi
v_date=`date +%Y%m%d%H%M%S`
tok=DEM_BOMC_AA_20151228_165722480.tok
htn=`hostname`
###############################################################################
# ��־�ļ�������20Mʱѹ��������
cd $orig_dir
log="$orig_dir/alpha.log"
if [ -f $log ];then
    log_size=`ls -l $log | awk '{printf("%d",$5)}'`
    if [ -n "$log_size" -a $log_size -gt 20971520 ];then
        half_line=`awk 'END{printf("%d",NR/2)}' $log`
        perl -ni -e "print if(\$.>$half_line)" $log
    fi
fi
###############################################################################
# д��־
wlog() {
    echo "`date +%Y-%m-%d' '%H:%M:%S`: $*" >> $log
}

debug() {
    [ "$DEBUG" = "true" ] && echo "$*"
}
###############################################################################
# ping���
check_ping() {
    ip=$1
    for i in 1 2 3
    do
        ping -s $1 1 3 > /dev/null 2>&1
        if [ $? -eq 0 ];then
            return 0
        else
            sleep 1
            continue
        fi
    done
    return 1
}
###############################################################################
# �ļ������
get_filename(){
    ip=$1
    user=$2
    password=$3
    port=$4
    port=${port:=21}
ftp -i -n $ip $port << EOF
user $user $password
cd /outgoing/BDC
ls -1
EOF
}
###############################################################################
# ��ʱ����
timeout() {
    waitsec=15
    ($*) & commandpid=$!
    (
        sleep $waitsec
        export COMMANDPID=$commandpid
        subpid=`ps -ef |grep -v grep|grep $commandpid | perl -F -ane 'print $F[1] if $F[2]==$ENV{COMMANDPID}'`
        debug "commandpid:$commandpid"
        debug "subpid:$subpid"
        kill -0 $commandpid && kill $commandpid
        [ -n "$subpid" ] && kill -0 $subpid >/dev/null 2>&1 && kill -9 $subpid >/dev/null 2>&1 
     ) & watchdog=$!
        debug "watchdog:$watchdog"
    if wait $commandpid ;then
        debug "success execute subroutine"
        kill $watchdog > /dev/null 2>&1
        return 0
    fi
    debug "subroutine timeout, force exit"
    return 1
}
###############################################################################
wlog "-------------------------------------------------------------"
wlog "��ʼ�ɼ�"
wlog "���ping״̬..."
check_ping 172.16.6.178
ping_stat=$?
ping_val=OK
if [ $ping_stat -eq 0 ];then
    wlog "ping�ɹ�����½��������ѯ�ļ�..." 
    timeout get_filename 172.16.6.178 username password 1160 > curr_filename.txt
    ftp_stat=$?
    if [ $ftp_stat -eq 0 ];then
        wlog "�ɹ���ȡ�ļ���"
        cat curr_filename.txt >> $log
        [ ! -e last_filename.txt ] && touch last_filename.txt
        # �Ƚ�curr_filename last_filename,ͬʱ���ֵ���д�� result_filename
        #awk 'NR==FNR{if($0 !~ /^[ \t]*$/)arr[$0]+=1;next}{if($0 in arr || $0 ~ /^[ \t]*$/)print;}' last_filename.txt curr_filename.txt > result_filename.txt
        perl -ne '$h{$_}++;END{print grep{$h{$_}>1}keys %h}' last_filename.txt curr_filename.txt > result_filename.txt
        mv curr_filename.txt last_filename.txt
        grep -v '^[ \t]+$' filename.cfg | grep -v '^#' | while read res filename
        do
            express=${filename##*/}
            express=${express//\*/}
            wlog "express:$express"
            val=`grep "$express" result_filename.txt | awk '{print $1}'`
            if [ -z "$val" ];then
                val=OK
            fi
            wlog "$htn*$res[$filename]|check_file_undo|$val|$v_date"
            echo "$htn*$res[$filename]|check_file_undo|$val|$v_date" >> $tok
        done
    else
        wlog "ftp���Ӷ˿�1160��ʱ"
        ping_val="ftp���Ӷ˿�1160��ʱ������"
    fi
else
    wlog "�޷�pingͨĿ������"
    ping_val="�޷�pingͨĿ������"
fi
wlog "$htn*ping_${ip}|checkJFping|$ping_val|$v_date"
echo "$htn*ping_${ip}|checkJFping|$ping_val|$v_date" >> $tok
wlog "�ƶ��ļ���ָ��Ŀ¼"
[ "$DEBUG" = "false" ] && mv $tok $HOME/perfsrcfils/
wlog "�ɼ�����"