#!/usr/bin/env bash
#
# 检查容器内 adb 到宿主机 ADB Server 的连接，并选择目标设备。
#
# 输入环境变量：
#   ADB_SERVER_SOCKET  必填，例如 tcp:host.docker.internal:5037
#   REQUESTED_SERIAL   可选，指定设备序列号
#
# 输出约定：
#   stdout  成功时只输出选中的设备序列号（一行）
#   stderr  诊断日志和错误信息
#
# 返回码：
#   0  成功
#   非 0  检查失败

set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

adb_server_socket="${ADB_SERVER_SOCKET:-}"
if [ -z "$adb_server_socket" ]; then
    die 'ADB_SERVER_SOCKET 未设置，容器无法连接宿主机 ADB Server。请检查 compose.yaml 中的 ADB_SERVER_SOCKET。'
fi
printf 'ADB_SERVER_SOCKET=%s\n' "$adb_server_socket" >&2

adb_path="$(command -v adb || true)"
if [ -z "$adb_path" ]; then
    die '未找到 adb 命令，请检查 Jenkins 镜像中的 Android platform-tools 安装。'
fi
printf 'adb 路径: %s\n' "$adb_path" >&2

if ! adb_version="$(adb version 2>&1)"; then
    die "执行 adb version 失败：${adb_version}"
fi
printf '%s\n' "$adb_version" >&2

raw_devices="$(adb devices -l 2>&1 || true)"
printf '%s\n' "$raw_devices" >&2

case "$raw_devices" in
    *"doesn't match this client"*)
        die '容器内 adb 与宿主机 ADB Server 版本不一致。请将宿主机 platform-tools 调整到与容器内相同的版本，然后重启 ADB Server。'
        ;;
    *"cannot connect to daemon"* | *"failed to connect"* | *"cannot start server on remote host"* | *"Connection refused"*)
        die "容器无法连接宿主机 ADB Server（${adb_server_socket}）。请在宿主机执行 adb kill-server，再执行 adb -a nodaemon server，并保持该终端运行。"
        ;;
esac

# 解析 adb devices -l 的设备行：<serial>\t<state> ...
device_table="$(
    printf '%s\n' "$raw_devices" |
        tr -d '\r' |
        awk -F '\t' '
            NF >= 2 {
                serial = $1
                state = $2
                sub(/^[[:space:]]+/, "", state)
                split(state, fields, /[[:space:]]+/)
                if (serial != "" && fields[1] != "") {
                    printf "%s\t%s\n", serial, fields[1]
                }
            }
        '
)"

device_serials=()
device_states=()

while IFS=$'\t' read -r serial state; do
    if [ -z "$serial" ]; then
        continue
    fi
    device_serials+=("$serial")
    device_states+=("${state:-unknown}")
done <<< "$device_table"

if [ "${#device_serials[@]}" -eq 0 ]; then
    die 'ADB Server 已连接，但未发现 Android 设备。请检查 USB 连接和手机 USB 调试开关，并在宿主机执行 adb devices -l 查看状态。'
fi

format_devices() {
    local output=""
    local i
    for i in "${!device_serials[@]}"; do
        if [ -n "$output" ]; then
            output+=", "
        fi
        output+="${device_serials[$i]}=${device_states[$i]}"
    done
    printf '%s' "$output"
}

requested_serial="${REQUESTED_SERIAL:-}"
target_serial=""
target_state=""

if [ -n "$requested_serial" ]; then
    for i in "${!device_serials[@]}"; do
        if [ "${device_serials[$i]}" = "$requested_serial" ]; then
            target_serial="${device_serials[$i]}"
            target_state="${device_states[$i]}"
            break
        fi
    done

    if [ -z "$target_serial" ]; then
        die "指定设备 ${requested_serial} 不存在。当前设备: $(format_devices)"
    fi
else
    usable_count=0
    usable_list=""
    unauthorized_list=""

    for i in "${!device_serials[@]}"; do
        serial="${device_serials[$i]}"
        state="${device_states[$i]}"

        if [ "$state" = "device" ]; then
            usable_count=$((usable_count + 1))
            if [ -n "$usable_list" ]; then
                usable_list+=", "
            fi
            usable_list+="$serial"
            if [ "$usable_count" -eq 1 ]; then
                target_serial="$serial"
                target_state="$state"
            fi
        elif [ "$state" = "unauthorized" ]; then
            if [ -n "$unauthorized_list" ]; then
                unauthorized_list+=", "
            fi
            unauthorized_list+="$serial"
        fi
    done

    if [ "$usable_count" -eq 0 ]; then
        if [ -n "$unauthorized_list" ]; then
            die "设备未授权 USB 调试，请在手机上确认授权。当前设备: ${unauthorized_list}"
        fi
        die "没有处于 device 状态的设备。当前设备: $(format_devices)"
    elif [ "$usable_count" -gt 1 ]; then
        die "检测到多台可用设备，请通过 DEVICE_SERIAL 参数指定。当前可用设备: ${usable_list}"
    fi
fi

case "$target_state" in
    unauthorized)
        die "设备 ${target_serial} 未授权 USB 调试，请在手机上确认授权。"
        ;;
    offline)
        die "设备 ${target_serial} 处于 offline 状态，请重新插拔 USB 或重启设备后重试。"
        ;;
    device)
        ;;
    *)
        die "设备 ${target_serial} 当前状态为 ${target_state}，无法执行测试。"
        ;;
esac

if ! device_state="$(adb -s "$target_serial" get-state 2>&1)"; then
    die "无法获取设备 ${target_serial} 的状态：${device_state}"
fi
printf '设备状态: %s\n' "$device_state" >&2

print_prop() {
    local label="$1"
    local prop="$2"
    local value

    if ! value="$(adb -s "$target_serial" shell getprop "$prop" 2>&1)"; then
        die "读取设备属性 ${prop} 失败：${value}"
    fi
    value="$(printf '%s' "$value" | tr -d '\r')"
    printf '%s: %s\n' "$label" "$value" >&2
}

print_prop '设备型号' 'ro.product.model'
print_prop 'Android 版本' 'ro.build.version.release'
print_prop 'SDK 版本' 'ro.build.version.sdk'

printf '%s\n' "$target_serial"
