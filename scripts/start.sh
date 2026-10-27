#!/usr/bin/env bash
#
# 一键启动 Jenkins Android 自动化测试环境。
#
# 各步骤位于同目录下的独立脚本：
#   1. sync_adb_version.sh             同步宿主机 adb 版本到 .env
#   2. generate_jenkins_credentials.sh 首次安装时生成管理员凭据
#   3. restart_adb_server.sh           后台重启宿主机 ADB Server
#   4. start_jenkins.sh                构建并启动 Jenkins 容器
#   5. show_jenkins_credentials.sh     输出 Jenkins 地址和 .env 中的登录凭据
#
# 各步骤共用 common.sh 中的变量和函数。
# 使用 -a 让 ADB Server 监听所有网络接口；仅应在可信网络中使用。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

printf '[1/5] 同步宿主机 ADB 版本\n'
bash "${script_dir}/sync_adb_version.sh"

printf '\n[2/5] 准备 Jenkins 管理员凭据\n'
bash "${script_dir}/generate_jenkins_credentials.sh"

printf '\n[3/5] 重启宿主机 ADB Server\n'
bash "${script_dir}/restart_adb_server.sh"

printf '\n[4/5] 构建并启动 Jenkins 容器\n'
bash "${script_dir}/start_jenkins.sh"

printf '\n[5/5] 输出 Jenkins 访问信息\n'
bash "${script_dir}/show_jenkins_credentials.sh"
