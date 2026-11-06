# vim: set ft=make :

# 系统出厂自愈与还原 (System Reset & Recovery)
[group('System')]
reset-system:
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-factory-reset

# reset-system 快捷别名
[group('System')]
factory-reset:
    @ujust reset-system

# 系统快照与时光机还原面板 (Snapshot & Time Machine TUI)
[group('Snapshot')]
snapshot:
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot

# 创建系统与数据完整快照 (Create full system snapshot)
[group('Snapshot')]
snapshot-create NAME="":
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot create "{{NAME}}"

# 查看所有系统快照历史 (List system snapshots)
[group('Snapshot')]
snapshot-list:
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot list

# 还原指定系统快照 (Restore a system snapshot)
[group('Snapshot')]
snapshot-restore ID="":
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot restore "{{ID}}"

# 删除指定系统快照 (Delete a system snapshot)
[group('Snapshot')]
snapshot-delete ID="":
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot delete "{{ID}}"

# Sunshine 游戏串流服务启停与管理 (Sunshine GameStream Management)
[group('Streaming')]
sunshine ACTION="toggle":
    #!/usr/bin/env bash
    conf_dir="$HOME/.config/sunshine"
    conf_file="${conf_dir}/sunshine.conf"
    svc="app-dev.lizardbyte.app.Sunshine.service"
    if systemctl --user list-unit-files sunshine.service &>/dev/null; then
        svc="sunshine.service"
    fi

    ensure_sunshine_config() {
        ts_ip=$(tailscale ip -4 2>/dev/null || true)
        if [ -z "$ts_ip" ]; then
            echo "⚠️ 未检测到有效 Tailscale IP，为确保校园网完全隐身，已阻止启动。"
            echo "💡 请先启动并登录 Tailscale（可运行 'tailscale status' 检查连接状态）。"
            return 1
        fi
        mkdir -p "$conf_dir"
        [ ! -f "$conf_file" ] && touch "$conf_file"

        # 1. 动态绑定 Tailscale IP，物理校园网完全隐身
        if grep -q "^[[:space:]]*bind_address" "$conf_file"; then
            sed -i "s|^[[:space:]]*bind_address.*|bind_address = ${ts_ip}|" "$conf_file"
        else
            echo "bind_address = ${ts_ip}" >> "$conf_file"
        fi

        # 2. 固化使用成熟的 Intel 硬件级 VA-API 编码器（彻底杜绝 Mesa Vulkan 上游段错误 Bug）
        if grep -q "^[[:space:]]*encoder" "$conf_file"; then
            sed -i "s|^[[:space:]]*encoder.*|encoder = vaapi|" "$conf_file"
        else
            echo "encoder = vaapi" >> "$conf_file"
        fi
        return 0
    }

    case "{{ACTION}}" in
        "stop")
            systemctl --user stop "$svc"
            echo "🛑 Sunshine 串流服务已停止"
            ;;
        "restart")
            if ! ensure_sunshine_config; then
                exit 1
            fi
            systemctl --user restart "$svc"
            echo "🔄 Sunshine 串流服务已重启（已绑定至 Tailscale: ${ts_ip}，编码器: vaapi）"
            echo "🌐 控制台地址: https://${ts_ip}:47990"
            ;;
        "status")
            systemctl --user status "$svc"
            ;;
        "logs")
            journalctl --user -u "$svc" -f
            ;;
        *)
            if systemctl --user is-active --quiet "$svc"; then
                ts_ip=$(tailscale ip -4 2>/dev/null || true)
                echo "🟢 Sunshine 正在运行中（校园网完全隐身模式）"
                if [ -n "$ts_ip" ]; then
                    echo "🌐 控制台地址: https://${ts_ip}:47990"
                fi
                echo "💡 提示: 若要停止服务，可运行 'ujust sunshine stop'"
            else
                if ! ensure_sunshine_config; then
                    exit 1
                fi
                echo "🚀 正在启动 Sunshine 串流服务（绑定至 Tailscale: ${ts_ip}，编码器: vaapi，校园网完全隐身）..."
                systemctl --user start "$svc"
                sleep 1
                if systemctl --user is-active --quiet "$svc"; then
                    echo "✅ Sunshine 启动成功！"
                    echo "🌐 Web 管理控制台: https://${ts_ip}:47990"
                    echo "🔒 隐私安全状态: 物理校园网零暴露，仅限 Tailscale 设备可连接"
                    echo "💡 首次打开若提示自签名证书不安全，点击高级并继续即可。"
                else
                    echo "⚠️ Sunshine 服务未能处于 active 状态，请通过 'ujust sunshine logs' 查看日志"
                fi
            fi
            ;;
    esac
