#!/usr/bin/env bash
#
# 步骤 4/5：构建并启动 Jenkins 容器，等待健康检查通过。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/common.sh"

require_command docker

jenkins_container='jenkins-android-auto-test'

printf '构建并启动 Jenkins 容器（首次启动可能需要几分钟）...\n'
if ! (
    cd "$repo_root"
    docker compose up -d --build --wait --wait-timeout 300
); then
    printf 'Jenkins 启动失败或健康检查超时。查看日志：docker logs %s\n' \
        "$jenkins_container" >&2
    exit 1
fi
