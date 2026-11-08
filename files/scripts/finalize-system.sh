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
chmod 755 /usr/bin/fcitx5-prestart-setup /usr/bin/optimize-flathub
chmod 755 /usr/libexec/my-bluefin/* 2>/dev/null || true
chmod 644 /usr/share/ublue-os/grub2/user.cfg /usr/share/ublue-os/vscode/extensions.list /usr/share/ublue-os/vscode/extensions/*.vsix 2>/dev/null || true
chmod 644 /usr/share/ublue-os/just/60-custom.just /usr/share/applications/*.desktop 2>/dev/null || true
# 尝试同步社区最新 Android udev 规则（网络畅通即更新到最新，网络受限则保留仓库中内置的静态兜底版本）
curl -fsSL https://raw.githubusercontent.com/M0Rf30/android-udev-rules/main/51-android.rules \
    -o /usr/lib/udev/rules.d/51-android.rules 2>/dev/null || true

chmod 644 /usr/lib/udev/rules.d/*.rules /usr/share/sunshine/apps.json /usr/share/icons/hicolor/*/*/*.png 2>/dev/null || true
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

# 启用系统级与用户级服务（同时固化 /usr/lib 镜像不可变层与 /etc 标准配置层，兼顾 OSTree 升级无感生效与开箱自启）
mkdir -p /usr/lib/systemd/user/graphical-session.target.wants /usr/lib/systemd/user/gnome-session.target.wants /usr/lib/systemd/system/multi-user.target.wants /usr/lib/systemd/system/sockets.target.wants /usr/lib/systemd/system/timers.target.wants
ln -sf /usr/lib/systemd/user/fcitx5.service /usr/lib/systemd/user/graphical-session.target.wants/fcitx5.service
ln -sf /usr/lib/systemd/user/fcitx5.service /usr/lib/systemd/user/gnome-session.target.wants/fcitx5.service
ln -sf /usr/lib/systemd/user/tailscale-systray.service /usr/lib/systemd/user/graphical-session.target.wants/tailscale-systray.service
ln -sf /usr/lib/systemd/system/flatpak-ustc-mirror.service /usr/lib/systemd/system/multi-user.target.wants/flatpak-ustc-mirror.service
ln -sf /usr/lib/systemd/system/grub-user-cfg.service /usr/lib/systemd/system/multi-user.target.wants/grub-user-cfg.service
ln -sf /usr/lib/systemd/system/tailscale-operator-setup.service /usr/lib/systemd/system/multi-user.target.wants/tailscale-operator-setup.service
ln -sf /usr/lib/systemd/system/flatpak-ustc-mirror.timer /usr/lib/systemd/system/timers.target.wants/flatpak-ustc-mirror.timer

systemctl enable \
    flatpak-ustc-mirror.service \
    flatpak-ustc-mirror.timer \
    grub-user-cfg.service \
    tailscale-operator-setup.service \
    libvirtd.service \
    virtqemud.socket \
    virtnetworkd.socket \
    virtstoraged.socket 2>/dev/null || true

systemctl --global enable \
    fcitx5.service \
    tailscale-systray.service 2>/dev/null || true

systemctl disable warp-svc.service 2>/dev/null || true
systemctl --global disable warp-taskbar.service warp-desktop-svc.service 2>/dev/null || true

# 彻底屏蔽 GNOME 默认 IBus 会话拉起，确保单 Fcitx5 雾凇常驻零冲突
rm -f /usr/lib/systemd/user/gnome-session.target.wants/org.freedesktop.IBus.session.GNOME.service
ln -sf /dev/null /usr/lib/systemd/user/org.freedesktop.IBus.session.GNOME.service
rm -f /etc/xdg/Xwayland-session.d/10-ibus-x11 /usr/etc/xdg/Xwayland-session.d/10-ibus-x11

glib-compile-schemas /usr/share/glib-2.0/schemas/
flatpak remote-modify --system --disable fedora 2>/dev/null || true

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
