#!/usr/bin/env bash
#
# 步骤 3/5：在宿主机后台重启 ADB Server。
#
# Jenkins 容器通过 host.docker.internal:5037 连接这里启动的 ADB Server。
# 使用 -a 让 ADB Server 监听所有网络接口；仅应在可信网络中使用。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/common.sh"

require_command adb

adb_server_log='/tmp/adb-server.log'
adb_server_port=5037
adb_path="$(command -v adb)"

# 结束已有 Server，确保新的 -a 监听生效
"$adb_path" kill-server >/dev/null 2>&1 || true
listener_pids="$(lsof -ti "tcp:${adb_server_port}" -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$listener_pids" ]; then
    # shellcheck disable=SC2086
    kill $listener_pids 2>/dev/null || true
    sleep 1
fi

# 后台启动 ADB Server
nohup "$adb_path" -a nodaemon server >"$adb_server_log" 2>&1 </dev/null &
server_pid=$!
sleep 1

if ! kill -0 "$server_pid" 2>/dev/null; then
    printf 'ADB Server 启动失败，日志：\n' >&2
    tail -n 20 "$adb_server_log" >&2 || true
    exit 1
fi

printf 'ADB Server 已启动，PID: %s，监听端口: %s\n' \
    "$server_pid" "$adb_server_port"
printf '日志文件: %s\n' "$adb_server_log"
