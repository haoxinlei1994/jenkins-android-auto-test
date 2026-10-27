#!/usr/bin/env bash
#
# 在宿主机后台重启 ADB Server，并同步 Jenkins 镜像的 platform-tools 版本。
#
# Jenkins 容器通过 host.docker.internal:5037 连接这里启动的 ADB Server。
# 使用 -a 让 ADB Server 监听所有网络接口；仅应在可信网络中使用。
#
# 本脚本会把宿主机 adb 的 platform-tools 版本写入项目根目录 .env。
# 首次使用或宿主机 adb 版本变化后，执行 docker compose up -d --build 重建镜像。

set -euo pipefail

adb_server_log='/tmp/adb-server.log'
adb_server_port=5037
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${repo_root}/.env"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command -v adb >/dev/null 2>&1 || die '未找到 adb 命令。'

adb_path="$(command -v adb)"
adb_version_output="$("$adb_path" version)"
printf '%s\n' "$adb_version_output"

platform_tools_version="$(
    printf '%s\n' "$adb_version_output" |
        awk '/^Version / { version = $2; sub(/-.*/, "", version); print version; exit }'
)"
[ -n "$platform_tools_version" ] || die '无法从 adb version 输出中解析 platform-tools 版本。'

# 更新 .env 中的镜像构建版本，保留其它配置
env_tmp_file="$(mktemp "${TMPDIR:-/tmp}/jenkins-android-env.XXXXXX")"
if [ -f "$env_file" ]; then
    awk -v version="$platform_tools_version" '
        /^[[:space:]]*PLATFORM_TOOLS_VERSION[[:space:]]*=/ { next }
        { print }
        END { print "PLATFORM_TOOLS_VERSION=" version }
    ' "$env_file" >"$env_tmp_file"
else
    printf 'PLATFORM_TOOLS_VERSION=%s\n' "$platform_tools_version" >"$env_tmp_file"
fi
mv -f "$env_tmp_file" "$env_file"
printf '已更新 %s: PLATFORM_TOOLS_VERSION=%s\n' "$env_file" "$platform_tools_version"

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
printf '宿主机 adb 版本变化后，请重新执行本脚本并重建镜像：docker compose up -d --build\n'
