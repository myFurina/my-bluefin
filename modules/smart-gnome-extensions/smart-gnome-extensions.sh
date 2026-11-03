#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动智能 GNOME 扩展模块 (smart-gnome-extensions)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"

# 1. 解析需要安装的扩展声明列表
INSTALL_ITEMS=$(echo "${CONFIG_JSON}" | jq -r 'try .install[] // empty')

if [ -z "${INSTALL_ITEMS}" ]; then
    echo "==> [smart-gnome-extensions] 未声明需要安装的扩展，模块任务完成。"
    exit 0
fi

# 2. 检测当前系统或容器内的 GNOME 大版本
SYSTEM_GNOME_VER=$(gnome-shell --version 2>/dev/null | grep -Eo '[0-9]+' | head -n 1 || true)
if [ -z "${SYSTEM_GNOME_VER}" ]; then
    SYSTEM_GNOME_VER=$(rpm -q --qf '%{VERSION}' gnome-shell 2>/dev/null | grep -Eo '^[0-9]+' || echo "47")
fi
echo "==> 检测到当前容器环境 GNOME 大版本: [${SYSTEM_GNOME_VER}]"

# 3. 逐个处理扩展安装
for ITEM in ${INSTALL_ITEMS}; do
    echo "------------------------------------------------------------------------------"
    echo "==> 正在检索并解析扩展: [${ITEM}]..."

    # 对查询词进行 URL 编码
    ENCODED_QUERY=$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "${ITEM}")

    API_RESPONSE=$(curl -sSL --connect-timeout 15 --retry 3 "https://extensions.gnome.org/extension-query/?search=${ENCODED_QUERY}" || true)

    if [ -z "${API_RESPONSE}" ]; then
        echo "==> 错误: 无法从 extensions.gnome.org 获取 [${ITEM}] 的查询结果，网络请求失败。"
        continue
    fi

    # 通过 Python 解析返回结果并执行精准匹配与兜底决策
    PARSED_INFO=$(python3 -c '
import sys, json

query = sys.argv[1].strip()
target_ver = sys.argv[2].strip()

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

extensions = data.get("extensions", [])
if not extensions:
    sys.exit(2)

# 1. 优先根据 UUID 精确匹配，其次根据显示名称 (大小写无关) 精确匹配，最后退化为第一个匹配项
matched_ext = None
for ext in extensions:
    if ext.get("uuid", "").strip() == query:
        matched_ext = ext
        break

if not matched_ext:
    for ext in extensions:
        if ext.get("name", "").strip().lower() == query.lower():
            matched_ext = ext
            break

if not matched_ext:
    matched_ext = extensions[0]

uuid = matched_ext.get("uuid", "")
name = matched_ext.get("name", uuid)
svm = matched_ext.get("shell_version_map", {})

if not uuid or not svm:
    sys.exit(3)

# 2. 版本决策：优先精准匹配目标 GNOME 版本，未匹配时回退到最新可用构建
if target_ver in svm:
    strategy = "EXACT"
    pk = svm[target_ver]["pk"]
else:
    strategy = "FALLBACK"
    # 获取最大的 pk 构建号
    pk = max(x["pk"] for x in svm.values())

print(f"{uuid}\t{name}\t{strategy}\t{pk}")
' "${ITEM}" "${SYSTEM_GNOME_VER}" <<< "${API_RESPONSE}" 2>/dev/null || true)

    if [ -z "${PARSED_INFO}" ]; then
        echo "==> 警告: 在 extensions.gnome.org 未能匹配到 [${ITEM}] 的有效构建信息，跳过。"
        continue
    fi

    EXT_UUID=$(echo "${PARSED_INFO}" | awk -F'\t' '{print $1}')
    EXT_NAME=$(echo "${PARSED_INFO}" | awk -F'\t' '{print $2}')
    EXT_STRATEGY=$(echo "${PARSED_INFO}" | awk -F'\t' '{print $3}')
    EXT_PK=$(echo "${PARSED_INFO}" | awk -F'\t' '{print $4}')

    if [ "${EXT_STRATEGY}" = "EXACT" ]; then
        echo "==> 成功匹配精准版本构建 [${EXT_NAME}] (${EXT_UUID}) -> Version Tag: ${EXT_PK}"
    else
        echo "==> 提示: 上游未发布针对 GNOME [${SYSTEM_GNOME_VER}] 的独立版本，触发自动兜底 -> 回退至最新构建 Version Tag: ${EXT_PK}"
    fi

    # 4. 下载并部署扩展包
    TARGET_DIR="/usr/share/gnome-shell/extensions/${EXT_UUID}"
    TMP_ZIP="/tmp/${EXT_UUID}.zip"

    mkdir -p "${TARGET_DIR}"
    echo "==> 正在下载构建包: https://extensions.gnome.org/download-extension/${EXT_UUID}.shell-extension.zip?version_tag=${EXT_PK} ..."
    curl -sSL --connect-timeout 15 --retry 3 \
        "https://extensions.gnome.org/download-extension/${EXT_UUID}.shell-extension.zip?version_tag=${EXT_PK}" \
        -o "${TMP_ZIP}"

    unzip -qo "${TMP_ZIP}" -d "${TARGET_DIR}/"
    rm -f "${TMP_ZIP}"

    # 5. 动态核验与放宽 metadata.json 兼容版本号
    META_FILE="${TARGET_DIR}/metadata.json"
    if [ -f "${META_FILE}" ]; then
        python3 -c '
import sys, json

meta_path = sys.argv[1]
target_ver = sys.argv[2]

try:
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    shell_versions = meta.get("shell-version", [])
    if target_ver not in shell_versions:
        shell_versions.append(target_ver)
        meta["shell-version"] = shell_versions
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
        print(f"==> 已动态注入兼容版本 [{target_ver}] 至 metadata.json")
except Exception as e:
    print(f"==> 警告: 修改 metadata.json 兼容版本出现异常: {e}")
' "${META_FILE}" "${SYSTEM_GNOME_VER}" 2>/dev/null || true
    fi

    # 6. 统一规范权限
    chmod -R a+rX "${TARGET_DIR}/"

    # 7. 提取与编译 GSchema
    if [ -d "${TARGET_DIR}/schemas" ]; then
        mkdir -p /usr/share/glib-2.0/schemas
        cp -r "${TARGET_DIR}/schemas"/*.gschema.xml /usr/share/glib-2.0/schemas/ 2>/dev/null || true
        glib-compile-schemas "${TARGET_DIR}/schemas/" 2>/dev/null || true
        glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
    fi

    # 8. 规范安装语言包
    if [ -d "${TARGET_DIR}/locale" ]; then
        mkdir -p /usr/share/locale
        cp -r "${TARGET_DIR}/locale"/* /usr/share/locale/ 2>/dev/null || true
    fi

    echo "==> [${EXT_NAME}] (${EXT_UUID}) 部署集成完成！"
done

echo "=============================================================================="
echo "==> [smart-gnome-extensions] 所有声明扩展处理完毕。"
echo "=============================================================================="
