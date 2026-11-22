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

    # 若系统目录已预置该扩展（例如基础镜像已包含的 caffeine 或经典菜单组件），直接就绪无需网络拉取
    if [ -d "/usr/share/gnome-shell/extensions/${ITEM}" ] && [ -f "/usr/share/gnome-shell/extensions/${ITEM}/metadata.json" ]; then
        echo "==> 检测到 [${ITEM}] 已预装于系统扩展目录中，跳过在线下载，直接就绪并纳入激活。"
        continue
    fi

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

# ==============================================================================
# 9. 智能动态闭环：继承上游 Bluefin 官方扩展，并自动激活本次安装的扩展
# ==============================================================================
echo "------------------------------------------------------------------------------"
echo "==> 正在智能合并上游 Bluefin 官方扩展与自定义扩展清单..."
python3 - "${INSTALL_ITEMS}" << 'PYEOF'
import os
import re
import sys

raw_declared = sys.argv[1].split() if len(sys.argv) > 1 else []
SCHEMAS_DIR = "/usr/share/glib-2.0/schemas"
EXT_BASE = "/usr/share/gnome-shell/extensions"

# 1. 动态嗅探上游官方当天生效的所有默认扩展清单
upstream_exts = []
if os.path.isdir(SCHEMAS_DIR):
    for fname in sorted(os.listdir(SCHEMAS_DIR)):
        if fname.endswith(".override") and not fname.startswith("zz1-custom"):
            try:
                with open(os.path.join(SCHEMAS_DIR, fname), "r", encoding="utf-8") as f:
                    content = f.read()
                match = re.search(r'enabled-extensions\s*=\s*\[(.*?)\]', content, re.DOTALL)
                if match:
                    for item in re.findall(r"['\"]([^'\"]+)['\"]", match.group(1)):
                        if item not in upstream_exts:
                            upstream_exts.append(item)
            except Exception:
                pass

# 2. 物理扫描磁盘中实际安装成功的扩展
installed_exts = set()
if os.path.isdir(EXT_BASE):
    installed_exts = {d for d in os.listdir(EXT_BASE) if os.path.isdir(os.path.join(EXT_BASE, d))}

# 3. 动态合并：
# 优先保留上游官方项（仅当其确实安装在系统中）
final_list = []
for ext in upstream_exts:
    if ext in installed_exts and ext not in final_list:
        final_list.append(ext)

# 追加本次声明安装的自定义扩展（仅当其切实存在）
for ext in raw_declared:
    if ext in installed_exts and ext not in final_list:
        final_list.append(ext)

print(f"==> 成功合并 {len(final_list)} 个系统级扩展 (含官方与自定义):")
for ext in final_list:
    src_label = "【上游官方】" if ext in upstream_exts else "【声明追加】"
    print(f"    + {src_label} {ext}")

# 4. 生成自适应高优先级 override 文件
os.makedirs(SCHEMAS_DIR, exist_ok=True)
target_file = os.path.join(SCHEMAS_DIR, "zz1-custom-extensions.gschema.override")
with open(target_file, "w", encoding="utf-8") as f:
    f.write(f"[org.gnome.shell]\nenabled-extensions={final_list}\n")

PYEOF

# 立即编译全局 GSettings Schemas 确保开箱即用
glib-compile-schemas /usr/share/glib-2.0/schemas/

echo "=============================================================================="
echo "==> [smart-gnome-extensions] 所有声明扩展处理完毕并已成功与官方清单合并激活。"
echo "=============================================================================="
