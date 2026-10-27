#!/usr/bin/env bash
#
# 步骤 2/5：首次安装时生成 Jenkins 管理员凭据并写入 .env。
# 已有 Jenkins 用户时不覆盖现有账号。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/common.sh"

if compgen -G "${repo_root}/jenkins_home/users/*/config.xml" >/dev/null; then
    printf '检测到已有 Jenkins 用户，跳过管理员凭据生成。\n'
    exit 0
fi

jenkins_admin_user="$(env_value 'JENKINS_ADMIN_USER')"
jenkins_admin_password="$(env_value 'JENKINS_ADMIN_PASSWORD')"

if [ -n "$jenkins_admin_user" ] && [ -n "$jenkins_admin_password" ]; then
    printf '已存在 Jenkins 管理员凭据，跳过生成。\n'
    exit 0
fi

require_command openssl

jenkins_admin_user='admin'
jenkins_admin_password="$(openssl rand -hex 16)"
set_env_value 'JENKINS_ADMIN_USER' "$jenkins_admin_user"
set_env_value 'JENKINS_ADMIN_PASSWORD' "$jenkins_admin_password"
printf '已生成 Jenkins 管理员凭据并写入 %s\n' "$env_file"
