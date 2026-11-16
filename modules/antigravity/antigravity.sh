#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "==> 启动 Google Antigravity IDE 部署模块 (antigravity)..."
echo "=============================================================================="

CONFIG_JSON="${1:-"{}"}"
INSTALL_DIR=$(echo "${CONFIG_JSON}" | jq -r 'try .install_dir // empty')
INSTALL_DIR="${INSTALL_DIR:-/usr/lib/antigravity}"
BIN_LINK=$(echo "${CONFIG_JSON}" | jq -r 'try .bin_link // empty')
BIN_LINK="${BIN_LINK:-/usr/bin/antigravity}"

echo "==> 正在精准解析 Google 官方最新版 Antigravity IDE..."
HTML_PAGE=$(curl -sfSL --connect-timeout 10 --retry 2 "https://antigravity.google/download" 2>/dev/null || true)
UPDATER_API=$(printf '%s' "${HTML_PAGE}" | grep -Eo 'https://[a-zA-Z0-9.-]+\.run\.app/releases' | head -n 1 || true)
UPDATER_API="${UPDATER_API:-https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/releases}"

RELEASE_JSON=$(curl -sfSL --connect-timeout 15 --retry 3 "${UPDATER_API}" 2>/dev/null || true)
RELEASE_INFO=$(printf '%s' "${RELEASE_JSON}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    latest = data[0]
    print(str(latest["version"]) + "-" + str(latest["execution_id"]))
except Exception:
    pass
' 2>/dev/null || true)

if [ -z "${RELEASE_INFO}" ]; then
    echo "==> 警告: 无法解析 Antigravity 最新发布版本，跳过在线下载。"
    exit 0
fi

DOWNLOAD_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${RELEASE_INFO}/linux-x64/Antigravity.tar.gz"
echo "==> 检测到最新版本 [${RELEASE_INFO}]，开始下载并安装至 ${INSTALL_DIR}: ${DOWNLOAD_URL}"

mkdir -p "${INSTALL_DIR}"
TMP_TAR="/tmp/Antigravity.tar.gz"

curl -sfSL --connect-timeout 15 --retry 3 "${DOWNLOAD_URL}" -o "${TMP_TAR}"
tar -xzf "${TMP_TAR}" -C "${INSTALL_DIR}" --strip-components=1
rm -f "${TMP_TAR}"

chmod 755 "${INSTALL_DIR}/antigravity"
mkdir -p "$(dirname "${BIN_LINK}")"
ln -sf "${INSTALL_DIR}/antigravity" "${BIN_LINK}"

# 自动修复 Linux (GNOME/Wayland/分数缩放) 冷启动最大化时 hubWcv 尺寸未同步导致右半边留白的 Bug
ASAR_PATH="${INSTALL_DIR}/resources/app.asar"
if [ -f "${ASAR_PATH}" ]; then
    echo "==> 正在检查并修补 app.asar 最大化视口同步补丁..."
    python3 - "${ASAR_PATH}" <<'PYEOF'
import hashlib
import json
import os
import re
import struct
import sys

asar_path = sys.argv[1]

with open(asar_path, "rb") as f:
    header_prefix = f.read(16)
    if len(header_prefix) < 16:
        raise RuntimeError("Invalid asar header")
    u0, hdr_size, obj_size, str_size = struct.unpack("<IIII", header_prefix)
    hdr_json_bytes = f.read(str_size)
    hdr = json.loads(hdr_json_bytes.decode("utf-8"))
    data_start = 8 + hdr_size
    f.seek(0, os.SEEK_END)
    total_size = f.tell()
    f.seek(data_start)
    payload_blob = f.read(total_size - data_start)


def read_entry_bytes(entry):
    offset = int(entry["offset"])
    size = int(entry["size"])
    return payload_blob[offset : offset + size]


def compute_integrity(raw_bytes, block_size=4194304):
    overall = hashlib.sha256(raw_bytes).hexdigest()
    blocks = []
    if len(raw_bytes) == 0:
        blocks.append(overall)
    else:
        for i in range(0, len(raw_bytes), block_size):
            blocks.append(hashlib.sha256(raw_bytes[i : i + block_size]).hexdigest())
    return {
        "algorithm": "SHA256",
        "hash": overall,
        "blockSize": block_size,
        "blocks": blocks,
    }


def get_entry(root, rel_path):
    node = root
    for part in rel_path.split("/"):
        files = node.get("files")
        if not isinstance(files, dict) or part not in files:
            return None
        node = files[part]
    return node


def patch_utils_js(text):
    if "syncHubViewBounds.cleanup" in text:
        return text, False

    pattern_sync = re.compile(
        r"(?P<indent>[ \t]*)syncHubViewBounds = \(\) => \{\n"
        r"(?P=indent)[ \t]*if \(!baseWin\.isDestroyed\?\.\(\) && !hubWcv\.webContents\?\.isDestroyed\?\.\(\)\) \{\n"
        r"(?P=indent)[ \t]*const \[width, height\] = baseWin\.getContentSize\(\);\n"
        r"(?P=indent)[ \t]*curtainView\?\.setBounds\(\{ x: 0, y: 0, width, height \}\);\n"
        r"(?P=indent)[ \t]*hubWcv\.setBounds\(\{ x: 0, y: 0, width, height \}\);\n"
        r"(?P=indent)[ \t]*\}\n"
        r"(?P=indent)\};\n"
        r"(?P=indent)syncHubViewBounds\(\);\n"
        r"(?P=indent)baseWin\.on\('resize', syncHubViewBounds\);"
    )
    m = pattern_sync.search(text)
    if not m:
        return text, None

    ind = m.group("indent")
    replacement = (
        f"{ind}let syncHubViewBoundsTimers = [];\n"
        f"{ind}const clearSyncHubViewBoundsTimers = () => {{\n"
        f"{ind}    for (const timer of syncHubViewBoundsTimers) {{\n"
        f"{ind}        clearTimeout(timer);\n"
        f"{ind}    }}\n"
        f"{ind}    syncHubViewBoundsTimers = [];\n"
        f"{ind}}};\n"
        f"{ind}const applyHubViewBounds = () => {{\n"
        f"{ind}    if (!baseWin.isDestroyed?.() && !hubWcv.webContents?.isDestroyed?.()) {{\n"
        f"{ind}        const [width, height] = baseWin.getContentSize();\n"
        f"{ind}        if (width > 0 && height > 0) {{\n"
        f"{ind}            curtainView?.setBounds({{ x: 0, y: 0, width, height }});\n"
        f"{ind}            hubWcv.setBounds({{ x: 0, y: 0, width, height }});\n"
        f"{ind}        }}\n"
        f"{ind}    }}\n"
        f"{ind}}};\n"
        f"{ind}syncHubViewBounds = () => {{\n"
        f"{ind}    applyHubViewBounds();\n"
        f"{ind}    clearSyncHubViewBoundsTimers();\n"
        f"{ind}    syncHubViewBoundsTimers = [\n"
        f"{ind}        setTimeout(applyHubViewBounds, 50),\n"
        f"{ind}        setTimeout(applyHubViewBounds, 200),\n"
        f"{ind}        setTimeout(applyHubViewBounds, 500),\n"
        f"{ind}        setTimeout(applyHubViewBounds, 1000),\n"
        f"{ind}    ];\n"
        f"{ind}}};\n"
        f"{ind}syncHubViewBounds.cleanup = () => {{\n"
        f"{ind}    clearSyncHubViewBoundsTimers();\n"
        f"{ind}    baseWin.off?.('resize', applyHubViewBounds);\n"
        f"{ind}    baseWin.off?.('show', syncHubViewBounds);\n"
        f"{ind}    baseWin.off?.('maximize', syncHubViewBounds);\n"
        f"{ind}    baseWin.off?.('unmaximize', syncHubViewBounds);\n"
        f"{ind}    baseWin.off?.('restore', syncHubViewBounds);\n"
        f"{ind}    baseWin.off?.('enter-full-screen', syncHubViewBounds);\n"
        f"{ind}    baseWin.off?.('leave-full-screen', syncHubViewBounds);\n"
        f"{ind}    hubWcv.webContents?.off?.('did-finish-load', syncHubViewBounds);\n"
        f"{ind}}};\n"
        f"{ind}syncHubViewBounds();\n"
        f"{ind}baseWin.on('resize', applyHubViewBounds);\n"
        f"{ind}baseWin.on('show', syncHubViewBounds);\n"
        f"{ind}baseWin.on('maximize', syncHubViewBounds);\n"
        f"{ind}baseWin.on('unmaximize', syncHubViewBounds);\n"
        f"{ind}baseWin.on('restore', syncHubViewBounds);\n"
        f"{ind}baseWin.on('enter-full-screen', syncHubViewBounds);\n"
        f"{ind}baseWin.on('leave-full-screen', syncHubViewBounds);\n"
        f"{ind}hubWcv.webContents.once('did-finish-load', syncHubViewBounds);"
    )
    text = text[: m.start()] + replacement + text[m.end() :]

    pattern_cleanup = re.compile(
        r"(?P<indent>[ \t]*)if \(syncHubViewBounds\) \{\n"
        r"(?P=indent)[ \t]*win\.off\?\.\('resize', syncHubViewBounds\);\n"
        r"(?P=indent)\}"
    )
    mc = pattern_cleanup.search(text)
    if mc:
        cind = mc.group("indent")
        crepl = (
            f"{cind}if (syncHubViewBounds) {{\n"
            f"{cind}    win.off?.('resize', syncHubViewBounds);\n"
            f"{cind}    syncHubViewBounds.cleanup?.();\n"
            f"{cind}}}"
        )
        text = text[: mc.start()] + crepl + text[mc.end() :]

    return text, True


def patch_loading_overlay_js(text):
    if "scheduleOverlayBounds" in text:
        return text, False

    pattern_attach = re.compile(
        r"(?P<indent>[ \t]*)updateBounds\(\);\n"
        r"(?P=indent)win\.on\('resize', updateBounds\);"
    )
    pattern_cleanup = re.compile(
        r"(?P<indent>[ \t]*)if \(!win\.isDestroyed\?\.\(\)\) \{\n"
        r"(?P=indent)[ \t]*win\.off\?\.\('resize', updateBounds\);\n"
        r"(?P=indent)\}"
    )
    m1 = pattern_attach.search(text)
    m2 = pattern_cleanup.search(text)
    if not m1 or not m2:
        return text, None

    ind1 = m1.group("indent")
    repl1 = (
        f"{ind1}let overlayBoundsTimers = [];\n"
        f"{ind1}const clearOverlayBoundsTimers = () => {{\n"
        f"{ind1}    for (const timer of overlayBoundsTimers) clearTimeout(timer);\n"
        f"{ind1}    overlayBoundsTimers = [];\n"
        f"{ind1}}};\n"
        f"{ind1}const scheduleOverlayBounds = () => {{\n"
        f"{ind1}    updateBounds();\n"
        f"{ind1}    clearOverlayBoundsTimers();\n"
        f"{ind1}    overlayBoundsTimers = [setTimeout(updateBounds, 50), setTimeout(updateBounds, 200)];\n"
        f"{ind1}}};\n"
        f"{ind1}scheduleOverlayBounds();\n"
        f"{ind1}win.on('resize', updateBounds);\n"
        f"{ind1}win.on('show', scheduleOverlayBounds);\n"
        f"{ind1}win.on('maximize', scheduleOverlayBounds);\n"
        f"{ind1}win.on('unmaximize', scheduleOverlayBounds);\n"
        f"{ind1}win.on('restore', scheduleOverlayBounds);\n"
        f"{ind1}win.on('enter-full-screen', scheduleOverlayBounds);\n"
        f"{ind1}win.on('leave-full-screen', scheduleOverlayBounds);"
    )
    text = text[: m1.start()] + repl1 + text[m1.end() :]

    m2 = pattern_cleanup.search(text)
    ind2 = m2.group("indent")
    repl2 = (
        f"{ind2}clearOverlayBoundsTimers();\n"
        f"{ind2}if (!win.isDestroyed?.()) {{\n"
        f"{ind2}    win.off?.('resize', updateBounds);\n"
        f"{ind2}    win.off?.('show', scheduleOverlayBounds);\n"
        f"{ind2}    win.off?.('maximize', scheduleOverlayBounds);\n"
        f"{ind2}    win.off?.('unmaximize', scheduleOverlayBounds);\n"
        f"{ind2}    win.off?.('restore', scheduleOverlayBounds);\n"
        f"{ind2}    win.off?.('enter-full-screen', scheduleOverlayBounds);\n"
        f"{ind2}    win.off?.('leave-full-screen', scheduleOverlayBounds);\n"
        f"{ind2}}}"
    )
    text = text[: m2.start()] + repl2 + text[m2.end() :]
    return text, True


overrides = {}
utils_entry = get_entry(hdr, "dist/utils.js")
if utils_entry and "offset" in utils_entry:
    utils_src = read_entry_bytes(utils_entry).decode("utf-8")
    utils_new, status = patch_utils_js(utils_src)
    if status is True:
        overrides["dist/utils.js"] = utils_new.encode("utf-8")
        print("==> [app.asar] 已注入 dist/utils.js 最大化/视口同步补丁")
    elif status is None:
        print("==> [app.asar] 警告: dist/utils.js 特征未匹配（可能上游已重构或修复），跳过该文件。")

overlay_entry = get_entry(hdr, "dist/loadingOverlay.js")
if overlay_entry and "offset" in overlay_entry:
    ov_src = read_entry_bytes(overlay_entry).decode("utf-8")
    ov_new, status = patch_loading_overlay_js(ov_src)
    if status is True:
        overrides["dist/loadingOverlay.js"] = ov_new.encode("utf-8")
        print("==> [app.asar] 已注入 dist/loadingOverlay.js 加载遮罩视口同步补丁")

if not overrides:
    print("==> [app.asar] 无需重写打包。")
    sys.exit(0)

new_chunks = []
running_offset = 0


def rebuild_tree(node, prefix=""):
    global running_offset
    files = node.get("files")
    if not isinstance(files, dict):
        return
    for name, entry in files.items():
        rel_path = f"{prefix}/{name}" if prefix else name
        if "files" in entry:
            rebuild_tree(entry, rel_path)
        elif "offset" in entry:
            raw = overrides[rel_path] if rel_path in overrides else read_entry_bytes(entry)
            entry["size"] = len(raw)
            entry["offset"] = str(running_offset)
            if "integrity" in entry:
                block_size = int(entry["integrity"].get("blockSize", 4194304))
                entry["integrity"] = compute_integrity(raw, block_size)
            new_chunks.append(raw)
            running_offset += len(raw)


rebuild_tree(hdr)

new_hdr_bytes = json.dumps(hdr, separators=(",", ":")).encode("utf-8")
pad_len = (4 - (len(new_hdr_bytes) % 4)) % 4
padded_len = len(new_hdr_bytes) + pad_len
new_u1 = padded_len + 8
new_u2 = padded_len + 4
new_u3 = len(new_hdr_bytes)

tmp_asar = asar_path + ".tmp"
with open(tmp_asar, "wb") as wf:
    wf.write(struct.pack("<IIII", 4, new_u1, new_u2, new_u3))
    wf.write(new_hdr_bytes)
    wf.write(b"\x00" * pad_len)
    for chunk in new_chunks:
        wf.write(chunk)

os.chmod(tmp_asar, 0o644)
os.replace(tmp_asar, asar_path)
print("==> [app.asar] 重新打包完成并校验成功！")
PYEOF
fi

echo "==> Antigravity IDE [${RELEASE_INFO}] 已成功部署至 ${INSTALL_DIR} 并软链至 ${BIN_LINK}！"
echo "=============================================================================="
