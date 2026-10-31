#!/usr/bin/env bash
set -oue pipefail

# ==============================================================================
# 1. 动态解析并安装 GitHub 最新版 Clash Verge Rev
# ==============================================================================
echo "==> 正在精准解析 GitHub 最新版 Clash Verge..."
FINAL_URL=$(curl -sfSL -o /dev/null -w '%{url_effective}' https://github.com/clash-verge-rev/clash-verge-rev/releases/latest)
TAG="${FINAL_URL##*/}"
VER="${TAG#v}"

if [ -z "${FINAL_URL}" ] || [ "${TAG}" = "latest" ] || [ -z "${VER}" ]; then
    echo "==> 错误: 无法解析 Clash Verge 最新发布版本，请检查网络或 GitHub 状态。"
    exit 1
fi

CLASH_RPM="https://github.com/clash-verge-rev/clash-verge-rev/releases/download/${TAG}/Clash.Verge-${VER}-1.x86_64.rpm"
echo "==> 检测到最新版本 [${VER}]，开始通过 dnf 安装: ${CLASH_RPM}"
dnf install -y "${CLASH_RPM}"
dnf clean all

# ==============================================================================
# 2. 动态解析并缓存最新版 OpenCode V2 至 /usr/share/ublue-os/my-brew/opencode
#    （由首登脚本安装至用户可写目录 ~/.local/bin/opencode，支持本地随时升级或卸载）
# ==============================================================================
echo "==> 正在从 anomalyco/homebrew-tap 解析并缓存最新版 OpenCode V2..."
OPENCODE_URL=$(curl -sfSL https://raw.githubusercontent.com/anomalyco/homebrew-tap/HEAD/opencode-v2.rb | grep -Eo 'https://[^"]+opencode-linux-x64[^"]+\.tar\.gz' | head -n 1)
if [ -n "${OPENCODE_URL}" ]; then
    echo "==> 下载 OpenCode V2: ${OPENCODE_URL}"
    mkdir -p /usr/share/ublue-os/my-brew
    curl -sfSL "${OPENCODE_URL}" -o /tmp/opencode.tar.gz
    tar -xzf /tmp/opencode.tar.gz -C /usr/share/ublue-os/my-brew opencode
    chmod 755 /usr/share/ublue-os/my-brew/opencode
    rm -f /tmp/opencode.tar.gz
    echo "==> OpenCode V2 已成功缓存至 /usr/share/ublue-os/my-brew/opencode！"
else
    echo "==> 错误: 未能解析到 OpenCode V2 下载地址"
    exit 1
fi

# ==============================================================================
# 3. 预置官方最新雾凇拼音词库（Rime-ICE）至 /usr/share/ublue-os/rime-ice
# ==============================================================================
echo "==> 正在拉取官方最新的雾凇拼音（Rime-ICE）并打包到系统模板中..."
mkdir -p /usr/share/ublue-os/rime-ice
git clone --depth 1 https://github.com/iDvel/rime-ice.git /tmp/rime-ice
cp -r /tmp/rime-ice/* /usr/share/ublue-os/rime-ice/
rm -rf /tmp/rime-ice

# ==============================================================================
# 4. 预置 GNOME 官方最新版 Kimpanel 输入法面板扩展至系统扩展目录
# ==============================================================================
echo "==> 正在精准获取 GNOME 官方最新版 Kimpanel 扩展..."
UUID="kimpanel@kde.org"
VERSION_TAG=$(curl -sSL "https://extensions.gnome.org/extension-query/?search=${UUID}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for ext in data.get("extensions", []):
        if ext.get("uuid") == "kimpanel@kde.org":
            print(max(x["pk"] for x in ext["shell_version_map"].values()))
            sys.exit(0)
except Exception:
    pass
' 2>/dev/null || true)

if [ -n "${VERSION_TAG}" ]; then
    echo "==> 成功解析到 Kimpanel 最新版本 tag: [${VERSION_TAG}]，正在下载..."
    mkdir -p /usr/share/gnome-shell/extensions/kimpanel@kde.org
    curl -sSL "https://extensions.gnome.org/download-extension/${UUID}.shell-extension.zip?version_tag=${VERSION_TAG}" -o /tmp/kimpanel.zip
    unzip -qo /tmp/kimpanel.zip -d /usr/share/gnome-shell/extensions/kimpanel@kde.org/
    rm -f /tmp/kimpanel.zip
    sed -i 's/"shell-version": \[/"shell-version": ["44", "45", "46", "47", "48", "49", "50", /g' /usr/share/gnome-shell/extensions/kimpanel@kde.org/metadata.json 2>/dev/null || true
    chmod -R a+rX /usr/share/gnome-shell/extensions/kimpanel@kde.org/
    glib-compile-schemas /usr/share/gnome-shell/extensions/kimpanel@kde.org/schemas/ 2>/dev/null || true
    echo "==> Kimpanel 官方扩展已成功预置到 /usr/share/gnome-shell/extensions/kimpanel@kde.org"
else
    echo "==> 警告: 无法从 GNOME Extensions API 解析到版本 tag，跳过在线下载"
fi

# ==============================================================================
# 5. 动态解析并安装最新版 Google Antigravity IDE (Linux x64)
# ==============================================================================
echo "==> 正在精准解析 Google 官方最新版 Antigravity IDE..."
# 优先从官网下载页动态抓取最新的更新接口，若异常则回落至默认已知接口
UPDATER_API=$(curl -sfSL "https://antigravity.google/download" | grep -Eo 'https://[a-zA-Z0-9.-]+\.run\.app/releases' | head -n 1)
UPDATER_API="${UPDATER_API:-https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/releases}"

RELEASE_INFO=$(curl -sfSL "${UPDATER_API}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    latest = data[0]
    print(f"{latest[\"version\"]}-{latest[\"execution_id\"]}")
except Exception:
    pass
' 2>/dev/null || true)

if [ -n "${RELEASE_INFO}" ]; then
    DOWNLOAD_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${RELEASE_INFO}/linux-x64/Antigravity.tar.gz"
    echo "==> 检测到最新版本 [${RELEASE_INFO}]，开始下载并安装至 /opt/antigravity: ${DOWNLOAD_URL}"
    mkdir -p /opt/antigravity
    curl -sfSL "${DOWNLOAD_URL}" -o /tmp/Antigravity.tar.gz
    tar -xzf /tmp/Antigravity.tar.gz -C /opt/antigravity --strip-components=1
    rm -f /tmp/Antigravity.tar.gz
    ln -sf /opt/antigravity/antigravity /usr/bin/antigravity
    chmod 755 /usr/bin/antigravity
    echo "==> Antigravity IDE [${RELEASE_INFO}] 已成功部署至 /opt/antigravity 并软链至 /usr/bin/antigravity！"
else
    echo "==> 警告: 无法解析 Antigravity 最新发布版本，跳过在线下载"
fi
