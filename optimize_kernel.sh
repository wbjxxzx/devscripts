#!/bin/bash

: ${AMP_PACKAGE_PATH:=/root/package}
: ${REDHAT_VER:=6}
: ${AMP_BAK_SUFFIX:="`date '+%Y%m%d'`.bak"}
. ${AMP_PACKAGE_PATH}/script/simple_log.sh

REDHAT_VER=`cat /etc/redhat-release |sed -re 's/[^0-9]*([0-9]*).*$/\1/;' | awk '{printf("%d",$0)}'`

##
# 关闭 selinux /etc/selinux/config
set_selinux_off(){
    logInfo "检测 selinux /etc/selinux/config"
    setenforce 0
    if [ -z "`grep '^SELINUX=disabled' /etc/selinux/config`" ];then
        perl -i.$AMP_BAK_SUFFIX -pe 's/^[ \t]*SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config
        [ $? -ne 0 ] && logWarn "修改 /etc/selinux/config 文件[Failed], 请手动尝试"
    else
        logInfo "无需修改 /etc/selinux/config"
    fi
}

##
# 修改文件打开数 /etc/security/limits.conf /etc/security/limits.d/90-noproc.conf
mod_limits(){
    logInfo "检测文件打开数 /etc/security/limits.conf"
    if [ $REDHAT_VER -lt 7 ];then
        if [ -z "`grep 'soft nproc 1024000' /etc/security/limits.d/90-nproc.conf`" ];then
            perl -i.$AMP_BAK_SUFFIX -pe 's/^\*\s+soft\s+nproc.*/\* soft nproc 1024000/' /etc/security/limits.d/90-nproc.conf
            [ $? -ne 0 ] && logWarn "修改/etc/security/limits.d/90-nproc.conf[Failed], 请手动尝试"
        fi
        if [ -f /etc/security/limits.d/90-nofile.conf ];then
            if [ -z "`grep 'soft nofile 1024000' /etc/security/limits.d/90-nofile.conf`" ];then
                perl -i.$AMP_BAK_SUFFIX -pe '
                    s/^\*\s+soft\s+nofile.*/\* soft nofile 1024000/;
                    s/^\*\s+hard\s+nofile.*/\* hard nofile 1024000/;
                    ' /etc/security/limits.d/90-nofile.conf
            fi
        else
            echo "* soft nofile 1024000" >> /etc/security/limits.d/90-nofile.conf
            echo "* hard nofile 1024000" >> /etc/security/limits.d/90-nofile.conf
        fi
    else
        if [ -z "`grep 'soft nproc 1024000' /etc/security/limits.d/20-nproc.conf`" ];then
            perl -i.$AMP_BAK_SUFFIX -pe 's/^\*\s+soft\s+nproc.*/\* soft nproc 1024000/' /etc/security/limits.d/20-nproc.conf
            [ $? -ne 0 ] && logWarn "修改/etc/security/limits.d/20-nproc.conf[Failed], 请手动尝试"
        fi
    fi
    if [ -f /etc/security/limits.conf.$AMP_BAK_SUFFIX ];then
        logInfo "/etc/security/limits.conf has been modified. nothing to do"
    else
        sed -i.$AMP_BAK_SUFFIX -r '/^\*\s*(soft|hard)\s+(nproc|nofile)/d' /etc/security/limits.conf
        [ $? -ne 0 ] && logWarn "修改/etc/security/limits.conf[Failed], 请手动尝试"
        echo "* soft nproc 65535" >> /etc/security/limits.conf
        echo "* hard nproc 65535" >> /etc/security/limits.conf
        echo "* soft nofile 65535" >> /etc/security/limits.conf
        echo "* soft nofile 65535" >> /etc/security/limits.conf
    fi
}
##
# 关闭防火墙
set_firewall_off(){
    logInfo "检测防火墙"
    if [ $REDHAT_VER -lt 7 ];then
        chkconfig iptables off && service iptables stop > /dev/null 2>&1
        [ $? -ne 0 ] && logWarn "关闭防火墙[Failed], 请手动尝试"
    else
        systemctl disable firewalld.service && systemctl stop firewalld.service > /dev/null 2>&1
        [ $? -ne 0 ] && logWarn "关闭防火墙[Failed], 请手动尝试"
    fi
}

set_selinux_off
set_firewall_off
mod_limits