#!/bin/bash
# 运行桌面版。用法：./run.sh            （窗口里按 1/2/3 换画质，L 开关光影，空格或点击放钩）
#               ./run.sh --q=mid      （直接指定画质等参数，参数说明见 scripts/main.gd 开头）
cd "$(dirname "$0")"
GODOT="${GODOT:-.tools/Godot.app/Contents/MacOS/Godot}"
[ -d .godot/imported ] || "$GODOT" --headless --path . --import >/dev/null 2>&1
exec "$GODOT" --path . -- "$@"
