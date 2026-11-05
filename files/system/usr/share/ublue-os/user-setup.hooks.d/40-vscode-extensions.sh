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

# 2. 查询 VS Code 当前实际已安装的扩展（统一转小写比对，避免大小写差异）
installed_exts=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)

# 3. 自动同步：若扩展实际上已经在 VS Code 中，直接同步记录到已推介清单，杜绝重复弹窗
if [ -n "${installed_exts}" ]; then
    while IFS= read -r ext || [ -n "${ext}" ]; do
        [[ -z "${ext}" || "${ext}" =~ ^[[:space:]]*# ]] && continue
        ext_clean=$(echo "${ext}" | tr -d '[:space:]')
        ext_lower=$(echo "${ext_clean}" | tr '[:upper:]' '[:lower:]')

        if echo "${installed_exts}" | grep -Fxq "${ext_lower}"; then
            if ! grep -Fxq "${ext_clean}" "${PROVISIONED_FILE}" 2>/dev/null; then
                echo "${ext_clean}" >> "${PROVISIONED_FILE}"
            fi
        fi
    done < "${EXT_LIST}"
fi

# 4. 计算真正需要增量安装的扩展（排除历史已推介 与 实际已安装的项目）
pending_extensions=()
while IFS= read -r ext || [ -n "${ext}" ]; do
    [[ -z "${ext}" || "${ext}" =~ ^[[:space:]]*# ]] && continue
    ext_clean=$(echo "${ext}" | tr -d '[:space:]')
    ext_lower=$(echo "${ext_clean}" | tr '[:upper:]' '[:lower:]')

    # 若已在推介清单中，跳过
    if grep -Fxq "${ext_clean}" "${PROVISIONED_FILE}" 2>/dev/null; then
        continue
    fi

    # 若实际已安装在 VS Code 中，补齐记录并跳过
    if [ -n "${installed_exts}" ] && echo "${installed_exts}" | grep -Fxq "${ext_lower}"; then
        echo "${ext_clean}" >> "${PROVISIONED_FILE}"
        continue
    fi

    pending_extensions+=("${ext_clean}")
done < "${EXT_LIST}"

# 若无待处理扩展，毫秒级直接退出（绝不弹窗、绝不打扰用户）
if [ ${#pending_extensions[@]} -eq 0 ]; then
    exit 0
fi

# 5. 后台异步静默安装（使用独立子进程，完全不阻碍图形桌面就绪，静默无弹窗）
(
    # 等待桌面网络就绪
    sleep 5

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 开始增量安装 VS Code 扩展: ${pending_extensions[*]}" >> "${LOG_FILE}"

    success_count=0
    for ext in "${pending_extensions[@]}"; do
        echo "--> 正在安装: ${ext}..." >> "${LOG_FILE}"
        ext_lower=$(echo "${ext}" | tr '[:upper:]' '[:lower:]')

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

        install_ok=0
        if code --install-extension "${target_install}" ${extra_args[@]+"${extra_args[@]}"} --force >> "${LOG_FILE}" 2>&1; then
            install_ok=1
        elif code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -Fxq "${ext_lower}"; then
            # 即使命令退出码非零，若 VS Code 中实际已存在该扩展，也判定为成功
            install_ok=1
        fi

        if [ ${install_ok} -eq 1 ]; then
            echo "${ext}" >> "${PROVISIONED_FILE}"
            ((success_count++)) || true
            echo "✔ 成功安装: ${ext}" >> "${LOG_FILE}"
        else
            echo "✖ 安装失败: ${ext}" >> "${LOG_FILE}"
        fi
    done

    echo "==> [$(date '+%Y-%m-%d %H:%M:%S')] 扩展安装结束，成功: ${success_count}/${#pending_extensions[@]}" >> "${LOG_FILE}"
) >/dev/null 2>&1 &
