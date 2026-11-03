#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动 OpenCode 缓存部署模块 (opencode)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"
TARGET_DIR=$(echo "${CONFIG_JSON}" | jq -r 'try .target_dir // empty')
TARGET_DIR="${TARGET_DIR:-/usr/share/ublue-os/my-brew}"

echo "==> 正在从 anomalyco/homebrew-tap 解析最新版 OpenCode V2..."
OPENCODE_URL=$(curl -sfSL --connect-timeout 15 --retry 3 https://raw.githubusercontent.com/anomalyco/homebrew-tap/HEAD/opencode-v2.rb | grep -Eo 'https://[^"]+opencode-linux-x64[^"]+\.tar\.gz' | head -n 1 || true)

if [ -z "${OPENCODE_URL}" ]; then
    echo "==> 错误: 未能解析到 OpenCode V2 下载地址，请检查网络或源仓库状态。"
    exit 1
fi

echo "==> 开始下载 OpenCode V2: ${OPENCODE_URL}"
mkdir -p "${TARGET_DIR}"
TMP_TAR="/tmp/opencode.tar.gz"

curl -sfSL --connect-timeout 15 --retry 3 "${OPENCODE_URL}" -o "${TMP_TAR}"
tar -xzf "${TMP_TAR}" -C "${TARGET_DIR}" opencode
chmod 755 "${TARGET_DIR}/opencode"
rm -f "${TMP_TAR}"

echo "==> OpenCode V2 已成功部署至 ${TARGET_DIR}/opencode！"
echo "=============================================================================="
