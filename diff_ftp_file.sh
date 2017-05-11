#!/usr/bin/bash
#
###############################################################################
# 先检查主机能否ping通，后续扫描 /outgoing/BDC
# 主机能否ping通    172.16.6.178
# kpi:check_file_undo 文件是否积压
###############################################################################
# 实现方式：每15分钟登陆远程主机，执行 ls -1 将文件名保存至本地 curr_filename
# 维护文件: last_filename 记录上次出现的文件名
# 比较 curr_filename last_filename,同时出现的行写入 result_filename
# 解析 result_filename ， 重命名 mv curr_filename last_filename
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
# 日志文件，大于20M时压缩半数行
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
# 写日志
wlog() {
    echo "`date +%Y-%m-%d' '%H:%M:%S`: $*" >> $log
}

debug() {
    [ "$DEBUG" = "true" ] && echo "$*"
}
###############################################################################
# ping检查
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
# 文件名检查
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
# 超时控制
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
wlog "开始采集"
wlog "检查ping状态..."
check_ping 172.16.6.178
ping_stat=$?
ping_val=OK
if [ $ping_stat -eq 0 ];then
    wlog "ping成功，登陆服务器查询文件..." 
    timeout get_filename 172.16.6.178 username password 1160 > curr_filename.txt
    ftp_stat=$?
    if [ $ftp_stat -eq 0 ];then
        wlog "成功获取文件名"
        cat curr_filename.txt >> $log
        [ ! -e last_filename.txt ] && touch last_filename.txt
        # 比较curr_filename last_filename,同时出现的行写入 result_filename
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
        wlog "ftp连接端口1160超时"
        ping_val="ftp连接端口1160超时，请检查"
    fi
else
    wlog "无法ping通目标主机"
    ping_val="无法ping通目标主机"
fi
wlog "$htn*ping_${ip}|checkJFping|$ping_val|$v_date"
echo "$htn*ping_${ip}|checkJFping|$ping_val|$v_date" >> $tok
wlog "移动文件到指定目录"
[ "$DEBUG" = "false" ] && mv $tok $HOME/perfsrcfils/
wlog "采集结束"