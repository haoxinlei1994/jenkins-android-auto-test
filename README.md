# Jenkins Android 自动化测试

本项目在本机 Docker 中运行 Jenkins，通过宿主机上的 ADB Server 操作 USB 连接的 Android 设备，执行 Monkey 测试。测试结束后会关闭 App 页面、dump Java 堆，并使用 Square Shark 分析内存泄漏；**只有检测到泄漏时才生成测试报告**。

本项目只负责测试，不负责：

- 安装 APK；
- 归档 logcat 或普通测试日志；
- 管理 Android 应用源码。

待测应用需要提前安装到设备上。

## 工作方式

```text
宿主机（macOS / Linux）
├── USB 连接的 Android 设备
├── 宿主机 ADB Server：0.0.0.0:5037（使用 -a 监听所有接口）
└── Docker
    └── Jenkins 容器：http://localhost:8080
        ├── 通过 ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 操作设备
        └── 执行 Jenkinsfile -> scripts/check_adb.sh -> scripts/monkey_test.sh
```

Docker Desktop for macOS 无法直接把 USB 设备透传给容器，所以采用下面的模式：

1. 手机通过 USB 连接宿主机；
2. 宿主机运行 ADB Server；
3. 容器内的 adb 客户端通过网络连接宿主机 ADB Server，再操作手机。

Jenkins 的工作区会挂载在宿主机的 `./jenkins_home/workspace/<任务名>/`。

## 前置条件

- Docker Desktop（macOS）或 Docker Engine + Compose v2；
- 宿主机安装 Android platform-tools，能执行 `adb`；
- Git；
- `openssl`（首次生成 Jenkins 管理员密码时使用）；
- 手机已开启开发者选项和 USB 调试，并已授权当前电脑；
- 待测 App 已安装在手机上；
- 只有一台处于 `device` 状态的设备；
- Jenkins 容器构建和拉取代码时需要能访问 Docker Hub、GitHub、Jenkins 插件更新中心，以及下载 platform-tools 使用的 `dl.google.com`。

检查 Docker 和 adb：

```bash
docker compose version
adb version
adb devices -l
```

如果使用 Apple Silicon，镜像会以 `linux/amd64` 运行，首次构建可能较慢。

## 从零启动 Jenkins

### 1. 克隆项目

```bash
git clone https://github.com/haoxinlei1994/jenkins-android-auto-test.git
cd jenkins-android-auto-test
```

如果使用自己的 fork，请把仓库地址换成自己的地址。后面配置 Jenkins Pipeline 时，也要使用同一个仓库地址。

### 2. 连接并检查手机

```bash
adb devices -l
```

正常应看到类似输出：

```text
List of devices attached
<设备序列号>    device
```

如果状态是 `unauthorized`，请在手机上确认 USB 调试授权；如果有多个设备，请先断开其他设备，本项目只支持一台可用设备。

确认待测 App 已安装：

```bash
adb shell pm list packages | grep <应用包名>
```

### 3. 一键启动

在项目根目录执行：

```bash
bash scripts/start.sh
```

脚本会依次完成：

1. 读取宿主机 `adb version`，把 platform-tools 版本写入 `.env`；
2. 首次安装时生成 Jenkins 管理员用户名和密码，写入 `.env`；
3. 后台重启宿主机 ADB Server，使用 `-a` 监听，日志在 `/tmp/adb-server.log`；
4. 执行 `docker compose up -d --build --wait --wait-timeout 300`，构建并启动 Jenkins；
5. 输出 Jenkins 地址和管理员登录凭据。

首次启动需要下载 Jenkins 基础镜像、插件、platform-tools 和 Shark，可能需要几分钟。

启动成功后，终端会输出类似：

```text
Jenkins 已启动：http://localhost:8080
用户名: admin
登录密码: <自动生成的密码>
凭据文件: /path/to/jenkins-android-auto-test/.env
```

管理员凭据由 `scripts/generate_jenkins_credentials.sh` 生成，并由 Jenkins 启动时的 `jenkins/init.groovy.d/10-create-admin.groovy` 创建账号。

> `jenkins_home/secrets/initialAdminPassword` 不是这里的登录密码。它只在全新 Jenkins 的 setup wizard 中使用，而本项目的 setup wizard 已关闭。

