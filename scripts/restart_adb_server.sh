#!/usr/bin/env bash
#
# 在宿主机后台重启 ADB Server，并监听所有网络接口。
#
# 用途：
#   Jenkins 容器通过 host.docker.internal:5037 连接宿主机 ADB Server。
#   普通 adb start-server 只监听 127.0.0.1，容器无法访问，因此使用：
#     adb -a nodaemon server
#
# 环境变量：
#   ADB_SERVER_LOG   日志文件，默认 /tmp/adb-server.log
#   ADB_SERVER_PORT  ADB Server 端口，默认 5037
#
# 注意：
#   - 本脚本用于宿主机，不要在 Jenkins 容器内执行。
#   - -a 会把 ADB 端口暴露到局域网，请仅在可信网络使用。
#
# 返回码：
#   0  启动成功
#   非 0  启动失败

set -euo pipefail

adb_server_log="${ADB_SERVER_LOG:-/tmp/adb-server.log}"
adb_server_port="${ADB_SERVER_PORT:-5037}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command -v adb >/dev/null 2>&1 || die '未找到 adb 命令。'
command -v lsof >/dev/null 2>&1 || die '未找到 lsof 命令。'
command -v nohup >/dev/null 2>&1 || die '未找到 nohup 命令。'

adb_path="$(command -v adb)"
printf 'adb 路径: %s\n' "$adb_path"
printf '%s\n' 'adb 版本:'
"$adb_path" version

listener_pids() {
    lsof -ti "tcp:${adb_server_port}" -sTCP:LISTEN 2>/dev/null || true
}

listener_names() {
    lsof -nP -iTCP:"${adb_server_port}" -sTCP:LISTEN 2>/dev/null |
        awk 'NR > 1 { print $9 }'
}

printf '停止现有 ADB Server...\n'
"$adb_path" kill-server >/dev/null 2>&1 || true

pids="$(listener_pids)"
if [ -n "$pids" ]; then
    printf '端口 %s 仍被占用，结束进程: %s\n' "$adb_server_port" "$pids"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        [ -z "$(listener_pids)" ] && break
        sleep 1
    done
fi

if [ -n "$(listener_pids)" ]; then
    die "端口 ${adb_server_port} 仍被占用，无法启动 ADB Server。"
fi

printf '后台启动 ADB Server...\n'
nohup "$adb_path" -a nodaemon server \
    >"$adb_server_log" 2>&1 </dev/null &
server_pid=$!

listening=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -n "$(listener_names)" ]; then
        listening=true
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        printf 'ADB Server 进程已退出，日志：\n' >&2
        tail -n 20 "$adb_server_log" >&2 || true
        exit 1
    fi
    sleep 1
done

if [ "$listening" != true ]; then
    printf 'ADB Server 启动超时，日志：\n' >&2
    tail -n 20 "$adb_server_log" >&2 || true
    kill "$server_pid" 2>/dev/null || true
    exit 1
fi

listeners="$(listener_names)"
printf 'ADB Server 已启动，PID: %s\n' "$server_pid"
printf '监听地址:\n%s\n' "$listeners"
printf '日志文件: %s\n' "$adb_server_log"

if ! printf '%s\n' "$listeners" |
    grep -Eq '^(\*|0\.0\.0\.0|\[::\]):'"${adb_server_port}"'$'; then
    printf 'ERROR: ADB Server 未监听所有网络接口，容器可能无法连接。\n' >&2
    printf '请检查 ADB Server 是否使用了 -a 参数。\n' >&2
    kill "$server_pid" 2>/dev/null || true
    exit 1
fi

printf '完成。容器可通过 host.docker.internal:%s 连接。\n' "$adb_server_port"
