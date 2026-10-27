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
                    sh '''
                        set -eu
                        echo "ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-未设置}"
                        command -v adb
                        adb version
                    '''

                    if (!env.ADB_SERVER_SOCKET?.trim()) {
                        error('ADB_SERVER_SOCKET 未设置，容器无法连接宿主机 ADB Server。请检查 compose.yaml 中的 ADB_SERVER_SOCKET。')
                    }

                    def rawDevices = sh(
                        script: 'adb devices -l 2>&1 || true',
                        returnStdout: true
                    ).trim()
                    echo rawDevices

                    if (rawDevices.contains("doesn't match this client")) {
                        error('容器内 adb 与宿主机 ADB Server 版本不一致。请将宿主机 platform-tools 调整到与容器内相同的版本，然后重启 ADB Server。')
                    }
                    if (rawDevices.contains('cannot connect to daemon') ||
                        rawDevices.contains('failed to connect') ||
                        rawDevices.contains('cannot start server on remote host') ||
                        rawDevices.contains('Connection refused')) {
                        error("容器无法连接宿主机 ADB Server（${env.ADB_SERVER_SOCKET}）。请在宿主机执行 adb kill-server，再执行 adb -a nodaemon server，并保持该终端运行。")
                    }

                    // 输出格式：<serial>\t<state> ...
                    def devices = rawDevices.readLines()
                        .findAll { it.contains("\t") }
                        .collect { line ->
                            def parts = line.trim().split(/\s+/, 2)
                            def state = parts.length > 1 ? parts[1].split(/\s+/)[0] : 'unknown'
                            [serial: parts[0], state: state]
                        }

                    if (!devices) {
                        error('ADB Server 已连接，但未发现 Android 设备。请检查 USB 连接和手机 USB 调试开关，并在宿主机执行 adb devices -l 查看状态。')
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
                            error("检测到多台可用设备，请通过 DEVICE_SERIAL 参数指定。当前可用设备: ${usable.collect { it.serial }.join(', ')}")
                        } else {
                            def unauthorized = devices.findAll { it.state == 'unauthorized' }
                            if (unauthorized) {
                                error("设备未授权 USB 调试，请在手机上确认授权。当前设备: ${unauthorized.collect { it.serial }.join(', ')}")
                            }
                            error("没有处于 device 状态的设备。当前设备: ${devices.collect { it.serial + '=' + it.state }.join(', ')}")
                        }
                    }

                    if (target.state == 'unauthorized') {
                        error("设备 ${target.serial} 未授权 USB 调试，请在手机上确认授权。")
                    }
                    if (target.state == 'offline') {
                        error("设备 ${target.serial} 处于 offline 状态，请重新插拔 USB 或重启设备后重试。")
                    }
                    if (target.state != 'device') {
                        error("设备 ${target.serial} 当前状态为 ${target.state}，无法执行测试。")
                    }

                    env.DEVICE_SERIAL = target.serial
                    env.ANDROID_SERIAL = target.serial
                    echo "使用设备: ${target.serial}"

                    withEnv(["ANDROID_SERIAL=${target.serial}"]) {
                        sh '''
                            set -eu
                            printf '设备状态: '
                            adb get-state
                            printf '设备型号: '
                            adb shell getprop ro.product.model
                            printf 'Android 版本: '
                            adb shell getprop ro.build.version.release
                            printf 'SDK 版本: '
                            adb shell getprop ro.build.version.sdk
                        '''
                    }
                }
            }
        }
    }
}