如果复用了一个已经初始化过的 `jenkins_home`，初始化脚本检测到已有安全域后会跳过，不会重置已有用户密码。此时请使用已有账号登录；`.env` 中可能没有自动生成的凭据。

### 4. 登录 Jenkins

打开：

```text
http://localhost:8080
```

使用上一步输出的用户名和密码登录。插件已经在镜像中预装，不需要再进入“插件管理”手动安装。

### 5. 在 Jenkins 页面创建 Pipeline

1. 点击 **新建任务（New Item）**；
2. 输入任务名，例如 `android-auto-test`；
3. 选择 **流水线（Pipeline）**，点击 **确定（OK）**；
4. 在任务配置页找到 **流水线（Pipeline）** 区域；
5. **定义（Definition）** 选择 **Pipeline script from SCM**；
6. **SCM** 选择 **Git**；
7. **Repository URL** 填写本项目的 GitHub 地址，例如：

   ```text
   https://github.com/haoxinlei1994/jenkins-android-auto-test.git
   ```

   注意：这里必须填写 Jenkins 容器能够访问的 Git 地址，不要填写宿主机的本地路径。

8. 公开仓库的 **Credentials** 保持 `- none -`；私有仓库需要先在 Jenkins 中配置 Git 凭据并选中；
9. **Branches to build / 分支** 填写：

   ```text
   */master
   ```

   如果你的 fork 使用 `main` 分支，则填写 `*/main`；
10. **必须取消勾选 Lightweight checkout（轻量级检出）**；
11. **Script Path / 脚本路径** 保持 `Jenkinsfile`；
12. 点击 **保存（Save）**。

#### 为什么必须取消 Lightweight checkout

如果勾选轻量级检出，Jenkins 只会读取 `Jenkinsfile`，不会把整个仓库检出到工作区，流水线执行到：

```text
bash scripts/check_adb.sh
```

时会因为找不到 `scripts/` 而失败。取消勾选后，Jenkins 会在构建开始时完整检出仓库，工作区根目录同时包含 `Jenkinsfile` 和 `scripts/`，因此 `Jenkinsfile` 中不需要再写一次 `git clone`。

### 6. 执行构建

在任务页面点击 **Build Now / 立即构建**。

构建过程：

1. **准备并检查 ADB 连接**：确认容器能连接宿主机 ADB Server，并且恰好有一台可用设备；
2. **Monkey 与内存泄漏测试**：解锁屏幕、启动 App、执行 Monkey，然后关闭 App 页面、dump 堆并分析。

在构建详情页点击 **Console Output / 控制台输出** 可以查看完整执行日志。

Jenkins 工作区位置：

```text
宿主机：./jenkins_home/workspace/android-auto-test/
容器内：/var/jenkins_home/workspace/android-auto-test/
```

## 配置待测应用和测试参数

直接修改 `scripts/monkey_test.sh`：

```bash
app_package='com.rollydrop.app'

# 启动应用
adb shell monkey -p "$app_package" -c android.intent.category.LAUNCHER 1

# Monkey 测试：--throttle 30 1000 表示事件间隔 30ms、共 1000 个事件
adb shell monkey -p "$app_package" --throttle 30 1000
```

需要修改的内容：

- `app_package` 改成待测应用的真实包名；
- 按需修改 Monkey 的事件数量和 `--throttle`；
- 修改完成后提交并推送到 Jenkins 使用的分支。

Jenkins 构建时拉取的是远程仓库，不是宿主机当前工作目录。只在本地修改而不 push，Jenkins 不会使用这些修改。

测试前还需要确认：

- App 已经安装在设备上；
- App 有可用的 Launcher Activity，`monkey -c android.intent.category.LAUNCHER` 能启动它；
- 内存泄漏检测需要能对 App 执行 `am dumpheap`，因此 App 通常需要是 debuggable 版本，或设备具备相应权限；
- 如果手机设置了锁屏密码，脚本无法解锁，需要手动解锁后再执行构建；
- 不要在测试过程中断开 USB 或切换设备。

## 测试流程说明

### ADB 检查

`scripts/check_adb.sh` 会：

