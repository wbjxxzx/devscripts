
/*
    运行流水线前设置一些环境变量,
    该环境变量不能出现在 jenkinsfile 的 environment 中
    加前缀 LIB_ENV 以做区分
*/

def call() {
    env['LIB_ENV_PEPELINE_ID'] = UUID.randomUUID().toString()

    // 由 GenericTrigger 触发的流水线, currentBuild.description 为 null 
    if (!currentBuild.description){
        currentBuild.description = "Trigger by ${triggerUserAlphaName} [${triggerBranch}]"
    }
    def t = new Date(currentBuild.startTimeInMillis)
    env['LIB_ENV_START_TIME'] = t.format('yyyy-MM-dd HH:mm:ss')
    env['LIB_ENV_START_TIMESTAMP'] = currentBuild.startTimeInMillis / 1000

    println("in prePipeline")
    println("LIB_ENV_PEPELINE_ID: ${LIB_ENV_PEPELINE_ID}")
    println("LIB_ENV_START_TIME: ${LIB_ENV_START_TIME}")
    println("LIB_ENV_START_TIMESTAMP: ${LIB_ENV_START_TIMESTAMP}")
}
