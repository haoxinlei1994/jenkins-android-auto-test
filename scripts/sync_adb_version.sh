#!/usr/bin/env bash
#
# 步骤 1/5：读取宿主机 adb 版本，将 platform-tools 版本写入 .env。

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "${script_dir}/common.sh"

require_command adb

adb_version_output="$(adb version)"
printf '%s\n' "$adb_version_output"

platform_tools_version="$(
    printf '%s\n' "$adb_version_output" |
        awk '/^Version / { version = $2; sub(/-.*/, "", version); print version; exit }'
)"
[ -n "$platform_tools_version" ] || die '无法从 adb version 输出中解析 platform-tools 版本。'

set_env_value 'PLATFORM_TOOLS_VERSION' "$platform_tools_version"
printf '已更新 %s: PLATFORM_TOOLS_VERSION=%s\n' "$env_file" "$platform_tools_version"
