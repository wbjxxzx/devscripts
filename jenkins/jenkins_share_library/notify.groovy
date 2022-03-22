/*
 * 流水线任务开始、结束发送通知
 */

import groovy.json.JsonSlurperClassic
import groovy.json.JsonOutput
import org.devops.serializers.PipelineTaskInfo

def call() {

}

def jobStart(PipelineTaskInfo info, String baseUrl){
    def triggerInfoMap = [:]
    triggerInfoMap.put('start_timestamp', currentBuild.startTimeInMillis / 1000)
    triggerInfoMap.put('ci_server', "${env.JENKINS_URL}")
    triggerInfoMap.put('job_name', "${env.JOB_NAME}")
    triggerInfoMap.put('build_id', env.BUILD_NUMBER)
    triggerInfoMap.put('build_url', "${env.BUILD_URL}")
    triggerInfoMap.put('console_url', info.get('detailUrl'))
    triggerInfoMap.put('pipeline_id', env.LIB_ENV_PEPELINE_ID)
    triggerInfoMap.put('source_branch', info.get('sourceBranch'))
    triggerInfoMap.put('target_branch', info.get('targetBranch'))
    triggerInfoMap.put('trigger_branch', info.get('sourceBranch'))
    triggerInfoMap.put('trigger_commit_sha', info.get('commitSha'))
    triggerInfoMap.put('trigger_username', info.get('username'))
    triggerInfoMap.put('trigger_author', info.get('username'))
    triggerInfoMap.put('trigger_user_id', info.get('userId'))
    triggerInfoMap.put('trigger_author_email', info.get('authorEmail'))
    triggerInfoMap.put('trigger_scm_name', info.get('scmName'))
    triggerInfoMap.put('trigger_scm_http', info.get('scmUrl'))
    triggerInfoMap.put('trigger_action', info.get('action'))

    println("triggerInfoMap: ${triggerInfoMap}")
    httpRequest contentType: 'APPLICATION_JSON_UTF8', 
        consoleLogResponseBody: false,
        httpMode: 'POST', 
        responseHandle: 'NONE', 
        timeout: 30, 
        url: "${baseUrl}/pipeline/trigger/", 
        requestBody: JsonOutput.toJson(triggerInfoMap)
}


def jobFinish(PipelineTaskInfo info, String token="xxx"){
    def msg = null
    if (info.get('action') == "merge"){
        msg = generateMergeMsg(info)
    } else {
        msg = generatePushMsg(info)
    }
    httpRequest contentType: 'APPLICATION_JSON_UTF8', 
        consoleLogResponseBody: true,
        httpMode: 'POST', 
        responseHandle: 'NONE', 
        timeout: 30, 
        url: "https://open.feishu.cn/open-apis/bot/v2/hook/${token}", 
        requestBody: JsonOutput.toJson(msg)

}

