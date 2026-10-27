#!/usr/bin/env bash
#
# 步骤 5/5：输出 Jenkins 地址和登录凭据。
# 已有 Jenkins 账号的密码以哈希形式保存，无法还原；此时只输出已有用户名。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/common.sh"

require_command docker

jenkins_container='jenkins-android-auto-test'

jenkins_port="$(
    cd "$repo_root"
    docker compose port jenkins 8080 2>/dev/null || true
)"
jenkins_port="${jenkins_port##*:}"
jenkins_port="${jenkins_port:-8080}"

printf '\nJenkins 已启动：http://localhost:%s\n' "$jenkins_port"

jenkins_admin_user="$(env_value 'JENKINS_ADMIN_USER')"
jenkins_admin_password="$(env_value 'JENKINS_ADMIN_PASSWORD')"

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
