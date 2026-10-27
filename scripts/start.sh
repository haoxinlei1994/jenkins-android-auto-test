#!/usr/bin/env bash
#
# 启动 Jenkins 容器与宿主机 ADB Server。
#
# 流程：
#   1. 读取宿主机 adb 版本并写入 .env
#   2. 首次运行时生成 Jenkins 管理员凭据并写入 .env
#   3. 后台启动 ADB Server，容器通过 host.docker.internal:5037 连接
#   4. 构建并启动 Jenkins 容器，等待健康检查通过
#   5. 输出 Jenkins 地址和登录凭据
#
# 使用 -a 让 ADB Server 监听所有网络接口；仅应在可信网络中使用。

set -euo pipefail

adb_server_log='/tmp/adb-server.log'
adb_server_port=5037
jenkins_container='jenkins-android-auto-test'
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${repo_root}/.env"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

set_env_value() {
    local key="$1"
    local value="$2"
    local tmp_file

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/jenkins-android-env.XXXXXX")"
    if [ -f "$env_file" ]; then
        awk -v key="$key" -v value="$value" '
            $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { next }
            { print }
            END { print key "=" value }
        ' "$env_file" >"$tmp_file"
    else
        printf '%s=%s\n' "$key" "$value" >"$tmp_file"
    fi
    mv -f "$tmp_file" "$env_file"
}

env_value() {
    [ -f "$env_file" ] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$env_file" | tail -n 1
}

command -v adb >/dev/null 2>&1 || die '未找到 adb 命令。'
command -v docker >/dev/null 2>&1 || die '未找到 docker 命令。'

# 读取宿主机 adb 版本，同步到镜像构建参数
adb_path="$(command -v adb)"
adb_version_output="$("$adb_path" version)"
printf '%s\n' "$adb_version_output"

platform_tools_version="$(
    printf '%s\n' "$adb_version_output" |
        awk '/^Version / { version = $2; sub(/-.*/, "", version); print version; exit }'
)"
[ -n "$platform_tools_version" ] || die '无法从 adb version 输出中解析 platform-tools 版本。'
set_env_value 'PLATFORM_TOOLS_VERSION' "$platform_tools_version"
printf '已更新 %s: PLATFORM_TOOLS_VERSION=%s\n' "$env_file" "$platform_tools_version"

# 首次安装时生成管理员凭据；已有 Jenkins 用户时不覆盖
jenkins_admin_user="$(env_value 'JENKINS_ADMIN_USER')"
jenkins_admin_password="$(env_value 'JENKINS_ADMIN_PASSWORD')"
if ! compgen -G "${repo_root}/jenkins_home/users/*/config.xml" >/dev/null &&
    { [ -z "$jenkins_admin_user" ] || [ -z "$jenkins_admin_password" ]; }; then
    command -v openssl >/dev/null 2>&1 || die '未找到 openssl，无法生成 Jenkins 管理员密码。'
    jenkins_admin_user='admin'
    jenkins_admin_password="$(openssl rand -hex 16)"
    set_env_value 'JENKINS_ADMIN_USER' "$jenkins_admin_user"
    set_env_value 'JENKINS_ADMIN_PASSWORD' "$jenkins_admin_password"
    printf '已生成 Jenkins 管理员凭据并写入 %s\n' "$env_file"
fi

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
printf '构建并启动 Jenkins 容器（首次启动可能需要几分钟）...\n'

if ! (
    cd "$repo_root"
    docker compose up -d --build --wait --wait-timeout 300
); then
    printf 'Jenkins 启动失败或健康检查超时。查看日志：docker logs %s\n' \
        "$jenkins_container" >&2
    exit 1
fi

jenkins_port="$(
    cd "$repo_root"
    docker compose port jenkins 8080 2>/dev/null || true
)"
jenkins_port="${jenkins_port##*:}"
jenkins_port="${jenkins_port:-8080}"
jenkins_url="http://localhost:${jenkins_port}"

printf '\nJenkins 已启动：%s\n' "$jenkins_url"

if [ -n "$jenkins_admin_user" ] && [ -n "$jenkins_admin_password" ] &&
    grep -qsF "<id>${jenkins_admin_user}</id>" "${repo_root}"/jenkins_home/users/*/config.xml; then
    printf '用户名: %s\n' "$jenkins_admin_user"
    printf '登录密码: %s\n' "$jenkins_admin_password"
    printf '初始凭据已保存到: %s（如在 Jenkins 中改过密码，请使用新密码）\n' "$env_file"
else
    existing_users=''
    for user_config in "${repo_root}"/jenkins_home/users/*/config.xml; do
        [ -f "$user_config" ] || continue
        user_id="$(awk -F'[<>]' '/<id>/ { print $3; exit }' "$user_config")"
        [ -n "$user_id" ] || continue
        existing_users="${existing_users:+${existing_users}, }${user_id}"
    done

    if [ -n "$existing_users" ]; then
        printf '现有用户名: %s\n' "$existing_users"
        printf 'Jenkins 只保存密码哈希，无法输出已有账号的登录密码。\n'
    else
        initial_password_file="${repo_root}/jenkins_home/secrets/initialAdminPassword"
        if [ -f "$initial_password_file" ]; then
            printf '初始化密码: %s\n' "$(cat "$initial_password_file")"
            printf '请打开 Jenkins 完成首次初始化。\n'
        else
            printf '未找到管理员凭据，请查看启动日志：docker logs %s\n' \
                "$jenkins_container"
        fi
    fi
fi
