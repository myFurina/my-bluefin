# Rustup / Cargo 用户级工具链 PATH 注入（镜像环境变量统一由 environment.d/10-rust-mirror.conf 托管）
if [ -d "$HOME/.cargo/bin" ]; then
    case ":$PATH:" in
        *":$HOME/.cargo/bin:"*) ;;
        *) export PATH="$HOME/.cargo/bin:$PATH" ;;
    esac
fi
