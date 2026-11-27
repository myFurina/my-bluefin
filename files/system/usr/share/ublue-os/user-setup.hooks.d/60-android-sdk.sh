#!/usr/bin/env bash
# ==============================================================================
# My-Bluefin Android SDK 用户空间离线秒装初始化钩子
# - 构建期已将 cmdline-tools、licenses、platform-tools、android-36 预缓存于系统
# - 首登仅本地复制至可写 ~/Android/Sdk（0 网络、0 代理依赖），秒级完成
# - 防复活机制：一旦初始化成功（或用户主动清理），后续登录永久跳过
# - 自动生成兼容 Gradle 8.5+/9.x 的 mirrors.gradle（阿里云优先 + 官方兜底）
# ==============================================================================
set -euo pipefail

# 0. 仅对普通真实用户执行，跳过 gdm、gdm-greeter 等系统与登录器会话
[ "$(id -u)" -lt 1000 ] && exit 0
[ "${XDG_SESSION_CLASS:-}" = "greeter" ] && exit 0
case "$(id -u -n 2>/dev/null)" in
    gdm|gdm-greeter|gnome-initial-setup) exit 0 ;;
esac

TEMPLATE_DIR="/usr/share/ublue-os/android-sdk"
[ -x "${TEMPLATE_DIR}/cmdline-tools/latest/bin/sdkmanager" ] || exit 0

mkdir -p "$HOME/.local/state"

# 1. 快速前置检测（耗时 < 1ms）：防复活保障
# 只要存在初始化完成标记（含 ujust android-clean --all 留存的标记），即不再重复部署
DONE_FLAG="$HOME/.local/state/.android-sdk-init-done"
if [ -z "${MY_BLUEFIN_ANDROID_FOREGROUND:-}" ] && [ -f "${DONE_FLAG}" ]; then
    exit 0
fi

# 2. 若非前台模式且尚未切入后台 worker，通过 systemd-run 启动独立瞬态用户服务异步执行
if [ -z "${MY_BLUEFIN_ANDROID_FOREGROUND:-}" ] && [ -z "${MY_BLUEFIN_ANDROID_BG_WORKER:-}" ]; then
    if command -v systemd-run >/dev/null 2>&1; then
        if systemd-run --user --no-block --collect --unit=my-bluefin-android-setup \
            --setenv=MY_BLUEFIN_ANDROID_BG_WORKER=1 "$0" >/dev/null 2>&1; then
            exit 0
        fi
    fi
fi

write_gradle_mirrors() {
    local gradle_init_dir="$HOME/.gradle/init.d"
    local mirrors_file="${gradle_init_dir}/mirrors.gradle"
    mkdir -p "${gradle_init_dir}"

    if [ -f "${mirrors_file}" ]; then
        return 0
    fi

    cat << 'EOF' > "${mirrors_file}"
import java.net.URI
import org.gradle.api.initialization.resolve.RepositoriesMode

def prependMirrors = { handler, boolean includePluginPortal ->
    def existing = handler.toList()
    handler.clear()

    if (includePluginPortal) {
        handler.maven { url = URI.create("https://maven.aliyun.com/repository/gradle-plugin") }
    }
    handler.maven { url = URI.create("https://maven.aliyun.com/repository/google") }
    handler.maven { url = URI.create("https://maven.aliyun.com/repository/public") }
    handler.maven { url = URI.create("https://maven.aliyun.com/repository/central") }

    existing.each { repo ->
        handler.add(repo)
    }

    // 保留官方源作为兜底 fallback，防止阿里云镜像同步延迟导致新库拉取失败
    if (includePluginPortal && !existing.any { it.name == "Gradle Central Plugin Repository" }) {
        handler.gradlePluginPortal()
    }
    if (!existing.any { it.name == "Google" }) {
        handler.google()
    }
    if (!existing.any { it.name == "MavenRepo" }) {
        handler.mavenCentral()
    }
}

boolean allowProjectRepos = true

gradle.settingsEvaluated { settings ->
    prependMirrors(settings.pluginManagement.repositories, true)

    def drm = settings.dependencyResolutionManagement
    if (drm.repositoriesMode.getOrNull() == RepositoriesMode.FAIL_ON_PROJECT_REPOS) {
        allowProjectRepos = false
    }
    if (!drm.repositories.isEmpty()) {
        prependMirrors(drm.repositories, false)
    }
}

gradle.beforeProject { proj ->
    proj.buildscript.repositories.maven { url = URI.create("https://maven.aliyun.com/repository/google") }
    proj.buildscript.repositories.maven { url = URI.create("https://maven.aliyun.com/repository/public") }
    proj.buildscript.repositories.maven { url = URI.create("https://maven.aliyun.com/repository/central") }

    proj.afterEvaluate {
        if (allowProjectRepos && !proj.repositories.isEmpty()) {
            prependMirrors(proj.repositories, false)
        }
    }
}
EOF
    chmod 644 "${mirrors_file}"
}

run_android_worker() {
    local lock_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/my-bluefin-android-${UID}.lock"
    mkdir -p "$(dirname "${lock_file}")"
    exec 203>"${lock_file}"
    if ! flock -n 203; then
        echo "==> 已有 Android SDK 初始化任务正在运行，本次跳过。"
        exit 0
    fi

    if [ -z "${MY_BLUEFIN_ANDROID_FOREGROUND:-}" ]; then
        exec >>"$HOME/.local/state/android-sdk-setup.log" 2>&1
    fi

    export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
    export ANDROID_SDK_ROOT="${ANDROID_HOME}"

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 开始离线部署 Android 16 (API 36) SDK 环境..."

    # 1. 从系统离线预缓存模板增量复制到用户可写目录 $ANDROID_HOME（不覆盖用户已自行安装的额外 SDK/NDK）
    mkdir -p "${ANDROID_HOME}"
    if [ -n "${MY_BLUEFIN_ANDROID_FOREGROUND:-}" ] || \
       [ ! -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ] || \
       [ ! -d "${ANDROID_HOME}/licenses" ] || \
       [ ! -d "${ANDROID_HOME}/platform-tools" ] || \
       [ ! -d "${ANDROID_HOME}/platforms/android-36" ] || \
       [ ! -d "${ANDROID_HOME}/build-tools/36.0.0" ]; then
        echo "==> 正在从系统离线模板复制 SDK 至 ${ANDROID_HOME}..."
        cp -rn "${TEMPLATE_DIR}/." "${ANDROID_HOME}/"
        chmod -R u+rwX "${ANDROID_HOME}"
        chmod 755 "${ANDROID_HOME}/cmdline-tools/latest/bin/"*
    fi

    # 2. 注入 Gradle 阿里云优先 + 官方兜底镜像配置
    write_gradle_mirrors

    if [ -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ] && \
       [ -d "${ANDROID_HOME}/platform-tools" ] && \
       [ -d "${ANDROID_HOME}/platforms/android-36" ] && \
       [ -d "${ANDROID_HOME}/build-tools/36.0.0" ]; then
        touch "${DONE_FLAG}"
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] ✔ Android 16 (API 36) SDK 环境已离线秒级就绪: ${ANDROID_HOME}"
    else
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] ✖ SDK 目录校验未通过，未写入完成标志。"
        exit 1
    fi
}

if [ -n "${MY_BLUEFIN_ANDROID_FOREGROUND:-}" ] || [ -n "${MY_BLUEFIN_ANDROID_BG_WORKER:-}" ]; then
    run_android_worker
else
    run_android_worker &
fi
