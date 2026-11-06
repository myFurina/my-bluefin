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
    case "{{ACTION}}" in
        "stop")
            systemctl --user stop sunshine
            echo "🛑 Sunshine 串流服务已停止"
            ;;
        "restart")
            systemctl --user restart sunshine
            echo "🔄 Sunshine 串流服务已重启"
            ts_ip=$(tailscale ip -4 2>/dev/null || true)
            echo "💻 本机配对控制台: https://localhost:47990"
            [ -n "$ts_ip" ] && echo "🌐 Tailscale 远程控制台: https://${ts_ip}:47990"
            ;;
        "status")
            systemctl --user status sunshine
            ;;
        "logs")
            journalctl --user -u sunshine -f
            ;;
        *)
            if systemctl --user is-active --quiet sunshine; then
                echo "🟢 Sunshine 正在运行中"
                ts_ip=$(tailscale ip -4 2>/dev/null || true)
                echo "💻 本机配对控制台: https://localhost:47990"
                [ -n "$ts_ip" ] && echo "🌐 Tailscale 远程控制台: https://${ts_ip}:47990"
                echo "💡 提示: 若要停止服务，可运行 'ujust sunshine stop'"
            else
                echo "🚀 正在启动 Sunshine 串流服务..."
                systemctl --user start sunshine
                sleep 1
                if systemctl --user is-active --quiet sunshine; then
                    echo "✅ Sunshine 启动成功！"
                    ts_ip=$(tailscale ip -4 2>/dev/null || true)
                    echo "💻 本机配对控制台: https://localhost:47990"
                    [ -n "$ts_ip" ] && echo "🌐 Tailscale 远程控制台: https://${ts_ip}:47990"
                    echo "💡 首次打开若提示自签名证书不安全，点击高级并继续即可。"
                else
                    echo "⚠️ Sunshine 服务未能处于 active 状态，请通过 'ujust sunshine logs' 查看日志"
                fi
            fi
            ;;
    esac
