#!/usr/bin/env bash
set -oue pipefail

echo "=============================================================================="
echo "==> 启动 Cloudflare WARP 官方软件源自适应嗅探与准备..."
echo "=============================================================================="

# 1. 动态检测当前构建系统的主版本号 (如 45)
TARGET_VER="${VERSION_ID:-$(rpm -E %fedora 2>/dev/null || echo 45)}"
echo "==> 当前构建系统版本: Fedora ${TARGET_VER}"

# 2. 自适应探测 Cloudflare 官方 RPM 仓库可用版本（由当前版本向下回退探测）
DETECTED_VER=""
for v in $(seq "${TARGET_VER}" -1 40); do
    STATUS=$(curl -sfSL --connect-timeout 6 --retry 2 -o /dev/null -w "%{http_code}" "https://pkg.cloudflareclient.com/rpm/${v}/repodata/repomd.xml" 2>/dev/null || true)
    if [ "${STATUS}" = "200" ]; then
        DETECTED_VER="${v}"
        break
    fi
done

if [ -z "${DETECTED_VER}" ]; then
    echo "==> 警告: 未能从 Cloudflare 官方检测到可用源，使用当前系统版本兜底: Fedora ${TARGET_VER}"
    DETECTED_VER="${TARGET_VER}"
else
    if [ "${DETECTED_VER}" = "${TARGET_VER}" ]; then
        echo "==> 成功匹配 Cloudflare 官方原生源: Fedora ${DETECTED_VER}"
    else
        echo "==> 官方尚未发布 Fedora ${TARGET_VER} 源，自动选用官方当前最新可用源: Fedora ${DETECTED_VER}"
    fi
fi

# 3. 写入供构建期使用的临时 repo 配置
mkdir -p /etc/yum.repos.d
cat <<EOF > /etc/yum.repos.d/cloudflare-warp.repo
[cloudflare-warp-stable]
name=cloudflare-warp-stable
baseurl=https://pkg.cloudflareclient.com/rpm/${DETECTED_VER}
enabled=1
type=rpm
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
EOF

echo "==> Cloudflare WARP 软件源准备完成 (当前构建阶段指向: rpm/${DETECTED_VER})！"
echo "=============================================================================="
