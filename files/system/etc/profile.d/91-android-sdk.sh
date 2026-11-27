# Android SDK & JDK 21 用户级开发环境注入（与 environment.d/20-android.conf 保持一致）
if [ -d /usr/lib/jvm/java-21-openjdk ] && [ -z "${JAVA_HOME:-}" ]; then
    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
fi

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"

for _android_bin in \
    "$ANDROID_HOME/cmdline-tools/latest/bin" \
    "$ANDROID_HOME/platform-tools" \
    "$ANDROID_HOME/emulator"; do
    if [ -d "$_android_bin" ]; then
        case ":$PATH:" in
            *":$_android_bin:"*) ;;
            *) export PATH="$_android_bin:$PATH" ;;
        esac
    fi
done
unset _android_bin
