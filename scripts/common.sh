#!/usr/bin/env bash
#
# start.sh 各步骤共用变量和函数。
#
# 本文件只被其他脚本 source 引入，不直接执行。

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${repo_root}/.env"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "未找到 $1 命令。"
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
