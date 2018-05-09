#!/bin/bash

: ${AMP_PACKAGE_PATH:=/root/package}

SIMPLE_LOG_ERROR_LEVEL=5
SIMPLE_LOG_WARN_LEVEL=4
SIMPLE_LOG_INFO_LEVEL=3
SIMPLE_LOG_DEBUG_LEVEL=2
SIMPLE_LOG_BASIC_LEVEL=1

SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

logSuccess() {
    $SETCOLOR_SUCCESS
    wlog "[SUCCESS] $*"
    $SETCOLOR_NORMAL    
    return 0
}

logFailure() {
    $SETCOLOR_FAILURE
    wlog "[FAILED] $*"
    $SETCOLOR_NORMAL
    return 1
}

logPassed() {
    echo -n "["
    $SETCOLOR_WARNING
    wlog "[PASSED] $*"
    $SETCOLOR_NORMAL
    return 1
}

logWarning() {
    $SETCOLOR_WARNING
    wlog "[WARNING] $*"
    $SETCOLOR_NORMAL
    return 1
}

: ${LOGLEVEL:=$SIMPLE_LOG_INFO_LEVEL}
SIMPLE_LOG_LOGFILE=$AMP_PACKAGE_PATH/install_amp.log

wlog() {
    echo "`date '+%Y-%m-%d %H:%M:%S'` $*" | tee -a $SIMPLE_LOG_LOGFILE
}

isEnabled(){
    level=$1
    [ $level -ge $LOGLEVEL ] && return 0 || return 1
}

logError() {
    isEnabled $SIMPLE_LOG_ERROR_LEVEL && logFailure "[ERROR] $*"
}

logWarn(){
    isEnabled $SIMPLE_LOG_WARN_LEVEL && logWarning "$*"
}

logInfo(){
    isEnabled $SIMPLE_LOG_INFO_LEVEL && wlog "[INFO] $*"
}

logDebug(){
    isEnabled $SIMPLE_LOG_DEBUG_LEVEL && wlog "[DEBUG] $*"
}

logBasic(){
    isEnabled $SIMPLE_LOG_BASIC_LEVEL && wlog "[BASIC] $*"
}