def generatePushMsg(PipelineTaskInfo info){
    def color = "${currentBuild.currentResult}" == 'SUCCESS' ? 'green' : 'red'
    def flag  = "${currentBuild.currentResult}" == 'SUCCESS' ? '👍 ' : '❗️ '

    def elements = [
        [
            "tag": "div",
            "fields": [
                [
                    "is_short": true,
                    "text": [
                        "content": "**构建用户：**" + info.get('username') + "<at email=" + info.get('authorEmail') + "></at>",
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": true,
                    "text": [
                        "content": "**时间：**${LIB_ENV_START_TIME}",
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": true,
                    "text": [
                        "content": "**构建结果：**${currentBuild.currentResult}",
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": true,
                    "text": [
                        "content": "**代码库名称：**[" + info.get('scmName') + "](" + info.get('scmUrl') + ")",
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**提交分支：**" + info.get('branch'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**提交信息: **" + info.get('commitMessage'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**提交号: **" + info.get('commitSha'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**代码扫描结果: **" + info.get('sonarResult'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**单元测试覆盖率：**" + info.get('unittestResult'),
                        "tag": "lark_md"
                    ]
                ]
            ]
        ],
        ["tag": "hr"],
        [
            "tag": "div",
            "text": [
                "content": "**构建日志: **[点我查看](" + info.get('detailUrl') + ")",
                "tag": "lark_md"
            ]
        ],
        [
            "tag": "note",
            "elements": [
                [
                    "content": "构建时长: ${currentBuild.durationString}",
                    "tag": "plain_text"
                ]
            ]
        ]
    ]

    if(info.get('category') == 'release'){
        elements[0]['fields'].push([
            "is_short": false,
            "text": [
                "content": "**自动化测试结果：**" + info.get('autotestResult'),
                "tag": "lark_md"
            ]
        ])
    }

    def msg = [
        "msg_type": "interactive", 
        "card": [
            "header": [
                "template": "${color}",
                "title": [
                    "content": "${flag} " + info.get('scmName') + " 自动构建任务 # ${env.BUILD_NUMBER} 详情",
                    "tag": "plain_text"
                ]
            ],
            "config": [
                "wide_screen_mode": true
            ], 
            "elements": elements
        ]
    ]

    return msg
}

def generateMergeMsg(PipelineTaskInfo info){
    def color = "${currentBuild.currentResult}" == 'SUCCESS' ? 'green' : 'red'
    def flag  = "${currentBuild.currentResult}" == 'SUCCESS' ? '👍 ' : '❗️ '

    def elements = [
        [
            "tag": "div",
            "fields": [
                [
                    "is_short": true,
                    "text": [
                        "content": "**请求用户：**" + info.get('username') + "<at email=" + info.get('authorEmail') + "></at>",
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": true,
                    "text": [
                        "content": "**时间：**${LIB_ENV_START_TIME}",
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": true,
                    "text": [
                        "content": "**合并检查结果：**${currentBuild.currentResult}",
                        "tag": "lark_md"
                    ]
                ],
            ],
        ],
        ["tag": "hr"],
        [
            "tag": "div",
            "fields": [
                [
                    "is_short": true,
                    "text": [
                        "content": "**代码库名称：**[" + info.get('scmName') + "](" + info.get('scmUrl') + ")",
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**源分支：**" + info.get('sourceBranch'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**目标分支：**" + info.get('targetBranch'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**提交信息: **" + info.get('commitMessage'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**提交号: **" + info.get('commitSha'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "合并请求链接: **[合并请求](" + info.get('triggerBranchUrl') + ")",
                        "tag": "lark_md"
                    ]
                ],
            ]
        ],
        ["tag": "hr"],
        [
            "tag": "div",
            "fields": [
                [
                    "is_short": false,
                    "text": [
                        "content": "**代码扫描结果: **" + info.get('sonarResult'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**单元测试覆盖率：**" + info.get('unittestResult'),
                        "tag": "lark_md"
                    ]
                ],
                [
                    "is_short": false,
                    "text": [
                        "content": "**自动化测试结果：**" + info.get('autotestResult'),
                        "tag": "lark_md"
                    ]
                ]
            ]
        ],
        ["tag": "hr"],
        [
            "tag": "div",
            "text": [
                "content": "**构建日志: **[点我查看](" + info.get('detailUrl') + ")",
                "tag": "lark_md"
            ]
        ],
        [
            "tag": "note",
            "elements": [
                [
                    "content": "构建时长: ${currentBuild.durationString}",
                    "tag": "plain_text"
                ]
            ]
        ]
    ]

    def msg = [
        "msg_type": "interactive", 
        "card": [
            "header": [
                "template": "${color}",
                "title": [
                    "content": "${flag} " + info.get('scmName') + " 自动合并任务 # ${env.BUILD_NUMBER} 详情",
                    "tag": "plain_text"
                ]
            ],
            "config": [
                "wide_screen_mode": true
            ], 
            "elements": elements
        ]
    ]

    return msg
}