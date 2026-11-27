#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动 Android SDK 离线预缓存模块 (android-cmdline-tools)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"
TARGET_DIR=$(echo "${CONFIG_JSON}" | jq -r 'try .target_dir // empty')
TARGET_DIR="${TARGET_DIR:-/usr/share/ublue-os/android-sdk}"

mapfile -t SDK_PACKAGES < <(echo "${CONFIG_JSON}" | jq -r 'try .packages[] // empty')
if [ ${#SDK_PACKAGES[@]} -eq 0 ]; then
    SDK_PACKAGES=(
        "platform-tools"
        "platforms;android-36"
        "build-tools;36.0.0"
    )
fi

FALLBACK_URL="https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip"
FALLBACK_SHA256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"

echo "==> 正在从 developer.android.com 解析最新 Linux Command-line Tools..."
STUDIO_HTML=$(curl -sfSL --connect-timeout 15 --retry 3 "https://developer.android.com/studio" 2>/dev/null || true)

PARSED_INFO=$(STUDIO_HTML="${STUDIO_HTML}" python3 - <<'PYEOF' || true
import os
import re

html = os.environ.get("STUDIO_HTML", "")
url_match = re.search(
    r"https://dl\.google\.com/android/repository/commandlinetools-linux-[0-9]+_latest\.zip",
    html,
)
if url_match:
    url = url_match.group(0)
    window = html[url_match.end() : url_match.end() + 600]
    sha_match = re.search(r"\b([0-9a-fA-F]{64})\b", window)
    sha = sha_match.group(1).lower() if sha_match else ""
    print(f"{url}\t{sha}")
PYEOF
)

DOWNLOAD_URL="${PARSED_INFO%%$'\t'*}"
EXPECTED_SHA256="${PARSED_INFO#*$'\t'}"

if [ -z "${DOWNLOAD_URL}" ]; then
    echo "==> 警告: 动态解析页面失败，回退至已核验官方版本: ${FALLBACK_URL}"
    DOWNLOAD_URL="${FALLBACK_URL}"
    EXPECTED_SHA256="${FALLBACK_SHA256}"
fi

echo "==> 下载地址: ${DOWNLOAD_URL}"
TMP_ZIP="/tmp/android-cmdline-tools.zip"
TMP_UNZIP="/tmp/android-cmdline-tools-unpack"

rm -f "${TMP_ZIP}"
rm -rf "${TMP_UNZIP}"

curl -sfSL --connect-timeout 15 --retry 3 "${DOWNLOAD_URL}" -o "${TMP_ZIP}"

if [ -n "${EXPECTED_SHA256}" ]; then
    echo "==> 正在校验 SHA-256: ${EXPECTED_SHA256}"
    echo "${EXPECTED_SHA256}  ${TMP_ZIP}" | sha256sum -c -
else
    echo "==> 警告: 页面未匹配到邻近 SHA-256，跳过哈希校验。"
fi

unzip -q "${TMP_ZIP}" -d "${TMP_UNZIP}"

if [ ! -f "${TMP_UNZIP}/cmdline-tools/bin/sdkmanager" ]; then
    echo "==> 错误: 解压产物中未找到 cmdline-tools/bin/sdkmanager！"
    rm -f "${TMP_ZIP}"
    rm -rf "${TMP_UNZIP}"
    exit 1
fi

rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}/cmdline-tools/latest"
cp -a "${TMP_UNZIP}/cmdline-tools/." "${TARGET_DIR}/cmdline-tools/latest/"

rm -f "${TMP_ZIP}"
rm -rf "${TMP_UNZIP}"

if [ -d /usr/lib/jvm/java-openjdk ]; then
    export JAVA_HOME="/usr/lib/jvm/java-openjdk"
elif command -v javac >/dev/null 2>&1; then
    export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi

SDKMANAGER="${TARGET_DIR}/cmdline-tools/latest/bin/sdkmanager"
chmod 755 "${TARGET_DIR}/cmdline-tools/latest/bin/"*

echo "==> 正在接受 Android SDK 许可协议并离线预缓存组件: ${SDK_PACKAGES[*]}"
(yes || true) | "${SDKMANAGER}" --sdk_root="${TARGET_DIR}" --licenses >/dev/null 2>&1 || true
"${SDKMANAGER}" --sdk_root="${TARGET_DIR}" "${SDK_PACKAGES[@]}"

rm -rf "${TARGET_DIR}/.temp" "${TARGET_DIR}/.downloadIntermediates"

if [ ! -d "${TARGET_DIR}/licenses" ] || [ ! -d "${TARGET_DIR}/platform-tools" ]; then
    echo "==> 错误: Android SDK 预缓存校验失败（缺少 licenses 或 platform-tools）！"
    exit 1
fi

chmod -R a+rX "${TARGET_DIR}"
chmod 755 "${TARGET_DIR}/cmdline-tools/latest/bin/"*

echo "==> Android 16 (API 36) 离线 SDK 模板已成功预缓存至 ${TARGET_DIR}！"
echo "=============================================================================="