- 读取 `ADB_SERVER_SOCKET`；
- 检查容器内 adb 是否可用；
- 检查容器内 adb 与宿主机 ADB Server 的版本是否一致；
- 检查是否有且仅有一台 `device` 状态的设备；
- 输出设备型号、Android 版本和 SDK 版本；
- 成功时通过 stdout 返回设备序列号。

如果检测到多台可用设备，脚本会直接失败，避免在错误设备上执行测试。

### Monkey 测试

`scripts/monkey_test.sh` 会：

1. 点亮屏幕并尝试关闭无密码锁屏；
2. 启动待测 App；
3. 执行 Monkey；
4. 调用 `scripts/memory_leak_test.sh` 进行内存泄漏检测。

### 内存泄漏检测

`scripts/memory_leak_test.sh` 会：

1. 连续发送返回键，关闭 App 页面并回到桌面；
2. 确认 App 进程仍然存在；
3. 使用 `am dumpheap -g` dump Java 堆；
4. 把堆文件拉回 Jenkins 工作区临时目录；
5. 使用 Shark CLI 分析；
6. 只有在检测到 Application 或 Library 泄漏时生成：

   ```text
   reports/memory-leak-report.md
   ```

7. 原始 hprof 文件不归档，分析结束后删除。

如果连续返回 50 次仍未回到桌面，或者 App 进程已经不存在，检测会失败，不会生成报告。

## 测试报告和构建产物

如果没有检测到内存泄漏：

- 不生成 `reports/memory-leak-report.md`；
- Jenkins 的 `archiveArtifacts` 允许空产物，构建仍然可以成功。

如果检测到内存泄漏：

- 报告生成在 Jenkins 工作区的 `reports/memory-leak-report.md`；
- Jenkins 在 **Build Artifacts / 构建产物** 中归档该文件；
- 报告包含应用包名、设备信息、Android 版本、设备序列号、检测时间、泄漏数量和 Shark 原始分析结果。

报告不会因为下一次构建而覆盖历史构建的归档副本；每个构建都有自己的一份构建产物。工作区中的 `reports/memory-leak-report.md` 会在下一次构建开始时删除，避免失败构建误归档旧报告。

Jenkins 保留最近 30 次构建和对应产物。

## 目录结构

```text
.
├── Dockerfile                              # Jenkins、adb、Shark、插件环境
├── compose.yaml                            # Jenkins 服务、端口、挂载和 ADB 配置
├── plugins.txt                             # 固定版本的 Jenkins 插件
├── Jenkinsfile                             # 流水线定义
├── jenkins/
│   └── init.groovy.d/
│       └── 10-create-admin.groovy          # 首次启动时初始化管理员
├── scripts/
│   ├── start.sh                            # 一键启动入口
│   ├── common.sh                           # 公共变量和函数
│   ├── sync_adb_version.sh                 # 同步宿主机 adb 版本到 .env
│   ├── generate_jenkins_credentials.sh     # 生成管理员凭据
│   ├── restart_adb_server.sh               # 重启宿主机 ADB Server
│   ├── start_jenkins.sh                    # 构建并启动 Jenkins 容器
│   ├── show_jenkins_credentials.sh         # 输出访问地址和登录凭据
│   ├── check_adb.sh                        # 检查 ADB 连接和设备
│   ├── monkey_test.sh                      # 启动 App 并执行 Monkey
│   └── memory_leak_test.sh                 # dump 堆并用 Shark 分析
├── jenkins_home/                           # 运行时生成，已 gitignore
├── reports/                                # 运行时生成，已 gitignore
├── .env                                    # 运行时生成，已 gitignore
└── README.md
```

`.env`、`jenkins_home/` 和 `reports/` 不要提交到 Git。`.env` 中包含 Jenkins 管理员密码，`jenkins_home/` 中包含 Jenkins 用户、任务、插件和构建数据。

## 常用操作

查看 Jenkins 日志：

```bash
docker logs -f jenkins-android-auto-test
```

查看宿主机 ADB Server 日志：

```bash
tail -f /tmp/adb-server.log
```

停止 Jenkins 容器：

```bash
docker compose down
```

停止不会删除 `jenkins_home` 中的数据；再次执行 `bash scripts/start.sh` 即可恢复。

宿主机重启后，Docker 容器可能会自动启动，但宿主机 ADB Server 不会自动恢复，需要重新执行：

```bash
bash scripts/start.sh
```

