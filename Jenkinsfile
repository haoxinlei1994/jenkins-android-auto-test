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
                    def branch = (params.APP_GIT_BRANCH ?: 'master').trim()
                    def branchSpec = branch
                    if (!(branch ==~ /^[0-9a-fA-F]{7,40}$/) &&
                        !branch.startsWith('refs/') &&
                        !branch.contains('*')) {
                        branchSpec = "*/${branch}"
                    }

                    def remoteConfig = [url: (params.APP_GIT_URL ?: '').trim()]

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
    }
}
