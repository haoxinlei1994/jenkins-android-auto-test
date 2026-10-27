# Jenkins + Android 自动化测试环境
#
# 说明：
# - macOS 上的 Docker Desktop 无法直接透传 USB 设备，因此容器内只运行 adb 客户端，
#   通过 ADB_SERVER_SOCKET 连接宿主机上监听 5037 端口的 ADB Server。
# - 宿主机需先执行：adb -a nodaemon server
# - 宿主机与容器内的 adb（platform-tools）版本应保持一致，避免 ADB Server 版本不匹配。
# - 官方 Linux platform-tools 仅提供 x86_64 包；Apple Silicon 上请使用
#   `docker build --platform linux/amd64` 构建（通过模拟执行）。
FROM jenkins/jenkins:2.580.1-lts-jdk21

ARG TARGETARCH
ARG PLATFORM_TOOLS_VERSION=37.0.1
ARG ANDROID_SDK_ROOT=/opt/android-sdk

USER root

# GOOGLE 官方 Linux platform-tools 仅提供 x86_64 版本
RUN if [ "${TARGETARCH}" != "amd64" ]; then \
        echo "ERROR: platform-tools Linux 包仅支持 x86_64，当前 TARGETARCH=${TARGETARCH}。请使用 --platform linux/amd64 构建。" >&2; \
        exit 1; \
    fi

ENV ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}" \
    ANDROID_HOME="${ANDROID_SDK_ROOT}"
ENV PATH="${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

# ADB 连接宿主机上的 ADB Server；运行时可通过 -e / compose environment 覆盖
ENV ADB_SERVER_SOCKET="tcp:host.docker.internal:5037"

# git：拉取被测代码；curl/unzip：安装 platform-tools；openssh-client：支持 SSH 方式 Git
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        openssh-client \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# 安装 adb（platform-tools）
RUN set -eux; \
    mkdir -p "${ANDROID_SDK_ROOT}"; \
    curl -fsSL --retry 3 --retry-delay 2 \
        "https://dl.google.com/android/repository/platform-tools_r${PLATFORM_TOOLS_VERSION}-linux.zip" \
        -o /tmp/platform-tools.zip; \
    unzip -q /tmp/platform-tools.zip -d "${ANDROID_SDK_ROOT}"; \
    rm -f /tmp/platform-tools.zip; \
    chmod -R a+rX "${ANDROID_SDK_ROOT}"; \
    adb version; \
    git --version

# 安装固定版本的 Jenkins 插件；plugins.txt 为空或只有注释时跳过
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN if [ -s /usr/share/jenkins/ref/plugins.txt ] \
        && grep -qEv '^[[:space:]]*(#|$)' /usr/share/jenkins/ref/plugins.txt; then \
        jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt; \
    fi

USER jenkins

EXPOSE 8080 50000
