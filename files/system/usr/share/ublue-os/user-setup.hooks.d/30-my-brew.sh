#!/usr/bin/env bash

# 0. 仅对普通真实用户 (UID >= 1000) 执行，跳过 gdm 登录界面等系统虚拟用户
[ "$(id -u)" -lt 1000 ] && exit 0

# 1. 确保 Fcitx5 单雾凇配置与 LocalSend 渲染所需的回退中文字体第一时间到位
/usr/bin/fcitx5-prestart-setup 2>/dev/null || true
mkdir -p "$HOME/.local/share/fonts" "$HOME/.local/state"
if [ ! -f "$HOME/.local/share/fonts/DroidSansFallbackFull.ttf" ] && [ -f /usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf ]; then
    cp /usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf "$HOME/.local/share/fonts/"
fi

# 2. 确保 WezTerm 终端配置下发至用户目录，并默认关闭 Bluefin 终端欢迎横幅 (MOTD)
mkdir -p "$HOME/.config/wezterm" "$HOME/.local/bin"
touch "$HOME/.config/no-show-user-motd"
if [ ! -f "$HOME/.config/wezterm/wezterm.lua" ] && [ -f /usr/share/ublue-os/my-brew/wezterm.lua ]; then
    cp /usr/share/ublue-os/my-brew/wezterm.lua "$HOME/.config/wezterm/wezterm.lua"
fi

# 2.5 托管 OpenCode V2 至用户可写目录 ~/.local/bin/opencode（首次自动部署，未卸载则随镜像自动更新，卸载后不反弹）
if [ ! -f "$HOME/.config/opencode-initialized" ] && [ -f /usr/share/ublue-os/my-brew/opencode ]; then
    cp -f /usr/share/ublue-os/my-brew/opencode "$HOME/.local/bin/opencode"
    chmod 755 "$HOME/.local/bin/opencode"
    touch "$HOME/.config/opencode-initialized"
elif [ -f "$HOME/.local/bin/opencode" ] && [ -f /usr/share/ublue-os/my-brew/opencode ]; then
    cp -u /usr/share/ublue-os/my-brew/opencode "$HOME/.local/bin/opencode"
    chmod 755 "$HOME/.local/bin/opencode"
fi

# 3. 确保 ~/.bashrc 中包含 Homebrew 清华源环境变量及首次就绪检测
if ! grep -q "linuxbrew" "$HOME/.bashrc" 2>/dev/null; then
    cat << 'BREWENV' >> "$HOME/.bashrc"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)"
export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
export HOMEBREW_NO_AUTO_UPDATE=1

# 首次登录未安装完成时的轻量终端进度指引（仅在就绪前提示一次）
if [ ! -f "$HOME/.config/user-brew-installed" ]; then
    echo "💡 提示: 后台正在自动安装 Homebrew 开发工具链 (可查看日志: tail -f ~/.local/state/brew-setup.log)"
fi
BREWENV
fi

# 5. 幂等性检测：Homebrew 依赖已安装完成则直接退出
INSTALL_FLAG="$HOME/.config/user-brew-installed"
[ -f "$INSTALL_FLAG" ] && exit 0

BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

# 异步在后台运行（配合 10-keep-background.conf 杜绝被 systemd 回收杀死）
(
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/simon-brew.lock"
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        exit 0
    fi

    exec >>"$HOME/.local/state/brew-setup.log" 2>&1

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 正在检查 Homebrew 核心程序 (${BREW_BIN})..."
    count=0
    while [ ! -x "${BREW_BIN}" ] && [ $count -lt 60 ]; do
        sleep 2
        count=$((count + 1))
    done

    if [ ! -x "${BREW_BIN}" ]; then
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 错误: 超时未能检测到可执行的 Homebrew: ${BREW_BIN}"
        which notify-send >/dev/null 2>&1 && notify-send -u critical -i dialog-error -a "系统初始化" "Homebrew 初始化失败" "未找到 Homebrew 核心程序，详情见 ~/.local/state/brew-setup.log" 2>/dev/null || true
        exit 0
    fi

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 检测到 Homebrew 已就绪，探测国内清华源连通性..."
    net_count=0
    while ! curl -s --connect-timeout 2 https://mirrors.tuna.tsinghua.edu.cn > /dev/null && [ $net_count -lt 30 ]; do
        sleep 2
        net_count=$((net_count + 1))
    done

    eval "$("${BREW_BIN}" shellenv)"
    export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
    export HOMEBREW_NO_AUTO_UPDATE=1

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 开始执行 brew bundle 批量安装..."
    if "${BREW_BIN}" bundle --file="/usr/share/ublue-os/my-brew/Brewfile"; then
        touch "$INSTALL_FLAG"
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] Homebrew 所有依赖安装成功！"
        which notify-send >/dev/null 2>&1 && notify-send -i utilities-terminal -a "系统初始化" "终端开发环境就绪" "Homebrew 核心工具链已全自动安装完成！" 2>/dev/null || true
    else
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 警告: brew bundle 未全部成功"
        which notify-send >/dev/null 2>&1 && notify-send -u critical -i dialog-warning -a "系统初始化" "Homebrew 依赖未全部完成" "部分工具安装异常，详情查看 ~/.local/state/brew-setup.log" 2>/dev/null || true
    fi
) &
