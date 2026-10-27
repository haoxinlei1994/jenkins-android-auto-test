#!/usr/bin/env bash
#
# Monkey 测试结束后关闭 App 页面并检测内存泄漏。
#
# 用法：
#   bash scripts/memory_leak_test.sh <app_package>
#
# 流程：
#   1. 连续发送返回键关闭 App 页面，直到回到桌面，并确认 App 进程仍在
#   2. 强制 GC 后 dump App 的 Java 堆
#   3. 使用 Square Shark 分析堆
#   4. 检测到泄漏时生成 reports/memory-leak-report.md

set -euo pipefail

app_package="${1:-}"
if [ -z "$app_package" ]; then
    printf 'ERROR: 未传入 app_package\n' >&2
    exit 1
fi

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

shark_cli="$(command -v shark-cli || true)"
[ -n "$shark_cli" ] || die '未找到 shark-cli，请检查 Jenkins 镜像中的 Shark 安装。'

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
reports_dir="${repo_root}/reports"
report_file="${reports_dir}/memory-leak-report.md"
mkdir -p "$reports_dir"
rm -f "$report_file"

remote_hprof="/data/local/tmp/shark-memory-leak-$$.hprof"
work_dir="$(mktemp -d)"

cleanup() {
    adb shell rm -f "$remote_hprof" >/dev/null 2>&1 || true
    rm -rf "$work_dir"
}
trap cleanup EXIT

current_package() {
    adb shell dumpsys activity activities 2>/dev/null |
        tr -d '\r' |
        awk '
            /topResumedActivity=|mResumedActivity=/ {
                if (line == "") {
                    line = $0
                }
            }
            END {
                if (line != "") {
                    print line
                }
            }
        ' |
        sed -n 's/.*[[:space:]]\([^/ ]*\)\/.*/\1/p'
}

launcher_component="$(
    adb shell cmd package resolve-activity --brief \
        -a android.intent.action.MAIN \
        -c android.intent.category.HOME 2>/dev/null |
        tail -n 1 | tr -d '\r'
)"
launcher_package="${launcher_component%%/*}"
[ -n "$launcher_package" ] || die '无法获取桌面应用包名。'

printf '关闭 App 页面并返回桌面...\n'
on_home=false
for ((attempt = 1; attempt <= 50; attempt++)); do
    current="$(current_package)"
    if [ "$current" = "$launcher_package" ]; then
        on_home=true
        break
    fi
    adb shell input keyevent KEYCODE_BACK
    sleep 0.5
done

if [ "$on_home" != true ] && [ "$(current_package)" = "$launcher_package" ]; then
    on_home=true
fi

if [ "$on_home" != true ]; then
    adb shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
    die '连续返回 50 次仍未回到桌面，已强制返回桌面并终止检测。'
fi

sleep 2
[ "$(current_package)" = "$launcher_package" ] || die '关闭页面后前台不是桌面，终止检测。'

app_pid="$(adb shell pidof "$app_package" 2>/dev/null | tr -d '\r' | awk '{print $1}' || true)"
[ -n "$app_pid" ] || die "App 进程 ${app_package} 已不存在，无法 dump 堆。"
printf '已返回桌面，App 进程仍在运行（PID: %s）\n' "$app_pid"

printf 'Dump Java 堆...\n'
adb shell am dumpheap -g "$app_package" "$remote_hprof"
sleep 2
local_hprof="${work_dir}/heap.hprof"
adb pull "$remote_hprof" "$local_hprof"
adb shell rm -f "$remote_hprof" >/dev/null 2>&1 || true
[ -s "$local_hprof" ] || die '堆 dump 文件为空。'

printf '使用 Shark 分析堆...\n'
analysis_output="${work_dir}/shark-analysis.txt"
if ! "$shark_cli" --hprof "$local_hprof" analyze >"$analysis_output" 2>&1; then
    cat "$analysis_output" >&2
    die 'Shark 堆分析失败。'
fi

if ! grep -q 'HEAP ANALYSIS RESULT' "$analysis_output"; then
    cat "$analysis_output" >&2
    die 'Shark 输出中没有分析结果。'
fi

application_leaks="$(
    awk '$2 == "APPLICATION" && $3 == "LEAKS" { print $1; exit }' "$analysis_output"
)"
library_leaks="$(
    awk '$2 == "LIBRARY" && $3 == "LEAKS" { print $1; exit }' "$analysis_output"
)"
application_leaks="${application_leaks:-0}"
library_leaks="${library_leaks:-0}"
total_leaks=$((application_leaks + library_leaks))

printf 'Shark 分析结果: Application leaks=%s, Library leaks=%s\n' \
    "$application_leaks" "$library_leaks"

if [ "$total_leaks" -eq 0 ]; then
    printf '未发现内存泄漏，不生成报告。\n'
    exit 0
fi

device_manufacturer="$(adb shell getprop ro.product.manufacturer | tr -d '\r')"
device_model="$(adb shell getprop ro.product.model | tr -d '\r')"
android_release="$(adb shell getprop ro.build.version.release | tr -d '\r')"
android_sdk="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
device_serial="$(adb get-serialno | tr -d '\r')"
generated_at="$(date '+%Y-%m-%d %H:%M:%S %Z')"

report_tmp="${report_file}.tmp"
{
    printf '# Android 应用内存泄漏报告\n\n'
    printf -- '- 应用包名：`%s`\n' "$app_package"
    printf -- '- 设备：%s %s\n' "$device_manufacturer" "$device_model"
    printf -- '- Android 版本：%s（SDK %s）\n' "$android_release" "$android_sdk"
    printf -- '- 设备序列号：`%s`\n' "$device_serial"
    printf -- '- 检测时间：%s\n' "$generated_at"
    printf -- '- Application leaks：%s\n' "$application_leaks"
    printf -- '- Library leaks：%s\n' "$library_leaks"
    printf -- '- 泄漏总数：%s\n\n' "$total_leaks"
    printf 'Monkey 测试结束后，已关闭 App 页面并返回桌面，确认 App 进程仍在运行，'
    printf '随后强制 GC 并 dump Java 堆。由 Square Shark CLI 分析堆，'
    printf '原始 hprof 文件未归档。\n\n'
    printf '## Shark 分析结果\n\n'
    printf '```text\n'
    cat "$analysis_output"
    printf '```\n'
} >"$report_tmp"
mv "$report_tmp" "$report_file"

printf '发现内存泄漏，测试报告已生成: %s\n' "$report_file"
