#!/usr/bin/env bash
set -oue pipefail

# ==============================================================================
# 1. 收敛 Cloudflare WARP 自启残留（移除 /etc 自启项并归档至 /usr/lib）
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

# ==============================================================================
# 2. 修正静态文件权限与建立 systemd 服务软链接
# ==============================================================================
echo "==> 正在校准系统脚本权限、建立服务软链接并编译 GSettings Schema..."
chmod 644 /usr/share/polkit-1/rules.d/50-warp-service.rules /usr/share/polkit-1/rules.d/50-libvirt-nopasswd.rules
chmod 755 /usr/bin/fcitx5-prestart-setup
chmod 755 /usr/share/ublue-os/user-setup.hooks.d/30-my-brew.sh

mkdir -p /usr/lib/systemd/user/graphical-session.target.wants /usr/lib/systemd/user/gnome-session.target.wants /usr/lib/systemd/system/multi-user.target.wants /usr/lib/systemd/system/sockets.target.wants
ln -sf /usr/lib/systemd/user/fcitx5.service /usr/lib/systemd/user/graphical-session.target.wants/fcitx5.service
ln -sf /usr/lib/systemd/user/fcitx5.service /usr/lib/systemd/user/gnome-session.target.wants/fcitx5.service
rm -f /usr/lib/systemd/user/gnome-session.target.wants/org.freedesktop.IBus.session.GNOME.service
ln -sf /dev/null /usr/lib/systemd/user/org.freedesktop.IBus.session.GNOME.service
rm -f /etc/xdg/Xwayland-session.d/10-ibus-x11 /usr/etc/xdg/Xwayland-session.d/10-ibus-x11
ln -sf /usr/lib/systemd/user/tailscale-systray.service /usr/lib/systemd/user/graphical-session.target.wants/tailscale-systray.service
ln -sf /usr/lib/systemd/system/flatpak-ustc-mirror.service /usr/lib/systemd/system/multi-user.target.wants/flatpak-ustc-mirror.service
systemctl enable libvirtd.service virtqemud.socket virtnetworkd.socket virtstoraged.socket 2>/dev/null || true

glib-compile-schemas /usr/share/glib-2.0/schemas/

# ==============================================================================
# 3. OSTree 规范化兜底：消除 /usr/etc 与 /etc 双目录冲突
# ==============================================================================
echo "==> [OSTree 规范化] 检查 /usr/etc 状态..."
if [ -d /usr/etc ]; then
    echo "==> 检测到 /usr/etc，正在将其合并并彻底移除以消除冲突..."
    cp -rn /usr/etc/* /etc/ 2>/dev/null || true
    rm -rf /usr/etc
    echo "==> /usr/etc 已成功彻底移除！"
else
    echo "==> 良好: 镜像中未发现 /usr/etc 目录。"
fi
