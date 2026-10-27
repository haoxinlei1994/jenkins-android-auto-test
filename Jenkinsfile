// Jenkins Android 自动化测试流水线
//
// 前置条件：
// 1. Jenkins 任务使用 “Pipeline script from SCM” 加载本仓库；工作区根目录即项目根目录，
//    包含 Jenkinsfile、scripts/ 和 config/，无需在流水线内重复拉取。
// 2. Jenkins 镜像内已安装 adb 与 git，且 ADB_SERVER_SOCKET 指向宿主机 ADB Server
//    （默认 tcp:host.docker.internal:5037）。
// 3. 宿主机已执行：adb -a nodaemon server
// 4. 手机已开启 USB 调试并授权，且宿主机与容器内 adb 版本一致。
//
// scripts/check_adb.sh 约定：
// - 读取 ADB_SERVER_SOCKET
// - 自动选择唯一一台处于 device 状态的设备；多设备时直接失败
// - 成功时 stdout 只输出选中的设备序列号，日志和错误输出到 stderr
// - 失败时返回非 0
//
// scripts/monkey_test.sh 约定：
// - 直接修改脚本中的 app_package 和 Monkey 参数
// - 应用需已安装在设备上
// - 解锁屏幕、启动应用并执行 Monkey，不生成日志和测试报告
// - Monkey 结束后直接返回其退出码

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '30'))
        timeout(time: 2, unit: 'HOURS')
    }

    stages {
        stage('检查 ADB 连接') {
            options {
                timeout(time: 5, unit: 'MINUTES')
            }
            steps {
                script {
                    def serial = sh(
                        script: 'bash scripts/check_adb.sh',
                        returnStdout: true
                    ).trim()

                    if (!serial) {
                        error('ADB 检查脚本没有返回设备序列号')
                    }

                    echo "使用设备: ${serial}"
                }
            }
        }

        stage('Monkey 测试') {
            options {
                timeout(time: 60, unit: 'MINUTES')
            }
            steps {
                sh 'bash scripts/monkey_test.sh'
            }
        }
    }
}