如果修改了 `Dockerfile`、`compose.yaml`、`plugins.txt` 或需要同步宿主机 adb 版本，也执行 `bash scripts/start.sh` 重新构建。

如果只修改了 `Jenkinsfile` 或测试脚本，提交并 push 后，在 Jenkins 重新构建即可，不必重建容器。

需要更换宿主机端口时：

```bash
JENKINS_PORT=8081 bash scripts/start.sh
```

然后访问 `http://localhost:8081`。

## 分步执行

排查问题时，可以单独执行 `start.sh` 中的各个步骤：

```bash
bash scripts/sync_adb_version.sh
bash scripts/generate_jenkins_credentials.sh
bash scripts/restart_adb_server.sh
bash scripts/start_jenkins.sh
bash scripts/show_jenkins_credentials.sh
```

`scripts/start_jenkins.sh` 依赖 `.env` 中的 `PLATFORM_TOOLS_VERSION`，所以请先执行 `sync_adb_version.sh`，或者直接使用一键启动脚本。

## 故障排查

### 页面提示找不到自动生成的管理员凭据

说明当前已存在 Jenkins 用户，或者 `.env` 中没有 `JENKINS_ADMIN_USER` / `JENKINS_ADMIN_PASSWORD`。这通常发生在复用旧的 `jenkins_home` 时：

- 使用已有 Jenkins 账号登录；
- `initialAdminPassword` 不能恢复已有账号的密码；
- 如果这是本地测试环境且不需要旧数据，可以停止容器、备份并移走 `jenkins_home`，再执行 `bash scripts/start.sh`，让 Jenkins 重新初始化。此操作会丢失旧任务和构建数据。

### 找不到 scripts/check_adb.sh

检查 Pipeline 配置：

- 定义必须是 `Pipeline script from SCM`；
- 必须取消勾选 `Lightweight checkout`；
- `Script Path` 必须是 `Jenkinsfile`；
- 分支必须是包含这些脚本的分支。

### 没有发现 Android 设备

在宿主机执行：

```bash
adb devices -l
```

检查 USB 连接、开发者选项和 USB 调试授权。设备状态必须是 `device`，不能是 `unauthorized` 或 `offline`。

### 容器无法连接 ADB Server

确认宿主机 ADB Server 正在运行：

```bash
bash scripts/restart_adb_server.sh
tail -n 50 /tmp/adb-server.log
```

容器默认通过 `tcp:host.docker.internal:5037` 连接宿主机。Linux 下 `compose.yaml` 已通过 `host-gateway` 处理 `host.docker.internal`。

### ADB 版本不一致

如果流水线提示容器内 adb 与宿主机 ADB Server 版本不一致，在宿主机重新执行：

```bash
bash scripts/start.sh
```

脚本会重新读取宿主机 adb 版本并重建镜像，不需要单独升级容器内的 adb。

### 出现 INJECT_EVENTS / SecurityException

部分手机（例如 MIUI）需要在开发者选项中额外开启“USB 调试（安全设置）”或类似选项，否则 `input keyevent` 等操作会被拒绝。开启后重新连接 USB，并重新执行：

```bash
bash scripts/restart_adb_server.sh
```

### 无法 dump 堆

`am dumpheap` 对非 debuggable 应用可能没有权限。请使用 debug 版本的应用，或在具备相应权限的设备上测试。同时确认关闭页面后 App 进程仍然存在。

### 8080 端口被占用

使用其他宿主机端口启动：

```bash
JENKINS_PORT=8081 bash scripts/start.sh
```

## 安全与限制

- `adb -a` 会让 ADB Server 监听所有网络接口，只应在可信网络中使用，不要暴露到公网；
- Jenkins 默认只用于本地开发，不要直接把 8080 端口暴露到公网；
- `.env` 中包含管理员密码，已被 `.gitignore` 忽略，请勿提交或分享；
- 本项目只支持一台设备，并通过 `disableConcurrentBuilds()` 禁止同一任务并发构建；
- 本项目的流水线不安装 APK；待测应用必须已经安装在设备上；
- 不归档普通日志，只归档发现内存泄漏时生成的报告；
- 手机通过 USB 连接宿主机，Jenkins 容器通过宿主机 ADB Server 操作设备，因此运行构建时宿主机和手机必须保持连接。
