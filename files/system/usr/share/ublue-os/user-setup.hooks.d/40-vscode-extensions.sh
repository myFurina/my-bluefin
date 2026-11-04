#!/usr/bin/env bash
# ==============================================================================
# My-Bluefin VS Code 扩展用户空间增量静默安装钩子
# - 纯后台异步执行：零阻塞用户桌面登录
# - 增量差分防复活：已推介过的扩展若被用户手动卸载，绝不重新强装
# ==============================================================================

EXT_LIST="/usr/share/ublue-os/vscode/extensions.list"
PROVISIONED_FILE="$HOME/.local/state/vscode-provisioned.list"
LOG_FILE="$HOME/.local/state/vscode-setup.log"

# 1. 基础环境核验
if [ ! -f "${EXT_LIST}" ] || ! command -v code >/dev/null 2>&1; then
    exit 0
fi

mkdir -p "$HOME/.local/state"
touch "${PROVISIONED_FILE}"

# 2. 计算需要增量安装的扩展（排除历史已推介过的条目）
pending_extensions=()
while IFS= read -r ext || [ -n "${ext}" ]; do
    # 过滤空行与注释
    [[ -z "${ext}" || "${ext}" =~ ^[[:space:]]*# ]] && continue
    ext=$(echo "${ext}" | tr -d '[:space:]')

    # 若该扩展不在已推介清单中，则加入待安装队列
    if ! grep -Fxq "${ext}" "${PROVISIONED_FILE}" 2>/dev/null; then
        pending_extensions+=("${ext}")
    fi
done < "${EXT_LIST}"

# 若无待处理扩展，毫秒级直接退出
if [ ${#pending_extensions[@]} -eq 0 ]; then
    exit 0
fi

# 3. 后台异步静默安装（使用独立子进程，完全不阻碍图形桌面就绪）
(
    # 等待桌面网络就绪
    sleep 5

    # 桌面气泡提示
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="VS Code" "正在自动配置环境" "后台正在为您静默安装 ${#pending_extensions[@]} 个预置扩展..." 2>/dev/null || true
    fi

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 开始增量安装 VS Code 扩展: ${pending_extensions[*]}" >> "${LOG_FILE}"

    success_count=0
    for ext in "${pending_extensions[@]}"; do
        echo "--> 正在安装: ${ext}..." >> "${LOG_FILE}"

        # 优先使用镜像预置的离线 .vsix 安装包（零网络依赖，秒装就绪）
        local_vsix="/usr/share/ublue-os/vscode/extensions/${ext}.vsix"
        if [ -f "${local_vsix}" ]; then
            echo "    发现本地离线安装包: ${local_vsix}" >> "${LOG_FILE}"
            target_install="${local_vsix}"
        else
            target_install="${ext}"
        fi

        # 若本地 Clash 代理端口可用，自动附加代理参数加速网络下载兜底
        extra_args=()
        if [ "${target_install}" = "${ext}" ] && curl -s --connect-timeout 1 http://127.0.0.1:7897 >/dev/null 2>&1; then
            extra_args+=("--proxy-server=http://127.0.0.1:7897")
        fi

        if code --install-extension "${target_install}" ${extra_args[@]+"${extra_args[@]}"} --force >> "${LOG_FILE}" 2>&1; then
            echo "${ext}" >> "${PROVISIONED_FILE}"
            ((success_count++)) || true
            echo "✔ 成功安装: ${ext}" >> "${LOG_FILE}"
        else
            echo "✖ 安装失败: ${ext}" >> "${LOG_FILE}"
        fi
    done

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 扩展安装结束，成功: ${success_count}/${#pending_extensions[@]}" >> "${LOG_FILE}"

    if [ ${success_count} -gt 0 ] && command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="VS Code" "开发环境就绪" "已成功为您安装 ${success_count} 个 VS Code 扩展！" 2>/dev/null || true
    fi
) >/dev/null 2>&1 &
