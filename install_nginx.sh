#!/bin/bash

: ${AMP_PACKAGE_PATH:=/root/package}
: ${AMP_INSTALL_USER:=zhangsan}
: ${AMP_INSTALL_PATH:=/home/${AMP_INSTALL_USER}}
: ${AMP_BAK_SUFFIX:="`date '+%Y%m%d'`.bak"}

. ${AMP_PACKAGE_PATH}/script/simple_log.sh
: ${NGINX_LOG_DIR:=/var/log/nginx}
: ${NGINX_HOME:=${AMP_INSTALL_PATH}}
: ${NGINX_CONF:=/etc/nginx/conf.d}
: ${NGINX_USER:=$AMP_INSTALL_USER}
: ${NGINX_PORT:=80}

G_METHOD=$1
shift

mod_conf(){
    logInfo "ready to modify nginx"
    tar -zxf $AMP_PACKAGE_PATH/tools/nginx.tar.gz -C $NGINX_HOME > /dev/null 2>&1
    tar -zxf $AMP_PACKAGE_PATH/tools/nginx_conf.tar.gz -C / > /dev/null 2>&1
    sed -i 's#/usr/local#'$NGINX_HOME'#g' /etc/init.d/nginx
    sed -i 's/shsnc/'$NGINX_USER'/' /etc/nginx/nginx.conf
    sed -i 's#/usr/local#'$NGINX_HOME'#g' /etc/nginx/nginx.conf
    sed -i 's#/usr/local#'$NGINX_HOME'#g' /etc/nginx/conf.d/user.conf
    perl -i.$AMP_BAK_SUFFIX -pe "
        s/(listen\\s+)80/\${1}$NGINX_PORT/;
    " /etc/nginx/conf.d/user.conf
    sed -i 's#^\([ \t]*root[ \t]\+\).*#\1'$AMP_TOPO';#g' /etc/nginx/conf.d/topo_sftp.conf
    chown -R ${NGINX_USER}.$NGINX_USER $NGINX_HOME/nginx $NGINX_LOG_DIR
}

install(){
    logInfo "ready to install nginx"
    [ ! -d $NGINX_LOG_DIR ] && mkdir -p $NGINX_LOG_DIR
    [ ! -f /lib64/libpcre.so.0 ] && cp ${AMP_PACKAGE_PATH}/tools/libpcre.so.0.0.1 /lib64 && ldconfig
    chmod +x $NGINX_HOME/nginx/sbin/nginx
    $NGINX_HOME/nginx/sbin/nginx -c /etc/nginx/nginx.conf
    sleep 1
    if [ ! "`netstat -antlp|grep LISTEN|grep -w $NGINX_PORT`" ];then
        logError "Error,nginx start failed."
    else
        logSuccess "install nginx success."
        echo "$NGINX_HOME/nginx/sbin/nginx -c /etc/nginx/nginx.conf" >> /etc/rc.local
    fi
}

uninstall(){
    logInfo "uninstal nginx"
    filename=`basename $0`
    pids=`ps -ef|grep -v grep|grep -v $filename|grep 'nginx'|awk '{print $2}'`
    if [ -n "$pids" ];then
        logInfo "kill ${pids}"
        kill -9 $pids
    fi
    logInfo "unlink files and dirs"
    [ -d $NGINX_HOME/nginx ] && rm -rf $NGINX_HOME/nginx
    sed -i "s#$NGINX_HOME/nginx/sbin/nginx#PREPARE_TO_DELETE#" /etc/rc.local
    sed -i "/PREPARE_TO_DELETE/d" /etc/rc.local
    logSuccess "delete nginx complete"
}

case $G_METHOD in
    install)
        mod_conf
        install
        ;;
    uninstall)
        uninstall
        ;;
    *)
        logError "only support install|uninstall"
        ;;
esac