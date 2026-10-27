#!/usr/bin/env bash
#
# 在宿主机后台重启 ADB Server，并同步 Jenkins 镜像的 platform-tools 版本。
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
# 同时读取本机 adb 的 platform-tools 版本并写入项目根目录 .env，
# 供 compose.yaml 构建 Jenkins 镜像使用，避免 ADB client/server 版本不一致。
#
# 注意：
#   - 本脚本用于宿主机，不要在 Jenkins 容器内执行。
#   - -a 会把 ADB 端口暴露到局域网，请仅在可信网络使用。
#   - 版本写入 .env 后，需要重新构建镜像才会生效：
#     docker compose up -d --build
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

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
env_file="${repo_root}/.env"

update_platform_tools_env() {
    local version="$1"
    local tmp_file

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/jenkins-android-env.XXXXXX")"
    if [ -f "$env_file" ]; then
        # 保留其它配置，只替换 PLATFORM_TOOLS_VERSION
        awk -v version="$version" '
            /^[[:space:]]*(export[[:space:]]+)?PLATFORM_TOOLS_VERSION[[:space:]]*=/ {
                if (!updated) {
                    print "PLATFORM_TOOLS_VERSION=" version
                    updated = 1
                }
                next
            }
            { print }
            END {
                if (!updated) {
                    print "PLATFORM_TOOLS_VERSION=" version
                }
            }
        ' "$env_file" >"$tmp_file"
    else
        {
            printf '# 由 scripts/restart_adb_server.sh 自动生成：与宿主机 adb 版本保持一致\n'
            printf 'PLATFORM_TOOLS_VERSION=%s\n' "$version"
        } >"$tmp_file"
    fi
    mv -f "$tmp_file" "$env_file"
}

command -v adb >/dev/null 2>&1 || die '未找到 adb 命令。'
command -v lsof >/dev/null 2>&1 || die '未找到 lsof 命令。'
command -v nohup >/dev/null 2>&1 || die '未找到 nohup 命令。'

adb_path="$(command -v adb)"
printf 'adb 路径: %s\n' "$adb_path"
if ! adb_version_output="$("$adb_path" version 2>&1)"; then
    die "执行 adb version 失败：${adb_version_output}"
fi
printf '%s\n' 'adb 版本:'
printf '%s\n' "$adb_version_output"

platform_tools_version="$(
    printf '%s\n' "$adb_version_output" |
        tr -d '\r' |
        awk '/^Version / { version = $2; sub(/-.*/, "", version); print version; exit }'
)"
if [ -z "$platform_tools_version" ]; then
    die '无法从 adb version 输出中解析 platform-tools 版本，请确认本机 adb 安装完整。'
fi
if ! printf '%s\n' "$platform_tools_version" |
    grep -Eq '^[0-9]+(\.[0-9]+)+$'; then
    die "解析出的 platform-tools 版本格式无效：${platform_tools_version}"
fi

update_platform_tools_env "$platform_tools_version"
printf '已更新 %s: PLATFORM_TOOLS_VERSION=%s\n' "$env_file" "$platform_tools_version"

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
printf 'Jenkins 镜像构建版本已同步为 platform-tools %s。\n' "$platform_tools_version"
printf '首次使用或宿主机 adb 版本变化后，请执行：docker compose up -d --build\n'
