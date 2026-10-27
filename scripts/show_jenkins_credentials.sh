#!/usr/bin/env bash
#
# 步骤 5/5：输出 Jenkins 地址和管理员登录凭据。
#
# 管理员由步骤 2 初始化，密码保存在 .env。
# initialAdminPassword 只用于全新 Jenkins 的首次 setup，不是这里的登录密码。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/common.sh"

jenkins_admin_user="$(env_value 'JENKINS_ADMIN_USER')"
jenkins_admin_password="$(env_value 'JENKINS_ADMIN_PASSWORD')"
jenkins_port="${JENKINS_PORT:-$(env_value 'JENKINS_PORT')}"
jenkins_port="${jenkins_port:-8080}"

printf '\nJenkins 已启动：http://localhost:%s\n' "$jenkins_port"

if [ -z "$jenkins_admin_user" ] || [ -z "$jenkins_admin_password" ]; then
    printf '未找到自动生成的管理员凭据；已有账号的密码无法从 initialAdminPassword 恢复。\n'
    exit 0
fi

printf '用户名: %s\n' "$jenkins_admin_user"
printf '登录密码: %s\n' "$jenkins_admin_password"
printf '凭据文件: %s\n' "$env_file"
