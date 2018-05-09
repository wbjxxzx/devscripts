#!/bin/bash

: ${AMP_PACKAGE_PATH:=/root/package}
: ${AMP_INSTALL_USER:=zhangsan}
: ${AMP_INSTALL_PATH:=/home/${AMP_INSTALL_USER}}

. ${AMP_PACKAGE_PATH}/script/simple_log.sh

: ${ZK_PORT:=2181}
: ${ZK_MEM:='512M'}
: ${KAFKA_PORT:=9092}

iface=`netstat -rn|awk '{if($4~/UG/) print $NF}'`
AMP_LOCAL_IP=`ifconfig $iface|grep -w "inet"|awk '{print $2}'|cut -d ":" -f2`

# 接收 broker_id ips
G_METHOD=$1
shift
BROKER_ID=${1:-1}
shift

declare -A HOSTNAMES

if [ $# -eq 0 ];then
    :
elif [ $# -le 2 ];then
    BROKER_IPS=$1
    HOSTNAMES[$1]=$2
else 
    BROKER_IPS=`echo "$*" | awk '{print $1,$2,$3}'` 
    HOSTNAMES[$1]=$4
    HOSTNAMES[$2]=$5
    HOSTNAMES[$3]=$6
fi

AMP_LOCAL_IP=`echo $BROKER_IPS | awk -vidx=$BROKER_ID '{print $idx}'`

ZK_STR=""
for broker_ip in ${BROKER_IPS[@]}
do
    ZK_STR="${ZK_STR}${broker_ip}:${ZK_PORT}"
    ZK_STR="${ZK_STR},"
done
ZK_STR=${ZK_STR%%,}

##
# if user: ampmon exists
checkUser(){
    logInfo "检查是否存在用户 ${AMP_INSTALL_USER} "
    if [ -z "`grep -w $AMP_INSTALL_USER /etc/passwd`" ];then
        logInfo "not exists $AMP_INSTALL_USER, add"
        useradd -m $AMP_INSTALL_USER
        echo 'shsnc!@#' | passwd --stdin "$AMP_INSTALL_USER" 
    fi
}

installJDK(){
    logInfo "检查用户 ${AMP_INSTALL_USER} 是否已安装 jdk"
    su - $AMP_INSTALL_USER -c 'java -version' 2>/dev/null
    if [ $? -eq 0 ];then 
        logInfo "检测到 jdk, 跳过此步骤"
        return 0
    fi
    logInfo "安装 jdk"
    local tarfile=`ls -1 $AMP_PACKAGE_PATH/tools | egrep '^jdk-.*(gz)$'`
    filename=`tar -ztf $AMP_PACKAGE_PATH/tools/$tarfile | head -1`
    tar -zxf $AMP_PACKAGE_PATH/tools/$tarfile -C $AMP_INSTALL_PATH/
    ln -s $AMP_INSTALL_PATH/$filename $AMP_INSTALL_PATH/jdk
    chown -R $AMP_INSTALL_USER:$AMP_INSTALL_USER $AMP_INSTALL_PATH/jdk
    chown -R $AMP_INSTALL_USER:$AMP_INSTALL_USER $AMP_INSTALL_PATH/$filename
    echo "export JAVA_HOME=${AMP_INSTALL_PATH}/jdk" >> $AMP_INSTALL_PATH/.bash_profile
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> $AMP_INSTALL_PATH/.bash_profile
    echo 'export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar' >> $AMP_INSTALL_PATH/.bash_profile
    chown $AMP_INSTALL_USER.$AMP_INSTALL_USER $AMP_INSTALL_PATH/.bash_profile
    logSuccess "install JDK success"
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

installRedis(){
    logInfo "检查用户 ${AMP_INSTALL_USER} 是否已安装 redis"
    if [ -n "`netstat -antlp | grep LISTEN |grep -w 6379`" ];then 
        logInfo "检测到 redis, 跳过此步骤"
        return 0
    fi
    logInfo "安装 redis"
    tar -zxf $AMP_PACKAGE_PATH/tools/redis.tar.gz -C $AMP_INSTALL_PATH/
    perl -i.$AMP_BAK_SUFFIX -pe "
        s#^\\s*bind\\s+.*#bind ${AMP_LOCAL_IP}#;
        s#^\\s*pidfile\\s+.*#pidfile $AMP_INSTALL_PATH/redis/redis-6379.pid#;
        s#^\\s*logfile\\s+.*#logfile $AMP_INSTALL_PATH/redis/logs/redis-6379.log#;
    " $AMP_INSTALL_PATH/redis/conf/redis-6379.conf
    [ $? -ne 0 ] && logWarn "修改 $AMP_INSTALL_PATH/redis/conf 文件[Failed], 请手动尝试"
    chown -R $AMP_INSTALL_USER:$AMP_INSTALL_USER $AMP_INSTALL_PATH/redis
    chmod +x $AMP_INSTALL_PATH/redis/bin/*
    su - $AMP_INSTALL_USER -c "$AMP_INSTALL_PATH/redis/bin/run.sh"
    timeout checkPort 6379 > /dev/null 2>&1
    [ $? -eq 0 ] && logSuccess "start redis success" || logWarn "start redis failed"
}

addHostsCfg(){
    logInfo "检查是否已添加主机名到 /etc/hosts"
    if [ -f /etc/hosts.$AMP_BAK_SUFFIX ];then
        logInfo "/etc/hosts has been modified. nothing to do"
    else
        cp -a /etc/hosts /etc/hosts.$AMP_BAK_SUFFIX
        for ip in ${!HOSTNAMES[@]}
        do
            if [ -z "`egrep \"^$ip\" /etc/hosts`" ];then
                logInfo "添加 $ip ${HOSTNAMES[$ip]} 到 /etc/hosts"
                echo "$ip  ${HOSTNAMES[$ip]}" >> /etc/hosts
            fi
        done
    fi
}

installZookeeper(){
    logInfo "检查用户 ${AMP_INSTALL_USER} 是否已安装 zookeeper"
    if [ -n "`ps -ef | grep java | grep -v grep | grep zookeeper`" ];then 
        logInfo "检测到 zookeeper, 跳过此步骤"
        return 0
    fi
    logInfo "安装 zookeeper"
    tar -zxf $AMP_PACKAGE_PATH/tools/zookeeper-3.4.9.tar.gz -C $AMP_INSTALL_PATH/
    cp $AMP_INSTALL_PATH/zookeeper-3.4.9/conf/zoo_sample.cfg $AMP_INSTALL_PATH/zookeeper-3.4.9/conf/zoo.cfg
    mkdir -p $AMP_INSTALL_PATH/zookeeper-3.4.9/logs
    mkdir -p $AMP_INSTALL_PATH/zookeeper/logs
    mkdir -p $AMP_INSTALL_PATH/zookeeper/data
    perl -i.$AMP_BAK_SUFFIX -pe "
        s#dataDir=.*#dataDir=$AMP_INSTALL_PATH/zookeeper/data#;
    " $AMP_INSTALL_PATH/zookeeper-3.4.9/conf/zoo.cfg
    echo "dataLogDir=$AMP_INSTALL_PATH/zookeeper/logs" >> $AMP_INSTALL_PATH/zookeeper-3.4.9/conf/zoo.cfg
    echo "maxClientCnxns=3000" >> $AMP_INSTALL_PATH/zookeeper-3.4.9/conf/zoo.cfg
    local i=1
    for broker_ip in ${BROKER_IPS[@]}
    do
        echo "server.${i}=${broker_ip}:2888:3888" >> $AMP_INSTALL_PATH/zookeeper-3.4.9/conf/zoo.cfg
        let i++
    done
    echo "$BROKER_ID" > $AMP_INSTALL_PATH/zookeeper/data/myid
    perl -i.$AMP_BAK_SUFFIX -pe "
        BEGIN{\$flag=1;}
        if(! /^#|^\\s.*$/ and \$flag){
            print qq{SERVER_JVMFLAGS=\"-server -Xms${ZK_MEM} -Xmx${ZK_MEM} -XX:+UseG1GC\"\n};
            print qq{ZOO_LOG_DIR=\"\\\$ZOOBINDIR/../logs/\"\n};
            print qq{ZOO_LOG4J_PROP=\"INFO,ROLLINGFILE\"\n};
            \$flag=0;
        }
    " $AMP_INSTALL_PATH/zookeeper-3.4.9/bin/zkEnv.sh

    perl -i.$AMP_BAK_SUFFIX -pe '
        s/(log4j.appender.ROLLINGFILE.MaxFileSize)=10MB/$1=100MB/;
        s/^#(log4j.appender.ROLLINGFILE.MaxBackupIndex=10)/$1/;
    ' $AMP_INSTALL_PATH/zookeeper-3.4.9/conf/log4j.properties

    chown -R $AMP_INSTALL_USER:$AMP_INSTALL_USER $AMP_INSTALL_PATH/zookeeper
    chown -R $AMP_INSTALL_USER:$AMP_INSTALL_USER $AMP_INSTALL_PATH/zookeeper-3.4.9
    chmod +x $AMP_INSTALL_PATH/zookeeper-3.4.9/bin/*
    if [ -z "`grep zkCleanup /var/spool/cron/$AMP_INSTALL_USER`" ];then
        echo "20 4 * * * $AMP_INSTALL_PATH/zookeeper-3.4.9/bin/zkCleanup.sh -n 15" >> /var/spool/cron/$AMP_INSTALL_USER
        chown $AMP_INSTALL_USER.$AMP_INSTALL_USER /var/spool/cron/$AMP_INSTALL_USER
    fi
    su - $AMP_INSTALL_USER -c "$AMP_INSTALL_PATH/zookeeper-3.4.9/bin/zkServer.sh start"
    timeout checkPort ${ZK_PORT} > /dev/null 2>&1
    [ $? -eq 0 ] && logSuccess "start zookeeper success" || logWarn "start zookeeper failed"
}

installKafka(){
    logInfo "检查用户 ${AMP_INSTALL_USER} 是否已安装 kafka"
    if [ -n "`ps -ef | grep java | grep -v grep | grep kafka`" ];then 
        logInfo "检测到 kafka, 跳过此步骤"
        return 0
    fi
    logInfo "安装 kafka"
    tar -zxf $AMP_PACKAGE_PATH/tools/kafka_2.11-0.10.1.0.tgz -C $AMP_INSTALL_PATH/
    mkdir -p $AMP_INSTALL_PATH/kafka

    perl -i.$AMP_BAK_SUFFIX -pe "
        s/broker.id=0/broker.id=${BROKER_ID}/;
        s/^#(delete.topic.enable=true)/\$1/;
        s/^#(listeners=PLAINTEXT:\/\/)(?::9092)/\${1}${AMP_LOCAL_IP}:${KAFKA_PORT}/;
        s#(log.dirs=)/tmp/kafka-logs#\${1}${AMP_INSTALL_PATH}/kafka/kafka-logs#;
        s/num.partitions=1/num.partitions=10/;
        s/zookeeper.connect=localhost:${ZK_PORT}/zookeeper.connect=${ZK_STR}/;
    " $AMP_INSTALL_PATH/kafka_2.11-0.10.1.0/config/server.properties

    perl -i.$AMP_BAK_SUFFIX -pe "
        s/KAFKA_HEAP_OPTS=\"-Xmx1G -Xms1G\"/KAFKA_HEAP_OPTS=\"-Xmx${ZK_MEM} -Xms${ZK_MEM} -XX:MetaspaceSize=96m\"/;
    " $AMP_INSTALL_PATH/kafka_2.11-0.10.1.0/bin/kafka-server-start.sh
    if [ -z "`grep kafka /var/spool/cron/$AMP_INSTALL_USER`" ];then
        echo "0 2 1,15 * * find  $AMP_INSTALL_PATH/kafka_2.11-0.10.1.0/logs -type f -mtime +7|xargs rm -f" >> /var/spool/cron/$AMP_INSTALL_USER
        chown $AMP_INSTALL_USER.$AMP_INSTALL_USER /var/spool/cron/$AMP_INSTALL_USER
    fi
    chown -R $AMP_INSTALL_USER:$AMP_INSTALL_USER $AMP_INSTALL_PATH/kafka
    chown -R $AMP_INSTALL_USER:$AMP_INSTALL_USER $AMP_INSTALL_PATH/kafka_2.11-0.10.1.0
    chmod +x $AMP_INSTALL_PATH/kafka_2.11-0.10.1.0/bin/*
    logSuccess "install kafka complete"
}

runKafka(){
    logInfo "启动kafka..."
    su - $AMP_INSTALL_USER -c "$AMP_INSTALL_PATH/kafka_2.11-0.10.1.0/bin/kafka-server-start.sh -daemon $AMP_INSTALL_PATH/kafka_2.11-0.10.1.0/config/server.properties"
    timeout checkPort ${KAFKA_PORT} > /dev/null 2>&1
    [ $? -eq 0 ] && logSuccess "start kafka success" || logWarn "start kafka failed"
}


uninstall(){
    logInfo "uninstal redis zookeeper kafka"
    filename=`basename $0`
    pids=`ps -ef|grep -v grep|grep -v $filename|grep ${AMP_INSTALL_USER}|egrep 'redis|zookeeper|kafka'|awk '{print $2}'`
    logInfo "kill ${pids}"
    kill -9 $pids
    [ -f /etc/hosts.$AMP_BAK_SUFFIX ] && mv -f /etc/hosts.$AMP_BAK_SUFFIX /etc/hosts
    [ -d ${AMP_INSTALL_PATH}/redis ] && rm -rf ${AMP_INSTALL_PATH}/redis
    [ -d ${AMP_INSTALL_PATH}/zookeeper ] && rm -rf ${AMP_INSTALL_PATH}/zookeeper*
    [ -d ${AMP_INSTALL_PATH}/kafka ] && rm -rf ${AMP_INSTALL_PATH}/kafka*
    logSuccess "delete redis zookeeper kafka complete"
}

case $G_METHOD in
    install)
        checkUser
        installJDK
        [ $BROKER_ID -eq 1 ] && installRedis
        addHostsCfg
        installZookeeper
        installKafka
        ;;
    uninstall)
        uninstall
        ;;
    runkafka)
        runKafka
        ;;
    *)
        logError "only support install|uninstall|runkafka"
        ;;
esac
