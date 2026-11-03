#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动 Google Antigravity IDE 部署模块 (antigravity)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"
INSTALL_DIR=$(echo "${CONFIG_JSON}" | jq -r 'try .install_dir // empty')
INSTALL_DIR="${INSTALL_DIR:-/usr/lib/antigravity}"
BIN_LINK=$(echo "${CONFIG_JSON}" | jq -r 'try .bin_link // empty')
BIN_LINK="${BIN_LINK:-/usr/bin/antigravity}"

echo "==> 正在精准解析 Google 官方最新版 Antigravity IDE..."
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

if [ -z "${RELEASE_INFO}" ]; then
    echo "==> 警告: 无法解析 Antigravity 最新发布版本，跳过在线下载。"
    exit 0
fi

DOWNLOAD_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${RELEASE_INFO}/linux-x64/Antigravity.tar.gz"
echo "==> 检测到最新版本 [${RELEASE_INFO}]，开始下载并安装至 ${INSTALL_DIR}: ${DOWNLOAD_URL}"

mkdir -p "${INSTALL_DIR}"
TMP_TAR="/tmp/Antigravity.tar.gz"

curl -sfSL --connect-timeout 15 --retry 3 "${DOWNLOAD_URL}" -o "${TMP_TAR}"
tar -xzf "${TMP_TAR}" -C "${INSTALL_DIR}" --strip-components=1
rm -f "${TMP_TAR}"

chmod 755 "${INSTALL_DIR}/antigravity"
mkdir -p "$(dirname "${BIN_LINK}")"
ln -sf "${INSTALL_DIR}/antigravity" "${BIN_LINK}"

echo "==> Antigravity IDE [${RELEASE_INFO}] 已成功部署至 ${INSTALL_DIR} 并软链至 ${BIN_LINK}！"
echo "=============================================================================="
