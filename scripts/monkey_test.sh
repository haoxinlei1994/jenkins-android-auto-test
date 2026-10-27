#!/usr/bin/env bash
#
# 启动已安装的应用并执行 Monkey 测试。
# 直接修改下面的 app_package 和 Monkey 参数即可。

set -euo pipefail

app_package='com.rollydrop.app'

# 点亮并解锁屏幕（适用于未设置密码的锁屏）
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
sleep 1

# 启动应用
adb shell monkey -p "$app_package" -c android.intent.category.LAUNCHER 1

# 等待应用启动
sleep 3

# Monkey 测试，按需修改事件数和 throttle
adb shell monkey -p "$app_package" --throttle 30 1000
