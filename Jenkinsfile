// Jenkins Android 自动化测试流水线
//
// 前置条件：
// 1. Jenkins 任务使用 “Pipeline script from SCM” 加载本仓库；工作区根目录即项目根目录，
//    包含 Jenkinsfile 和 scripts/，无需在流水线内重复拉取。
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
// - 解锁屏幕、启动应用并执行 Monkey
// - Monkey 结束后调用 scripts/memory_leak_test.sh 检测内存泄漏
//
// scripts/memory_leak_test.sh 约定：
// - 关闭 App 页面并返回桌面，确认 App 进程仍在运行
// - dump Java 堆并使用 Square Shark 分析
// - 检测到内存泄漏时生成 reports/memory-leak-report.md

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '30'))
        timeout(time: 2, unit: 'HOURS')
    }

    stages {
        stage('准备并检查 ADB 连接') {
            options {
                timeout(time: 5, unit: 'MINUTES')
            }
            steps {
                // 清理上一次构建遗留的报告，避免本次失败时误归档旧报告
                sh 'rm -f reports/memory-leak-report.md'

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

        stage('Monkey 与内存泄漏测试') {
            options {
                timeout(time: 60, unit: 'MINUTES')
            }
            steps {
                sh 'bash scripts/monkey_test.sh'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/memory-leak-report.md', allowEmptyArchive: true
        }
    }
}
