#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动官方雾凇拼音 (Rime-ICE) 模板集成模块 (rime-ice)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"
TARGET_DIR=$(echo "${CONFIG_JSON}" | jq -r 'try .target_dir // empty')
TARGET_DIR="${TARGET_DIR:-/usr/share/ublue-os/rime-ice}"
REPO_URL=$(echo "${CONFIG_JSON}" | jq -r 'try .repo_url // empty')
REPO_URL="${REPO_URL:-https://github.com/iDvel/rime-ice.git}"
SHIFT_R_ACTION=$(echo "${CONFIG_JSON}" | jq -r 'try .shift_r // empty')
SHIFT_R_ACTION="${SHIFT_R_ACTION:-commit_code}"

echo "==> 正在克隆官方雾凇拼音仓库 [${REPO_URL}]..."
TMP_DIR="/tmp/rime-ice-build"
rm -rf "${TMP_DIR}"
git clone --depth 1 "${REPO_URL}" "${TMP_DIR}"

mkdir -p "${TARGET_DIR}"
cp -rf "${TMP_DIR}"/* "${TARGET_DIR}/"
rm -rf "${TMP_DIR}"

# 预置 Rime 自定义全局配置补丁
echo "==> 正在注入 Rime 全局配置补丁 (Shift_R: ${SHIFT_R_ACTION})..."
cat << EOF > "${TARGET_DIR}/default.custom.yaml"
# Rime 自定义全局配置补丁
patch:
  "ascii_composer/switch_key/Shift_R": ${SHIFT_R_ACTION}
EOF

chmod -R a+rX "${TARGET_DIR}"

echo "==> 雾凇拼音词库模板已成功预置至 ${TARGET_DIR}！"
echo "=============================================================================="
