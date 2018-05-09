#!/bin/bash

: ${AMP_PACKAGE_PATH:=/root/package}
: ${AMP_BAK_SUFFIX:="`date '+%Y%m%d'`.bak"}
. ${AMP_PACKAGE_PATH}/script/simple_log.sh

: ${MYSQL_INSTALL_PORT:=3306}
: ${MYSQL_INSTALL_USER:=mysql}
: ${MYSQL_INSTALL_DIR:=/usr/local}
: ${MYSQL_BASE_DIR:=${MYSQL_INSTALL_DIR}/mysql}
: ${MYSQL_DATA_BASE_DIR:=/data}
: ${MYSQL_DATA_DIR:=$MYSQL_DATA_BASE_DIR/mysql}
: ${MYSQL_DEFAULT_PASS:=123456}
: ${APP_DB_USER:=user}

G_METHOD=$1
shift
INSTALL_IP=$1

earseRpmMysql(){
    logBasic "删除系统自带 mysql"
    rpms=`rpm -qa | grep mysql |awk 'BEGIN{RS="\n";ORS=" "}{print}'`
    if [ -n "$rpms" ];then
        logInfo "删除系统自带 mysql:$rpms"
        rpm -e "$rpms" --nodeps
    fi
}

check_user(){
    logInfo "检查是否存在用户 ${MYSQL_INSTALL_USER} "
    if [ -z "`grep -w $MYSQL_INSTALL_USER /etc/passwd`" ];then
        logInfo "not exists $MYSQL_INSTALL_USER, add"
        useradd -s /sbin/nologin -M $MYSQL_INSTALL_USER
    fi
}

check_mysql(){
    logInfo "checking mysql..."
    if [ "`netstat -antlp | grep LISTEN |grep -w $MYSQL_INSTALL_PORT`" ];then
        logInfo "mysql runs on $MYSQL_INSTALL_PORT"
        return 0
    else
        return 1
    fi
}

