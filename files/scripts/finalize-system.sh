#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 1. 收敛 Cloudflare WARP 自启残留与恢复标准软件源
# ==============================================================================
echo "==> 正在清理 Cloudflare WARP 开机与桌面自启残留..."
mkdir -p /usr/lib/systemd/system
if [ -f /etc/systemd/system/warp-svc.service ]; then
    mv -f /etc/systemd/system/warp-svc.service /usr/lib/systemd/system/warp-svc.service
elif [ -f /opt/cloudflare-warp/warp-svc.service ]; then
    cp -f /opt/cloudflare-warp/warp-svc.service /usr/lib/systemd/system/warp-svc.service
fi
rm -f /etc/systemd/system/multi-user.target.wants/warp-svc.service
rm -f /etc/xdg/autostart/com.cloudflare.WarpTaskbar.desktop /etc/xdg/autostart/warp-taskbar.desktop

if [ -f /etc/yum.repos.d/cloudflare-warp.repo ]; then
    echo "==> 正在恢复 Cloudflare WARP 系统源为标准自适应 \$releasever 配置 (支持未来自动升级与容错)..."
    cat << 'EOF' > /etc/yum.repos.d/cloudflare-warp.repo
[cloudflare-warp-stable]
name=cloudflare-warp-stable
baseurl=https://pkg.cloudflareclient.com/rpm/$releasever
enabled=1
type=rpm
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
skip_if_unavailable=True
EOF
fi

# ==============================================================================
# 2. 修正静态文件权限与建立 systemd 服务软链接
# ==============================================================================
echo "==> 正在校准系统脚本权限、建立服务软链接并编译 GSettings Schema..."
chmod 644 /usr/share/polkit-1/rules.d/50-warp-service.rules /usr/share/polkit-1/rules.d/50-libvirt-nopasswd.rules
chmod 755 /usr/bin/fcitx5-prestart-setup /usr/bin/optimize-flathub
chmod 755 /usr/libexec/my-bluefin/* 2>/dev/null || true
chmod 644 /usr/share/ublue-os/grub2/user.cfg 2>/dev/null || true
chmod 644 /usr/share/ublue-os/just/60-custom.just /usr/share/applications/*.desktop 2>/dev/null || true
chmod 644 /etc/profile.d/90-rust-cargo.sh /usr/lib/environment.d/10-rust-mirror.conf /etc/ssh/ssh_config.d/*.conf /usr/lib/tmpfiles.d/*.conf 2>/dev/null || true
# 尝试同步社区最新 Android udev 规则（网络畅通即更新到最新，网络受限则保留仓库中内置的静态兜底版本）
curl -fsSL https://raw.githubusercontent.com/M0Rf30/android-udev-rules/main/51-android.rules \
    -o /usr/lib/udev/rules.d/51-android.rules 2>/dev/null || true

chmod 644 /usr/lib/udev/rules.d/*.rules /usr/share/sunshine/apps.json /usr/share/icons/hicolor/*/*/*.png /usr/share/fonts/NotoSansSC-Mega/*.ttf 2>/dev/null || true
fc-cache -f /usr/share/fonts/NotoSansSC-Mega 2>/dev/null || true
ln -sf /usr/bin/optimize-flathub /usr/bin/optimize-network
ln -sf /usr/libexec/my-bluefin/sunshine-privacy-screen /usr/bin/sunshine-privacy-screen
chmod 755 /usr/share/ublue-os/user-setup.hooks.d/*.sh 2>/dev/null || true

# 为原生 Sunshine 固化 KMS 抓屏特权 (CAP_SYS_ADMIN) 并建立 sunshine.service 兼容别名软链接
if [ -f /usr/bin/sunshine ]; then
    echo "==> 正在为原生 Sunshine 赋予 KMS 硬件捕获特权 (cap_sys_admin)..."
    setcap cap_sys_admin+p /usr/bin/sunshine || true
fi
if [ -f /usr/lib/systemd/user/app-dev.lizardbyte.app.Sunshine.service ] && [ ! -f /usr/lib/systemd/user/sunshine.service ]; then
    ln -sf app-dev.lizardbyte.app.Sunshine.service /usr/lib/systemd/user/sunshine.service
fi

# 规范化执行 systemd preset 声明式服务启用（避免在 /usr/lib 下遗留无法通过 systemctl disable 禁用的只读软链接）
systemctl preset-all 2>/dev/null || true
systemctl --global preset-all 2>/dev/null || true

# 彻底屏蔽 GNOME 默认 IBus 会话拉起，确保单 Fcitx5 雾凇常驻零冲突
rm -f /usr/lib/systemd/user/gnome-session.target.wants/org.freedesktop.IBus.session.GNOME.service
ln -sf /dev/null /usr/lib/systemd/user/org.freedesktop.IBus.session.GNOME.service
rm -f /etc/xdg/Xwayland-session.d/10-ibus-x11

glib-compile-schemas --strict /usr/share/glib-2.0/schemas/
flatpak remote-modify --system --disable fedora 2>/dev/null || true
