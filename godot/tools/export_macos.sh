#!/usr/bin/env bash
# 打一份本机可双击的 macOS 测试包。
# 用法：在仓库根目录执行  bash godot/tools/export_macos.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/godot"
OUT_DIR="$ROOT/dist"
OUT_APP="$OUT_DIR/网吧经营模拟.app"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
VERSION="4.7.2.stable"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/$VERSION"
TPZ_URL="https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
TPZ_PATH="${TMPDIR:-/tmp}/Godot_v4.7.2-stable_export_templates.tpz"

if [[ ! -x "$GODOT" ]]; then
	echo "找不到 Godot：$GODOT"
	exit 1
fi

mkdir -p "$TEMPLATE_DIR" "$OUT_DIR"

if [[ ! -f "$TEMPLATE_DIR/macos.zip" ]]; then
	echo "本机没有 4.7.2 macOS 导出模板，开始下载（约 1.2GB，只解压 macOS）…"
	curl -L --fail --retry 3 -o "$TPZ_PATH" "$TPZ_URL"
	unzip -o "$TPZ_PATH" "templates/macos.zip" "templates/version.txt" -d "${TMPDIR:-/tmp}/godot-templates"
	mv -f "${TMPDIR:-/tmp}/godot-templates/templates/macos.zip" "$TEMPLATE_DIR/macos.zip"
	mv -f "${TMPDIR:-/tmp}/godot-templates/templates/version.txt" "$TEMPLATE_DIR/version.txt"
	echo "模板已装到 $TEMPLATE_DIR"
fi

rm -rf "$OUT_APP"
echo "正在导出 $OUT_APP"
"$GODOT" --path "$PROJECT" --headless --export-release "macOS" "$OUT_APP"
echo "完成：$OUT_APP"
echo "双击即可玩。若系统拦截，按住 Control 点图标再选打开。"
