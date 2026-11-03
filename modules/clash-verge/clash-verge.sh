#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动 Clash Verge Rev 安装模块 (clash-verge)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"
REPO=$(echo "${CONFIG_JSON}" | jq -r 'try .repo // empty')
REPO="${REPO:-clash-verge-rev/clash-verge-rev}"

echo "==> 正在解析 GitHub [${REPO}] 最新发布版本..."
FINAL_URL=$(curl -sfSL --connect-timeout 15 --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" || true)
TAG="${FINAL_URL##*/}"
VER="${TAG#v}"

if [ -z "${FINAL_URL}" ] || [ "${TAG}" = "latest" ] || [ -z "${VER}" ]; then
    echo "==> 错误: 无法解析 Clash Verge 最新发布版本，请检查网络或 GitHub 状态。"
    exit 1
fi

CLASH_RPM="https://github.com/${REPO}/releases/download/${TAG}/Clash.Verge-${VER}-1.x86_64.rpm"
echo "==> 检测到最新版本 [${VER}]，开始通过 dnf 安装: ${CLASH_RPM}"
dnf install -y "${CLASH_RPM}"
dnf clean all

echo "==> Clash Verge Rev [${VER}] 安装完成！"
echo "=============================================================================="
