// Jenkins Android 自动化测试流水线
//
// 前置条件：
// 1. Jenkins 任务使用 “Pipeline script from SCM” 加载本仓库，确保 scripts/ 与 config/ 已在工作区。
// 2. Jenkins 镜像内已安装 adb 与 git，且 ADB_SERVER_SOCKET 指向宿主机 ADB Server
//    （默认 tcp:host.docker.internal:5037）。
// 3. 宿主机已执行：adb -a nodaemon server
// 4. 手机已开启 USB 调试并授权，且宿主机与容器内 adb 版本一致。
//
// scripts/monkey_test.sh 约定：
// - 参数：--config <配置文件>
// - 环境变量：APK_PATH、APP_PACKAGE、DEVICE_SERIAL、MONKEY_EVENTS、
//   MONKEY_THROTTLE_MS、MONKEY_SEED、LOG_DIR、REPORT_DIR
// - 上述变量为空时，脚本回退到 config/test.yaml 中的配置
// - 测试日志写入 LOG_DIR，测试报告写入 REPORT_DIR
// - Monkey 失败或检测到崩溃/ANR 时返回非 0

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '30'))
        timeout(time: 2, unit: 'HOURS')
    }

    parameters {
        // 被测代码来源；留空时使用当前工作区
        string(name: 'APP_GIT_URL', defaultValue: 'https://github.com/haoxinlei1994/jenkins-android-auto-test.git', description: '被测 App 代码仓库地址；留空则不额外拉取')
        string(name: 'APP_GIT_BRANCH', defaultValue: 'master', description: '被测代码分支、标签或提交')
        string(name: 'APP_GIT_CREDENTIALS_ID', defaultValue: '', description: 'Git 凭据 ID；公开仓库可留空')

        // 测试参数；留空时使用 config/test.yaml
        string(name: 'CONFIG_FILE', defaultValue: 'config/test.yaml', description: '测试配置文件')
        string(name: 'APK_PATH', defaultValue: '', description: 'APK 路径（相对工作区）；留空则使用配置文件中的 apk_path。启用 APP_GIT_URL 时通常位于 app-src/ 下')
        string(name: 'APP_PACKAGE', defaultValue: '', description: '被测应用包名；留空则使用配置文件中的 app_package')
        string(name: 'DEVICE_SERIAL', defaultValue: '', description: '设备序列号；只有一台可用设备时可留空')
        string(name: 'MONKEY_EVENTS', defaultValue: '', description: 'Monkey 事件数；留空则使用配置文件中的值')
        string(name: 'MONKEY_THROTTLE_MS', defaultValue: '', description: 'Monkey 事件间隔（毫秒）；留空则使用配置文件中的值')
        string(name: 'MONKEY_SEED', defaultValue: '', description: 'Monkey 随机种子；留空则使用配置文件中的值')
        string(name: 'TEST_TIMEOUT_MINUTES', defaultValue: '60', description: '测试阶段超时时间（分钟）')

        // 产物目录
        string(name: 'LOG_DIR', defaultValue: 'logs', description: '日志目录（相对工作区）')
        string(name: 'REPORT_DIR', defaultValue: 'reports', description: '报告目录（相对工作区）')
    }

    stages {
        stage('拉取被测代码') {
            options {
                timeout(time: 15, unit: 'MINUTES')
            }
            when {
                expression { !(params.APP_GIT_URL ?: '').trim().isEmpty() }
            }
            steps {
                script {
                    def branch = (params.APP_GIT_BRANCH ?: 'main').trim()
                    def branchSpec = branch
                    if (!(branch ==~ /^[0-9a-fA-F]{7,40}$/) &&
                        !branch.startsWith('refs/') &&
                        !branch.contains('*')) {
                        branchSpec = "*/${branch}"
                    }

                    def remoteConfig = [url: (params.APP_GIT_URL ?: '').trim()]
                    def credentialsId = (params.APP_GIT_CREDENTIALS_ID ?: '').trim()
                    if (credentialsId) {
                        remoteConfig.credentialsId = credentialsId
                    }

                    dir('app-src') {
                        deleteDir()
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: branchSpec]],
                            userRemoteConfigs: [remoteConfig],
                            extensions: [[$class: 'CleanCheckout']]
                        ])
                        sh 'git log -1 --oneline'
                    }
                }
            }
        }

        stage('环境与设备检查') {
            options {
                timeout(time: 5, unit: 'MINUTES')
            }
            steps {
                script {
                    def configFile = (params.CONFIG_FILE ?: 'config/test.yaml').trim()
                    def apkPath = (params.APK_PATH ?: '').trim()
                    def logDir = (params.LOG_DIR ?: 'logs').trim()
                    def reportDir = (params.REPORT_DIR ?: 'reports').trim()

                    sh '''
                        set -eu
                        echo "ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-未设置}"
                        command -v adb
                        command -v git
                        adb version
                        git --version
                    '''

                    if (!env.ADB_SERVER_SOCKET?.trim()) {
                        error('ADB_SERVER_SOCKET 未设置，容器无法连接宿主机 ADB Server。请检查镜像环境变量。')
                    }

                    if (!fileExists(configFile)) {
                        error("测试配置文件不存在: ${configFile}")
                    }

                    if (!logDir || logDir.startsWith('/') || logDir.contains('..')) {
                        error("LOG_DIR 必须是工作区内的相对路径，当前值: ${logDir}")
                    }
                    if (!reportDir || reportDir.startsWith('/') || reportDir.contains('..')) {
                        error("REPORT_DIR 必须是工作区内的相对路径，当前值: ${reportDir}")
                    }

                    if (apkPath && !fileExists(apkPath)) {
                        error("APK 不存在: ${apkPath}")
                    }

                    def numericOverrides = [
                        MONKEY_EVENTS      : params.MONKEY_EVENTS,
                        MONKEY_THROTTLE_MS : params.MONKEY_THROTTLE_MS,
                        MONKEY_SEED        : params.MONKEY_SEED
                    ]
                    numericOverrides.each { key, value ->
                        def raw = (value ?: '').trim()
                        if (raw && !(raw ==~ /\d+/)) {
                            error("${key} 必须是非负整数，当前值: ${raw}")
                        }
                    }

                    // 输出格式：<serial>\t<state>
                    def rawDevices = sh(
                        script: 'adb devices 2>&1 || true',
                        returnStdout: true
                    ).trim()
                    echo rawDevices

                    if (rawDevices.contains("doesn't match this client")) {
                        error('容器内 adb 与宿主机 ADB Server 版本不一致。请将宿主机 platform-tools 调整为与容器内相同的版本。')
                    }
                    if (rawDevices.contains('cannot connect to daemon') ||
                        rawDevices.contains('failed to connect')) {
                        error("容器无法连接宿主机 ADB Server（${env.ADB_SERVER_SOCKET}）。请确认宿主机已执行 adb -a nodaemon server，并允许 Docker 访问 5037 端口。")
                    }

                    def devices = rawDevices.readLines()
                        .findAll { it.contains("\t") }
                        .collect { line ->
                            def parts = line.trim().split(/\s+/, 2)
                            def state = parts.length > 1 ? parts[1].split(/\s+/)[0] : 'unknown'
                            [serial: parts[0], state: state]
                        }

                    if (!devices) {
                        error('未发现 Android 设备。请检查 USB 连接、USB 调试授权，以及宿主机上的 adb devices 输出。')
                    }

                    def requestedSerial = (params.DEVICE_SERIAL ?: '').trim()
                    def target = null

                    if (requestedSerial) {
                        target = devices.find { it.serial == requestedSerial }
                        if (!target) {
                            error("指定设备 ${requestedSerial} 不存在。当前设备: ${devices.collect { it.serial + '=' + it.state }.join(', ')}")
                        }
                    } else {
                        def usable = devices.findAll { it.state == 'device' }
                        if (usable.size() == 1) {
                            target = usable[0]
                        } else if (usable.size() > 1) {
                            error("检测到多台可用设备，请通过 DEVICE_SERIAL 指定。当前设备: ${usable.collect { it.serial }.join(', ')}")
                        } else {
                            def unauthorized = devices.findAll { it.state == 'unauthorized' }
                            if (unauthorized) {
                                error("设备未授权 USB 调试，请在手机上确认授权。当前设备: ${unauthorized.collect { it.serial }.join(', ')}")
                            }
                            error("没有处于 device 状态的设备。当前设备: ${devices.collect { it.serial + '=' + it.state }.join(', ')}")
                        }
                    }

                    if (target.state != 'device') {
                        error("设备 ${target.serial} 当前状态为 ${target.state}，无法执行测试。")
                    }

                    env.DEVICE_SERIAL = target.serial
                    env.ANDROID_SERIAL = target.serial
                    echo "使用设备: ${target.serial}"
                }
            }
        }

        stage('执行 Monkey 测试') {
            steps {
                script {
                    def timeoutRaw = (params.TEST_TIMEOUT_MINUTES ?: '60').trim()
                    if (!(timeoutRaw ==~ /[1-9]\d*/)) {
                        error("TEST_TIMEOUT_MINUTES 必须是正整数，当前值: ${timeoutRaw}")
                    }

                    def configFile = (params.CONFIG_FILE ?: 'config/test.yaml').trim()
                    def logDir = (params.LOG_DIR ?: 'logs').trim()
                    def reportDir = (params.REPORT_DIR ?: 'reports').trim()
                    def testEnv = [
                        "CONFIG_FILE=${configFile}",
                        "LOG_DIR=${logDir}",
                        "REPORT_DIR=${reportDir}",
                        "APK_PATH=${(params.APK_PATH ?: '').trim()}",
                        "APP_PACKAGE=${(params.APP_PACKAGE ?: '').trim()}",
                        "DEVICE_SERIAL=${env.DEVICE_SERIAL ?: ''}",
                        "MONKEY_EVENTS=${(params.MONKEY_EVENTS ?: '').trim()}",
                        "MONKEY_THROTTLE_MS=${(params.MONKEY_THROTTLE_MS ?: '').trim()}",
                        "MONKEY_SEED=${(params.MONKEY_SEED ?: '').trim()}"
                    ]

                    withEnv(testEnv) {
                        timeout(time: timeoutRaw.toInteger(), unit: 'MINUTES') {
                            sh '''
                                set -eu
                                mkdir -p "$LOG_DIR" "$REPORT_DIR"
                                bash scripts/monkey_test.sh --config "$CONFIG_FILE"

                                if [ -z "$(find "$LOG_DIR" -type f -print -quit)" ]; then
                                    echo "错误：日志目录 $LOG_DIR 中没有测试日志。" >&2
                                    exit 1
                                fi
                                if [ -z "$(find "$REPORT_DIR" -type f -print -quit)" ]; then
                                    echo "错误：报告目录 $REPORT_DIR 中没有测试报告。" >&2
                                    exit 1
                                fi
                            '''
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                def logDir = (params.LOG_DIR ?: 'logs').trim()
                def reportDir = (params.REPORT_DIR ?: 'reports').trim()
                archiveArtifacts(
                    artifacts: "${logDir}/**/*,${reportDir}/**/*",
                    allowEmptyArchive: true,
                    fingerprint: true
                )
            }
        }
        success {
            echo 'Monkey 测试完成，日志与报告已归档。'
        }
        failure {
            echo 'Monkey 测试失败，请查看构建日志及归档的 logcat / Monkey 日志。'
        }
    }
}
