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
// - 读取 REQUESTED_SERIAL（可选）与 ADB_SERVER_SOCKET
// - 成功时 stdout 只输出选中的设备序列号，日志和错误输出到 stderr
// - 失败时返回非 0
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
        // 测试参数；留空时使用 config/test.yaml
        string(name: 'CONFIG_FILE', defaultValue: 'config/test.yaml', description: '测试配置文件')
        string(name: 'APK_PATH', defaultValue: '', description: 'APK 路径（相对工作区）；留空则使用配置文件中的 apk_path')
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
        stage('检查 ADB 连接') {
            options {
                timeout(time: 5, unit: 'MINUTES')
            }
            steps {
                script {
                    def requestedSerial = (params.DEVICE_SERIAL ?: '').trim()
                    def serial = ''

                    withEnv(["REQUESTED_SERIAL=${requestedSerial}"]) {
                        serial = sh(
                            script: 'bash scripts/check_adb.sh',
                            returnStdout: true
                        ).trim()
                    }

                    if (!serial) {
                        error('ADB 检查脚本没有返回设备序列号')
                    }

                    env.DEVICE_SERIAL = serial
                    env.ANDROID_SERIAL = serial
                    echo "使用设备: ${serial}"
                }
            }
        }
    }
}
