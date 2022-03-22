
/*
 * 流水线运行过程中的一些方法
 */

import groovy.json.JsonSlurperClassic
import groovy.json.JsonOutput
import org.devops.serializers.PipelineTaskInfo

def call() {
    

}

Boolean isBranchCreateOrDelete(String beforeSha, String afterSha, int commitsCount){
    // 删除分支会触发 push 事件， 此时的 afterSha 为全 0
    // 在 gitlab 页面创建分支时，触发 push 事件，此时的 beforeSha 为全 0
    // 首次提交分支时，beforeSha 为全 0
    return commitsCount == 0 || afterSha == "0000000000000000000000000000000000000000"
}

/*
 * 通过 commitSha 获取变更的文件列表
 */
def getCurChangeFiles(String projectId, String commitSha){
    def resp = httpRequest acceptType: 'APPLICATION_JSON_UTF8', 
                    contentType: 'APPLICATION_JSON_UTF8', 
                    customHeaders: [[maskValue: true, name: 'PRIVATE-TOKEN', value: 'xxx']], 
                    timeout: 30, 
                    url: "https://gitlab.xxx.com/api/v4/projects/${projectId}/repository/commits/${commitSha}/diff/"

    def diffs = new JsonSlurperClassic().parseText("${resp.content}")
    def filenameMap = [:]
    diffs.each { item ->
        filenameMap.put(item.new_path, 1)
    }
    return filenameMap.keySet()
}

/*
 * 提交流水线运行结果
 */
def sendJobResult(PipelineTaskInfo info, String baseUrl){
    def reqBody = [:]
    def name = "${env.JOB_NAME}_" + info.get('username') + "_" + info.get('branchType')
    reqBody.put('name', name)
    reqBody.put('branch_type', info.get('branchType'))
    reqBody.put('category', info.get('category'))
    reqBody.put('start_timestamp', currentBuild.startTimeInMillis / 1000)
    reqBody.put('ci_server', "${env.JENKINS_URL}")
    reqBody.put('job_name', "${env.JOB_NAME}")
    reqBody.put('build_id', env.BUILD_NUMBER)
    reqBody.put('build_url', "${env.BUILD_URL}")
    reqBody.put('console_url', info.get('detailUrl'))
    reqBody.put('result', "${currentBuild.currentResult}")
    reqBody.put('duration_str', "${currentBuild.durationString}")
    reqBody.put('duration', currentBuild.duration / 1000)  // currentBuild.duration 为毫秒
    reqBody.put('pipeline_id', env.LIB_ENV_PEPELINE_ID)
    reqBody.put('source_branch', info.get('branch'))
    reqBody.put('target_branch', info.get('targetBranch'))
    reqBody.put('trigger_branch', info.get('branch'))
    reqBody.put('trigger_branch_url', info.get('triggerBranchUrl'))
    reqBody.put('trigger_commit_sha', info.get('commitSha'))
    reqBody.put('trigger_commit_message', info.get('commitMessage'))
    reqBody.put('trigger_username', info.get('username'))
    reqBody.put('trigger_user_id', info.get('userId'))
    reqBody.put('trigger_author', info.get('authorEmail'))
    reqBody.put('trigger_author_email', info.get('authorEmail'))
    reqBody.put('trigger_scm_name', info.get('scmName'))
    reqBody.put('trigger_scm_http', info.get('scmUrl'))
    reqBody.put('trigger_action', info.get('action'))

    httpRequest contentType: 'APPLICATION_JSON_UTF8', 
        consoleLogResponseBody: false,
        httpMode: 'POST', 
        responseHandle: 'NONE', 
        timeout: 10, 
        url: "${baseUrl}/pipeline/pipeline/", 
        requestBody: JsonOutput.toJson(reqBody)

}