timeout() {
    waitsec=30
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

checkPort() {
    while :
    do
        [ "`netstat -antlp | grep LISTEN |grep -w $1`" ] && break
        sleep 1
    done
}

init_mysql(){
    logInfo "install mysql"
    local pkg=`ls -1 $AMP_PACKAGE_PATH/tools | egrep '^mysql-.*(gz)$'`
    pkg_name=${pkg%-*}
    logInfo "backup /etc/my.cnf"
    if [ -f /etc/my.cnf ];then
        if [ ! -f /etc/my.cnf.$AMP_BAK_SUFFIX ];then
            cp -a /etc/my.cnf /etc/my.cnf.$AMP_BAK_SUFFIX
        fi
    fi
    logInfo "uncompress $pkg..."

    ls -1 $MYSQL_INSTALL_DIR | egrep '^mysql-.*' || tar -zxf $AMP_PACKAGE_PATH/tools/$pkg -C $MYSQL_INSTALL_DIR
    ln -s $MYSQL_INSTALL_DIR/${pkg_name}* $MYSQL_BASE_DIR
    [ ! -d $MYSQL_DATA_DIR ] && mkdir -p $MYSQL_DATA_DIR
    chown -R $MYSQL_INSTALL_USER.$MYSQL_INSTALL_USER $MYSQL_DATA_DIR $MYSQL_BASE_DIR $MYSQL_DATA_BASE_DIR
    chown -R $MYSQL_INSTALL_USER.$MYSQL_INSTALL_USER $MYSQL_INSTALL_DIR/${pkg_name}*
    cat > /etc/my.cnf <<EOF
[mysql]
port=$MYSQL_INSTALL_PORT
socket=/tmp/mysql.sock
default-character-set=utf8
[mysqld]
port=$MYSQL_INSTALL_PORT
character-set-server=utf8
socket=/tmp/mysql.sock
basedir=$MYSQL_BASE_DIR
datadir=${MYSQL_DATA_DIR}
lower_case_table_names=1
query_cache_size=0
transaction_isolation=READ-COMMITTED
tmp_table_size=96M
max_heap_table_size=96M
max_connections=1000
max_connect_errors=6000
long_query_time=1 
#***Innodbstorageengineparameters
innodb_buffer_pool_size=512M
innodb_flush_log_at_trx_commit=0
innodb_log_buffer_size=8M
innodb_log_file_size=128M
innodb_log_files_in_group=2
innodb_file_per_table=1
innodb_flush_method=O_DIRECT
innodb_file_format=Barracuda
innodb_write_io_threads=8
innodb_read_io_threads=4
innodb_doublewrite=0
innodb_purge_threads=1
innodb_stats_on_metadata=OFF
innodb_io_capacity=1000
log-bin-trust-function-creators=1
sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES,NO_AUTO_CREATE_USER
EOF
    [ ! -f /lib64/libaio.so.1 ] && cp $AMP_PACKAGE_PATH/tools/libaio.so.1 /lib64
    [ ! -f /usr/lib64/libnuma.so.1 ] && cp $AMP_PACKAGE_PATH/tools/libnuma.so.1 /usr/lib64
    init_cmd="$MYSQL_BASE_DIR/bin/mysqld --defaults-file=/etc/my.cnf --user=mysql \
        --datadir=$MYSQL_DATA_DIR --basedir=$MYSQL_BASE_DIR --initialize-insecure"
    logInfo "exec cmd [$init_cmd]"
    eval "$init_cmd"
    if [ $? -ne 0 ];then
        logError "init mysql failed "
        exit 1
    else
        logSuccess "init mysql [OK]"
    fi
}

add_service(){
    logInfo "add mysqld to chkconfig"
    cp $MYSQL_BASE_DIR/support-files/mysql.server /etc/init.d/mysqld
    perl -i -pe "
        s#^basedir=#basedir=$MYSQL_BASE_DIR#g;
        s#^datadir=#datadir=$MYSQL_DATA_DIR#g;
    " /etc/init.d/mysqld
    chmod 700 /etc/init.d/mysqld
    chkconfig --add mysqld
    chkconfig mysqld on
    if [ ! -f /etc/ld.so.conf.d/mysql-x86_64.conf ];then
        echo "$MYSQL_BASE_DIR/lib" > /etc/ld.so.conf.d/mysql-x86_64.conf
    fi
    ldconfig
}

mod_mysql(){
    logInfo "modify mysql password"
    /etc/init.d/mysqld start
    if [ $? -ne 0 ];then
        logError "start mysql error"
        exit 1
    fi
    timeout checkPort ${MYSQL_INSTALL_PORT}
    if [ -z "`grep $MYSQL_BASE_DIR /etc/profile`" ];then
        logInfo "add $MYSQL_BASE_DIR to /etc/profile"
        cp -a /etc/profile /etc/profile.$AMP_BAK_SUFFIX
        echo 'PATH=$PATH:'$MYSQL_BASE_DIR'/bin' >> /etc/profile
        echo 'LD_LIBRARY_PATH=$LD_LIBRARY_PATH:'$MYSQL_BASE_DIR'/lib' >> /etc/profile
        echo 'export PATH LD_LIBRARY_PATH' >> /etc/profile
    fi
    cmd="$MYSQL_BASE_DIR/bin/mysqladmin -S /tmp/mysql.sock -u root password '$MYSQL_DEFAULT_PASS'"
    logInfo "exec [$cmd]"
    eval "$cmd"
    if [ $? -ne 0 ];then
        logError "modify mysql password error"
        exit 1
    fi
    cat > /tmp/mysql_sec_script<<EOF
use mysql;
update mysql.user set host='%' where user='root';
grant all on *.* to "$APP_DB_USER"@'%' identified by "$MYSQL_DEFAULT_PASS";
flush privileges;
EOF
    logInfo "modify mysql listen host"
    cmd="$MYSQL_BASE_DIR/bin/mysql -uroot -p'$MYSQL_DEFAULT_PASS'  < /tmp/mysql_sec_script"
    logInfo "exec [$cmd]"
    eval "$cmd"
    if [ $? -ne 0 ];then
        logError "flush privileges error"
        exit 1
    fi
    logSuccess "installed mysql [successed]. mysql runs on $INSTALL_IP at $MYSQL_INSTALL_PORT. passwd: $MYSQL_DEFAULT_PASS"
}

uninstall(){
    logInfo "stop mysql process"
    filename=`basename $0`
    pids=`ps -ef|grep -v grep|grep -v $filename|grep ${MYSQL_INSTALL_USER}|grep 'mysql'|awk '{print $2}'`
    if [ -n "$pids" ];then
        logInfo "kill ${pids}"
        kill -9 $pids
    fi
    logInfo "unlink files and dirs"
    [ -f /etc/my.cnf.$AMP_BAK_SUFFIX ] && mv /etc/my.cnf.$AMP_BAK_SUFFIX /etc/my.cnf
    [ -f /etc/profile.$AMP_BAK_SUFFIX ] && mv /etc/profile.$AMP_BAK_SUFFIX /etc/profile
    [ -d $MYSQL_DATA_DIR ] && rm -rf $MYSQL_DATA_DIR
    logSuccess "delete mysql complete"
}


case $G_METHOD in
    install)
        check_mysql
        if [ $? -eq 0 ];then
            logWarn "mysql hasbeen installed on this host. please run $0 uninstall first"
            exit 1
        fi
        earseRpmMysql
        check_user 
        init_mysql
        add_service
        mod_mysql
        ;;
    uninstall)
        uninstall
        ;;
    *)
        logError "only support install|uninstall"
        ;;
esac
