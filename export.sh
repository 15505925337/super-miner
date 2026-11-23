#!/bin/bash
# 导出网页版到 build/web/。服务端没在跑的话顺手启动（服务端直接读 build/web，导出完刷新页面就是新的）。
# 用法：./export.sh          导出，并保证 http://localhost:8060/ 能打开
#       ./export.sh --only   只导出
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-.tools/Godot.app/Contents/MacOS/Godot}"
mkdir -p build/web
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" build/web/index.html 2>&1 | grep -E "ERROR|error" || true
echo "导出完成：$(du -sh build/web | cut -f1)"
[ "$1" = "--only" ] && exit 0
if curl -s -o /dev/null --max-time 2 http://localhost:8060/; then echo "服务端已经在跑：http://localhost:8060/"; else exec ./server.sh; fi
