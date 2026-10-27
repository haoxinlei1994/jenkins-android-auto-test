# Jenkins Android 自动化测试

通过 USB 连接 Android 设备，由 Jenkins 自动安装并启动 App、执行 Monkey 测试，收集日志并归档测试产物。

> 当前状态：工程骨架已生成，代码与配置内容待补充。

## 目录结构

```text
.
├── Dockerfile          # 定义 Jenkins 软件环境
├── compose.yaml        # 定义 Jenkins 如何启动
├── plugins.txt         # 固定 Jenkins 插件版本
├── Jenkinsfile         # 定义自动化测试流程
├── scripts/
│   └── monkey_test.sh  # 执行 Monkey 测试
├── config/
│   └── test.yaml       # 测试参数
└── README.md           # 部署说明
```

## 预期测试流程

1. 检查 ADB 设备是否在线
2. 安装并启动待测 App
3. 执行 Monkey 测试
4. 收集 logcat、Monkey 输出、截图等测试产物
5. 生成测试报告并由 Jenkins 归档

## 环境说明（macOS + Docker）

- 宿主已安装 `adb`（1.0.40），当前未检测到已连接的设备。
- Docker Desktop for macOS 无法将宿主 USB 设备直接透传给容器，建议：
  1. 在 macOS 宿主机启动 ADB Server：`adb -a nodaemon server`
  2. 容器内设置 `ADB_SERVER_SOCKET=tcp:host.docker.internal:5037`，通过宿主机的 ADB Server 操作 USB 设备。
- `adb -a` 会监听所有网络接口，请仅在可信网络中使用，并配合防火墙限制访问。
- 测试前确保手机已开启开发者选项与 USB 调试，并已授权本机。

## 待补充

- `Dockerfile`：Jenkins + JDK + Android SDK platform-tools 等运行环境
- `compose.yaml`：Jenkins 服务、端口、数据卷及 ADB 连接配置
- `plugins.txt`：Jenkins 插件及固定版本
- `Jenkinsfile`：构建流程、调用测试脚本、归档日志与报告
- `scripts/monkey_test.sh`：设备检查、安装/启动 App、Monkey 测试与日志收集
- `config/test.yaml`：包名、APK 路径、设备序列号、Monkey 参数等
