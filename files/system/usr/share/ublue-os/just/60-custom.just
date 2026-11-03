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
