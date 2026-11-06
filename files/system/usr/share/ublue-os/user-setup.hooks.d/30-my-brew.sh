#!/usr/bin/env bash

# 0. 仅对普通真实用户执行，跳过 gdm、gdm-greeter 等系统与锁屏虚拟用户
[ "$(id -u)" -lt 1000 ] && exit 0
case "$(id -u -n 2>/dev/null)" in
    gdm|gdm-greeter|gnome-initial-setup) exit 0 ;;
esac

mkdir -p "$HOME/.local/state" "$HOME/.local/bin"

# 1. 桌面出厂环境一次性初装（仅在首登时执行一次，成功后永久跳过，避免每次登录循环激活扩展）
DESKTOP_INIT_FLAG="$HOME/.local/state/.desktop-firstboot-done"
if [ ! -f "${DESKTOP_INIT_FLAG}" ]; then
    # 1.1 补齐 LocalSend 等应用所需的回退中文字体
    mkdir -p "$HOME/.local/share/fonts"
    if [ ! -f "$HOME/.local/share/fonts/DroidSansFallbackFull.ttf" ] && [ -f /usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf ]; then
        cp /usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf "$HOME/.local/share/fonts/"
    fi

    # 1.2 下发 WezTerm 默认配置并静默 Bluefin 终端 MOTD
    mkdir -p "$HOME/.config/wezterm"
    touch "$HOME/.config/no-show-user-motd"
    if [ ! -f "$HOME/.config/wezterm/wezterm.lua" ] && [ -f /usr/share/ublue-os/my-brew/wezterm.lua ]; then
        cp /usr/share/ublue-os/my-brew/wezterm.lua "$HOME/.config/wezterm/wezterm.lua"
    fi

    # 1.3 激活系统级预置 GNOME 扩展（出厂首登初始化一次即可）
    if [ -d "/usr/share/gnome-shell/extensions" ]; then
        for ext_path in /usr/share/gnome-shell/extensions/*; do
            if [ -d "${ext_path}" ]; then
                ext_uuid=$(basename "${ext_path}")
                gnome-extensions enable "${ext_uuid}" 2>/dev/null || true
            fi
        done
    fi

    touch "${DESKTOP_INIT_FLAG}"
fi

# 2. 托管 OpenCode V2 至用户可写目录 ~/.local/bin/opencode（未安装则装，有镜像更新则更新）
if [ ! -f "$HOME/.config/opencode-initialized" ] && [ -f /usr/share/ublue-os/my-brew/opencode ]; then
    cp -f /usr/share/ublue-os/my-brew/opencode "$HOME/.local/bin/opencode"
    chmod 755 "$HOME/.local/bin/opencode"
    touch "$HOME/.config/opencode-initialized"
elif [ -f "$HOME/.local/bin/opencode" ] && [ -f /usr/share/ublue-os/my-brew/opencode ]; then
    cp -u /usr/share/ublue-os/my-brew/opencode "$HOME/.local/bin/opencode"
    chmod 755 "$HOME/.local/bin/opencode"
fi

# 3. 确保 ~/.bashrc 中包含 Homebrew 清华源环境变量（含 Git 镜像）及首次就绪检测
if ! grep -q "linuxbrew" "$HOME/.bashrc" 2>/dev/null; then
    cat << 'BREWENV' >> "$HOME/.bashrc"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)"
export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
export HOMEBREW_NO_AUTO_UPDATE=1

# 首次登录未安装完成时的轻量终端进度指引（仅在就绪前提示一次）
if [ ! -f "$HOME/.local/state/brew-provisioned.list" ] && [ ! -f "$HOME/.config/user-brew-installed" ]; then
    echo "💡 提示: 后台正在自动安装 Homebrew 开发工具链 (可查看日志: tail -f ~/.local/state/brew-setup.log)"
fi
BREWENV
elif ! grep -q "HOMEBREW_BREW_GIT_REMOTE" "$HOME/.bashrc" 2>/dev/null; then
    cat << 'BREW_GIT_ENV' >> "$HOME/.bashrc"
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
BREW_GIT_ENV
fi

# 4. 自动校准 Homebrew 自身 Git 仓库至清华镜像（一次性操作，成功后立 flag 永久跳过）
BREW_MIRROR_FLAG="$HOME/.local/state/.brew-git-mirror-done"
if [ ! -f "$BREW_MIRROR_FLAG" ]; then
    brew_repo="/home/linuxbrew/.linuxbrew/Homebrew"
    if [ -d "${brew_repo}/.git" ]; then
        current_brew_remote=$(git -C "${brew_repo}" remote get-url origin 2>/dev/null || true)
        if [[ "${current_brew_remote}" =~ github\.com/Homebrew/brew ]]; then
            git -C "${brew_repo}" remote set-url origin "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git" 2>/dev/null || true
        fi

        core_tap="${brew_repo}/Library/Taps/homebrew/homebrew-core"
        if [ -d "${core_tap}/.git" ]; then
            current_core_remote=$(git -C "${core_tap}" remote get-url origin 2>/dev/null || true)
            if [[ "${current_core_remote}" =~ github\.com/Homebrew/homebrew-core ]]; then
                git -C "${core_tap}" remote set-url origin "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git" 2>/dev/null || true
            fi
        fi
        touch "$BREW_MIRROR_FLAG"
    fi
fi

# 5. 增量差分检测：仅对未推介过的新配方执行安装，用户主动卸载的工具绝不重新下载
BREWFILE="/usr/share/ublue-os/my-brew/Brewfile"
PROVISIONED_FILE="$HOME/.local/state/brew-provisioned.list"
LEGACY_FLAG="$HOME/.config/user-brew-installed"

# 兼容存量系统平滑迁移：若已有旧版完成标记且无历史清单，将当前已装的 formula 记录为历史已推介
if [ ! -f "$PROVISIONED_FILE" ] && [ -f "$LEGACY_FLAG" ]; then
    mkdir -p "$HOME/.local/state"
    /home/linuxbrew/.linuxbrew/bin/brew list --formula 2>/dev/null > "$PROVISIONED_FILE" || true
fi

# 从系统 Brewfile 解析所有声明的目标 formula
target_formulas=()
if [ -f "$BREWFILE" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] && target_formulas+=("$f")
    done < <(awk -F '["'"'"']' '/^[[:space:]]*brew[[:space:]]+/ {print $2}' "$BREWFILE")
fi

# 筛选出真正属于新加入的 formula（在历史推介清单中从未出现过的）
pending_formulas=()
for formula in "${target_formulas[@]}"; do
    if ! grep -Fxq "$formula" "$PROVISIONED_FILE" 2>/dev/null; then
        pending_formulas+=("$formula")
    fi
done

# 若没有新配方需要安装，直接毫秒级静默退出（不占进程、不刷日志）
[ ${#pending_formulas[@]} -eq 0 ] && exit 0

BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

# 通过 systemd-run 启动独立瞬态用户服务异步执行（符合 systemd CGroup 规范，零阻塞登录）
if [ -z "${MY_BLUEFIN_BG_WORKER:-}" ] && command -v systemd-run >/dev/null 2>&1; then
    if systemd-run --user --no-block --collect --unit=my-bluefin-brew-setup \
        --setenv=MY_BLUEFIN_BG_WORKER=1 "$0" >/dev/null 2>&1; then
        exit 0
    fi
fi

run_brew_worker() {
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
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
    export HOMEBREW_NO_AUTO_UPDATE=1

    # 若此前尚未完成校准（如首登未解压完毕），在此完成兜底并立 flag 永久跳过
    if [ ! -f "$BREW_MIRROR_FLAG" ]; then
        brew_repo="$("${BREW_BIN}" --repo 2>/dev/null || echo "/home/linuxbrew/.linuxbrew/Homebrew")"
        if [ -d "${brew_repo}/.git" ]; then
            current_brew_remote=$(git -C "${brew_repo}" remote get-url origin 2>/dev/null || true)
            if [[ "${current_brew_remote}" =~ github\.com/Homebrew/brew ]]; then
                echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 自动切换 Homebrew 核心程序至清华镜像源..."
                git -C "${brew_repo}" remote set-url origin "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git" 2>/dev/null || true
            fi
        fi

        core_tap="${brew_repo}/Library/Taps/homebrew/homebrew-core"
        if [ -d "${core_tap}/.git" ]; then
            current_core_remote=$(git -C "${core_tap}" remote get-url origin 2>/dev/null || true)
            if [[ "${current_core_remote}" =~ github\.com/Homebrew/homebrew-core ]]; then
                echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 自动切换 homebrew-core tap 至清华镜像源..."
                git -C "${core_tap}" remote set-url origin "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git" 2>/dev/null || true
            fi
        fi
        touch "$BREW_MIRROR_FLAG"
    fi

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 发现 ${#pending_formulas[@]} 个待推介工具: ${pending_formulas[*]}"

    # 若为初次全新环境（历史清单尚不存在），直接执行整套 bundle 批量部署
    if [ ! -s "$PROVISIONED_FILE" ] && [ -f "$BREWFILE" ]; then
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 首次初始化，执行 brew bundle 批量安装..."
        if "${BREW_BIN}" bundle --file="$BREWFILE"; then
            printf "%s\n" "${target_formulas[@]}" >> "$PROVISIONED_FILE"
            touch "$LEGACY_FLAG"
            echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] Homebrew 所有初始依赖安装成功并写入历史清单！"
        else
            echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 警告: brew bundle 未全部成功，详情见上方日志"
        fi
    else
        # 增量单项/批量安装新加入的工具（用户已删软件绝对不会被重新安装）
        for pkg in "${pending_formulas[@]}"; do
            echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 正在增量安装新工具: ${pkg}..."
            if "${BREW_BIN}" install "$pkg"; then
                echo "$pkg" >> "$PROVISIONED_FILE"
                echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 工具 ${pkg} 安装成功并写入历史清单！"
            else
                echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 警告: 工具 ${pkg} 安装失败，将在下次开机重试"
            fi
        done
        touch "$LEGACY_FLAG"
    fi
}

if [ -n "${MY_BLUEFIN_BG_WORKER:-}" ]; then
    run_brew_worker
else
    run_brew_worker &
fi
