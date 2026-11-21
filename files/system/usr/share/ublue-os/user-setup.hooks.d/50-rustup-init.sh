#!/usr/bin/env bash
# ==============================================================================
# My-Bluefin Rustup 用户空间静默初始化钩子
# - 纯后台异步执行：零阻塞用户桌面登录
# - 结合中科大 (USTC) 国内镜像，在 ~/.rustup / ~/.cargo 下自动就绪 stable 工具链
# - 保持工具链完全可写：后续 rustup update / nightly / cargo install 零只读限制
# ==============================================================================

# 0. 仅对普通真实用户执行，跳过 gdm、gdm-greeter 等系统与锁屏虚拟用户
[ "$(id -u)" -lt 1000 ] && exit 0
case "$(id -u -n 2>/dev/null)" in
    gdm|gdm-greeter|gnome-initial-setup) exit 0 ;;
esac

RUSTUP_INIT_BIN="/usr/bin/rustup-init"
[ -x "${RUSTUP_INIT_BIN}" ] || exit 0

mkdir -p "$HOME/.local/state" "$HOME/.cargo"

# 1. 若用户尚无 Cargo 镜像配置，默认初始化为中科大 (USTC) 稀疏索引源（不覆盖用户已有自定义）
CARGO_CONFIG="$HOME/.cargo/config.toml"
if [ ! -f "${CARGO_CONFIG}" ]; then
    cat << 'EOF' > "${CARGO_CONFIG}"
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
EOF
fi

# 2. 快速前置检测（耗时 < 1ms）：工具链已完整就绪则直接退出
DONE_FLAG="$HOME/.local/state/.rustup-init-done"
if [ -f "${DONE_FLAG}" ] && \
   [ -x "$HOME/.cargo/bin/rustup" ] && \
   [ -x "$HOME/.cargo/bin/rustc" ] && \
   [ -x "$HOME/.cargo/bin/cargo" ]; then
    exit 0
fi

# 3. 通过 systemd-run 启动独立瞬态用户服务异步执行（零阻塞登录）
if [ -z "${MY_BLUEFIN_RUSTUP_BG_WORKER:-}" ] && command -v systemd-run >/dev/null 2>&1; then
    if systemd-run --user --no-block --collect --unit=my-bluefin-rustup-setup \
        --setenv=MY_BLUEFIN_RUSTUP_BG_WORKER=1 "$0" >/dev/null 2>&1; then
        exit 0
    fi
fi

run_rustup_worker() {
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/my-bluefin-rustup-${UID}.lock"
    exec 201>"${LOCK_FILE}"
    if ! flock -n 201; then
        exit 0
    fi

    exec >>"$HOME/.local/state/rustup-setup.log" 2>&1

    export RUSTUP_DIST_SERVER="https://mirrors.ustc.edu.cn/rust-static"
    export RUSTUP_UPDATE_ROOT="https://mirrors.ustc.edu.cn/rust-static/rustup"

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 开始检查并初始化 Rust 工具链 (USTC 镜像)..."

    # 等待网络连接就绪（最多等待 60 秒）
    net_ready=false
    for _ in $(seq 1 30); do
        if curl -fsSL --connect-timeout 3 -o /dev/null "${RUSTUP_DIST_SERVER}/dist/channel-rust-stable.toml.sha256" 2>/dev/null; then
            net_ready=true
            break
        fi
        sleep 2
    done

    if [ "${net_ready}" != "true" ]; then
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 提示: 当前网络暂不可达 USTC Rust 镜像，将在下次登录重试。"
        exit 0
    fi

    # 若用户之前已有工具链，补齐组件；否则全新安装 stable + rust-analyzer + rust-src
    if [ -x "$HOME/.cargo/bin/rustup" ] && [ -x "$HOME/.cargo/bin/rustc" ]; then
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 检测到已存在 rustup，校验并补齐组件..."
        "$HOME/.cargo/bin/rustup" component add rust-analyzer rust-src clippy rustfmt || true
    else
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 正在通过 rustup-init 安装 stable 工具链 (含 clippy/rustfmt/rust-analyzer/rust-src)..."
        if ! "${RUSTUP_INIT_BIN}" -y --default-toolchain stable --profile default --component rust-analyzer,rust-src; then
            echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 警告: rustup-init 安装失败，将在下次登录重试。"
            exit 1
        fi
    fi

    if [ -x "$HOME/.cargo/bin/rustc" ] && [ -x "$HOME/.cargo/bin/cargo" ]; then
        touch "${DONE_FLAG}"
        echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] Rust 工具链初始化完成: $("$HOME/.cargo/bin/rustc" --version 2>/dev/null || true)"
    fi
}

if [ -n "${MY_BLUEFIN_RUSTUP_BG_WORKER:-}" ]; then
    run_rustup_worker
else
    run_rustup_worker &
fi
