#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动 VS Code 扩展声明模块 (vscode-extensions)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"

# 1. 解析需要预装的扩展列表
EXTENSIONS=$(echo "${CONFIG_JSON}" | jq -r 'try .install[] // empty')

TARGET_DIR="${VSCODE_EXT_DIR:-/usr/share/ublue-os/vscode}"
TARGET_FILE="${TARGET_DIR}/extensions.list"

mkdir -p "${TARGET_DIR}"

if [ -z "${EXTENSIONS}" ]; then
    echo "==> [vscode-extensions] 未声明预置扩展，清空或重置配置清单。"
    rm -f "${TARGET_FILE}"
    exit 0
fi

# 2. 规范化写入扩展清单（去除空行与重复项）
echo "${EXTENSIONS}" | grep -v '^[[:space:]]*$' | sort -u > "${TARGET_FILE}"
chmod 644 "${TARGET_FILE}"

COUNT=$(wc -l < "${TARGET_FILE}")
echo "==> 成功写入 ${COUNT} 个 VS Code 预装扩展至 ${TARGET_FILE}:"
cat "${TARGET_FILE}" | sed 's/^/  - /'

echo "=============================================================================="
