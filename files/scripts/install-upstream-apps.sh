#!/usr/bin/env bash
set -oue pipefail

# ==============================================================================
# 1. 动态解析并安装 GitHub 最新版 Clash Verge Rev
# ==============================================================================
echo "==> 正在精准解析 GitHub 最新版 Clash Verge..."
FINAL_URL=$(curl -sfSL --connect-timeout 15 --retry 3 -o /dev/null -w '%{url_effective}' https://github.com/clash-verge-rev/clash-verge-rev/releases/latest)
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
OPENCODE_URL=$(curl -sfSL --connect-timeout 15 --retry 3 https://raw.githubusercontent.com/anomalyco/homebrew-tap/HEAD/opencode-v2.rb | grep -Eo 'https://[^"]+opencode-linux-x64[^"]+\.tar\.gz' | head -n 1)
if [ -n "${OPENCODE_URL}" ]; then
    echo "==> 下载 OpenCode V2: ${OPENCODE_URL}"
    mkdir -p /usr/share/ublue-os/my-brew
    curl -sfSL --connect-timeout 15 --retry 3 "${OPENCODE_URL}" -o /tmp/opencode.tar.gz
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
# 4. 预置与当前系统 GNOME 版本精准匹配的官方 Kimpanel 扩展
# ==============================================================================
echo "==> 正在精准获取与当前系统 GNOME 版本相匹配的官方 Kimpanel 扩展..."
UUID="kimpanel@kde.org"
SYSTEM_GNOME_VER=$(gnome-shell --version 2>/dev/null | grep -Eo '[0-9]+' | head -n 1 || echo "50")

VERSION_TAG=$(curl -sSL --connect-timeout 15 --retry 3 "https://extensions.gnome.org/extension-query/?search=${UUID}" | python3 -c '
import sys, json
target_ver = sys.argv[1] if len(sys.argv) > 1 else "50"
try:
    data = json.load(sys.stdin)
    for ext in data.get("extensions", []):
        if ext.get("uuid") == "kimpanel@kde.org":
            svm = ext.get("shell_version_map", {})
            # 1. 优先精准匹配当前系统的 GNOME 大版本 (如 50, 51, 52)
            if target_ver in svm:
                print(svm[target_ver]["pk"])
                sys.exit(0)
            # 2. 若上游尚未为该大版本打独立 tag，自动回落至最新可用构建
            if svm:
                print(max(x["pk"] for x in svm.values()))
                sys.exit(0)
except Exception:
    pass
' "${SYSTEM_GNOME_VER}" 2>/dev/null || true)

if [ -n "${VERSION_TAG}" ]; then
    echo "==> 检测到系统 GNOME [${SYSTEM_GNOME_VER}]，成功解析版本 tag [${VERSION_TAG}]，正在下载..."
    mkdir -p /usr/share/gnome-shell/extensions/kimpanel@kde.org
    curl -sSL --connect-timeout 15 --retry 3 "https://extensions.gnome.org/download-extension/${UUID}.shell-extension.zip?version_tag=${VERSION_TAG}" -o /tmp/kimpanel.zip
    unzip -qo /tmp/kimpanel.zip -d /usr/share/gnome-shell/extensions/kimpanel@kde.org/
    rm -f /tmp/kimpanel.zip
    python3 -c '
import sys, json
meta_path = "/usr/share/gnome-shell/extensions/kimpanel@kde.org/metadata.json"
target_ver = sys.argv[1] if len(sys.argv) > 1 else "50"
try:
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    existing = set(meta.get("shell-version", []))
    existing.add(target_ver)
    for v in range(44, 61):
        existing.add(str(v))
    meta["shell-version"] = sorted(list(existing), key=lambda x: int(x) if x.isdigit() else 0)
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
except Exception as e:
    print(f"拓展 metadata.json 兼容版本出现异常: {e}")
' "${SYSTEM_GNOME_VER}" 2>/dev/null || true
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
HTML_PAGE=$(curl -sfSL --connect-timeout 10 --retry 2 "https://antigravity.google/download" 2>/dev/null || true)
UPDATER_API=$(printf '%s' "${HTML_PAGE}" | grep -Eo 'https://[a-zA-Z0-9.-]+\.run\.app/releases' | head -n 1 || true)
UPDATER_API="${UPDATER_API:-https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/releases}"

RELEASE_JSON=$(curl -sfSL --connect-timeout 15 --retry 3 "${UPDATER_API}" 2>/dev/null || true)
RELEASE_INFO=$(printf '%s' "${RELEASE_JSON}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    latest = data[0]
    print(str(latest["version"]) + "-" + str(latest["execution_id"]))
except Exception:
    pass
' 2>/dev/null || true)

if [ -n "${RELEASE_INFO}" ]; then
    DOWNLOAD_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${RELEASE_INFO}/linux-x64/Antigravity.tar.gz"
    echo "==> 检测到最新版本 [${RELEASE_INFO}]，开始下载并安装至 /usr/lib/antigravity: ${DOWNLOAD_URL}"
    mkdir -p /usr/lib/antigravity
    curl -sfSL --connect-timeout 15 --retry 3 "${DOWNLOAD_URL}" -o /tmp/Antigravity.tar.gz
    tar -xzf /tmp/Antigravity.tar.gz -C /usr/lib/antigravity --strip-components=1
    rm -f /tmp/Antigravity.tar.gz
    chmod 755 /usr/lib/antigravity/antigravity
    ln -sf /usr/lib/antigravity/antigravity /usr/bin/antigravity
    echo "==> Antigravity IDE [${RELEASE_INFO}] 已成功部署至 /usr/lib/antigravity 并软链至 /usr/bin/antigravity！"
else
    echo "==> 警告: 无法解析 Antigravity 最新发布版本，跳过在线下载"
fi
