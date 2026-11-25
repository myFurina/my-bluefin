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
    # 1.1 下发 WezTerm 默认配置并静默 Bluefin 终端 MOTD
    mkdir -p "$HOME/.config/wezterm"
    touch "$HOME/.config/no-show-user-motd"
    if [ ! -f "$HOME/.config/wezterm/wezterm.lua" ] && [ -f /usr/share/ublue-os/my-brew/wezterm.lua ]; then
        cp /usr/share/ublue-os/my-brew/wezterm.lua "$HOME/.config/wezterm/wezterm.lua"
    fi

    touch "${DESKTOP_INIT_FLAG}"
fi

# 2. 托管应用专属字体（LocalSend、MarkText 与 wiliwili）
# 当镜像内置了 NotoSansSC-Mega 定制字体族时，自动同步至用户态并配置各应用对应字体路径
if [ -d /usr/share/fonts/NotoSansSC-Mega ]; then
    mkdir -p "$HOME/.local/share/fonts"
    # 2.1 同步用户字体库 NotoSansSC-Mega 字体族（使用内容比对避免 OSTree /usr 1970 时间戳导致无法更新）
    for f in /usr/share/fonts/NotoSansSC-Mega/*.ttf; do
        if [ -f "$f" ]; then
            fname=$(basename "$f")
            if [ ! -f "$HOME/.local/share/fonts/$fname" ] || ! cmp -s "$f" "$HOME/.local/share/fonts/$fname"; then
                cp -f "$f" "$HOME/.local/share/fonts/$fname"
            fi
        fi
    done
    if [ ! -f "$HOME/.local/share/fonts/NotoSansSC-Mega.ttf" ] && [ -f "$HOME/.local/share/fonts/NotoSansSC-Mega-Regular.ttf" ]; then
        ln -sf NotoSansSC-Mega-Regular.ttf "$HOME/.local/share/fonts/NotoSansSC-Mega.ttf"
    fi
    # 2.2 保持 DroidSansFallbackFull 作为全局后备字体
    if [ ! -f "$HOME/.local/share/fonts/DroidSansFallbackFull.ttf" ] && [ -f /usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf ]; then
        cp /usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf "$HOME/.local/share/fonts/"
    fi

    # 2.3 部署 wiliwili UI 字体（Regular）与弹幕字体（Bold 粗体更醒目）
    WILIWILI_CONF_DIR="$HOME/.var/app/cn.xfangfang.wiliwili/config/wiliwili"
    mkdir -p "${WILIWILI_CONF_DIR}"
    if [ -f "$HOME/.local/share/fonts/NotoSansSC-Mega-Regular.ttf" ]; then
        if [ ! -f "${WILIWILI_CONF_DIR}/font.ttf" ] || ! cmp -s "$HOME/.local/share/fonts/NotoSansSC-Mega-Regular.ttf" "${WILIWILI_CONF_DIR}/font.ttf"; then
            cp -f "$HOME/.local/share/fonts/NotoSansSC-Mega-Regular.ttf" "${WILIWILI_CONF_DIR}/font.ttf"
        fi
    fi
    if [ -f "$HOME/.local/share/fonts/NotoSansSC-Mega-Bold.ttf" ]; then
        if [ ! -f "${WILIWILI_CONF_DIR}/danmaku.ttf" ] || ! cmp -s "$HOME/.local/share/fonts/NotoSansSC-Mega-Bold.ttf" "${WILIWILI_CONF_DIR}/danmaku.ttf"; then
            cp -f "$HOME/.local/share/fonts/NotoSansSC-Mega-Bold.ttf" "${WILIWILI_CONF_DIR}/danmaku.ttf"
        fi
    fi
fi

# 3. 托管 OpenCode V2 至用户可写目录 ~/.local/bin/opencode（按镜像哈希增量同步，既不受 OSTree 1970 时间戳影响，也不覆盖用户手动升级）
IMAGE_OPENCODE="/usr/share/ublue-os/my-brew/opencode"
OPENCODE_SHA_FILE="$HOME/.local/state/opencode-image.sha256"
if [ -f "${IMAGE_OPENCODE}" ]; then
    current_img_sha=$(sha256sum "${IMAGE_OPENCODE}" | awk '{print $1}')
    last_img_sha=$(cat "${OPENCODE_SHA_FILE}" 2>/dev/null || true)
    if [ ! -f "$HOME/.config/opencode-initialized" ] || [ ! -x "$HOME/.local/bin/opencode" ] || [ "${current_img_sha}" != "${last_img_sha}" ]; then
        cp -f "${IMAGE_OPENCODE}" "$HOME/.local/bin/opencode"
        chmod 755 "$HOME/.local/bin/opencode"
        echo "${current_img_sha}" > "${OPENCODE_SHA_FILE}"
        touch "$HOME/.config/opencode-initialized"
    fi
fi

# 4. 确保 ~/.bashrc 中包含 Homebrew 清华源环境变量（含 Git 镜像）及首次就绪检测
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

# 5. 自动校准 Homebrew 自身 Git 仓库至清华镜像（一次性操作，成功后立 flag 永久跳过）
BREW_MIRROR_FLAG="$HOME/.local/state/.brew-git-mirror-done"
configure_brew_git_mirror() {
    [ -f "$BREW_MIRROR_FLAG" ] && return 0
    local brew_repo="${1:-/home/linuxbrew/.linuxbrew/Homebrew}"
    if [ -d "${brew_repo}/.git" ]; then
        local current_brew_remote
        current_brew_remote=$(git -C "${brew_repo}" remote get-url origin 2>/dev/null || true)
        if [[ "${current_brew_remote}" =~ github\.com/Homebrew/brew ]]; then
            git -C "${brew_repo}" remote set-url origin "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git" 2>/dev/null || true
        fi

        local core_tap="${brew_repo}/Library/Taps/homebrew/homebrew-core"
        if [ -d "${core_tap}/.git" ]; then
            local current_core_remote
            current_core_remote=$(git -C "${core_tap}" remote get-url origin 2>/dev/null || true)
            if [[ "${current_core_remote}" =~ github\.com/Homebrew/homebrew-core ]]; then
                git -C "${core_tap}" remote set-url origin "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git" 2>/dev/null || true
            fi
        fi
        touch "$BREW_MIRROR_FLAG"
    fi
}
configure_brew_git_mirror "/home/linuxbrew/.linuxbrew/Homebrew"

# 6. 增量差分检测：仅对未推介过的新配方执行安装，用户主动卸载的工具绝不重新下载
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
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/my-bluefin-brew-${UID}.lock"
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
    configure_brew_git_mirror "$("${BREW_BIN}" --repo 2>/dev/null || echo "/home/linuxbrew/.linuxbrew/Homebrew")"

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
