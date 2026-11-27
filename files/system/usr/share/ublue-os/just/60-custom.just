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
    /usr/libexec/my-bluefin/system-snapshot create "{{ NAME }}"

# 查看所有系统快照历史 (List system snapshots)
[group('Snapshot')]
snapshot-list:
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot list

# 还原指定系统快照 (Restore a system snapshot)
[group('Snapshot')]
snapshot-restore ID="":
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot restore "{{ ID }}"

# 删除指定系统快照 (Delete a system snapshot)
[group('Snapshot')]
snapshot-delete ID="":
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/system-snapshot delete "{{ ID }}"

# Sunshine 游戏串流服务启停与管理 (Sunshine GameStream Management)
[group('Streaming')]
sunshine ACTION="toggle":
    #!/usr/bin/env bash
    exec /usr/libexec/my-bluefin/sunshine-gui-launcher "{{ ACTION }}"

# 初始化或修复本地 Android 16 (API 36) SDK 与 Gradle 国内镜像
[group('Android')]
android-setup:
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/android-sdk-manage setup

# 查看本地 Android 构建环境、已安装 SDK 与磁盘占用
[group('Android')]
android-status:
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/android-sdk-manage status

# 清理 Gradle 缓存或彻底清空用户态 Android SDK（防复活）
[group('Android')]
android-clean MODE="":
    #!/usr/bin/env bash
    /usr/libexec/my-bluefin/android-sdk-manage clean "{{ MODE }}"
