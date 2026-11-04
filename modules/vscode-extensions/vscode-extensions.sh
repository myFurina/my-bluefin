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

# 3. 构建期离线 VSIX 包预缓存（借助 GitHub Actions 优质网络，实现系统开箱 0 网络秒装）
VSIX_CACHE_DIR="${TARGET_DIR}/extensions"
mkdir -p "${VSIX_CACHE_DIR}"

echo "==> 正在尝试预下载扩展离线包至 ${VSIX_CACHE_DIR}..."
while IFS= read -r ext || [ -n "${ext}" ]; do
    [[ -z "${ext}" || "${ext}" =~ ^[[:space:]]*# ]] && continue
    ext=$(echo "${ext}" | tr -d '[:space:]')

    publisher="${ext%%.*}"
    ext_name="${ext#*.}"
    vsix_path="${VSIX_CACHE_DIR}/${ext}.vsix"

    echo "--> [预缓存] 正在下载扩展离线包: ${ext}..."
    # 官方 Marketplace API (优先探测 linux-x64 架构原生包，回退通用包) 与 open-vsx 多源下载
    download_urls=(
        "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${ext_name}/latest/vspackage?targetPlatform=linux-x64"
        "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${ext_name}/latest/vspackage"
        "https://${publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/${publisher}/extension/${ext_name}/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
        "https://open-vsx.org/api/${publisher}/${ext_name}/latest/file"
    )

    downloaded=0
    for url in "${download_urls[@]}"; do
        if curl -fsSL --connect-timeout 10 --max-time 120 -o "${vsix_path}" "${url}" 2>/dev/null; then
            # 校验是否为有效的 zip/vsix 文件（前 4 字节为 PK\x03\x04）
            if [ -s "${vsix_path}" ] && head -c 2 "${vsix_path}" | grep -q 'PK'; then
                chmod 644 "${vsix_path}"
                echo "    ✔ 离线包下载成功: $(ls -lh "${vsix_path}" | awk '{print $5}')"
                downloaded=1
                break
            else
                rm -f "${vsix_path}"
            fi
        fi
    done

    if [ ${downloaded} -eq 0 ]; then
        echo "    ⚠ 离线包下载跳过或失败（用户首登将自动降级为在线安装兜底）"
    fi
done < "${TARGET_FILE}"

echo "=============================================================================="
