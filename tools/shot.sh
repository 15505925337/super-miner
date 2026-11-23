#!/bin/bash
# 桌面版截一张图存到 shots/<名字>.png。用法：tools/shot.sh <名字> <宽x高> [参数...]
cd "$(dirname "$0")/.."
name="$1"; res="$2"; shift 2
.tools/Godot.app/Contents/MacOS/Godot --path . --resolution "$res" -- --shot="$name" "$@" 2>&1 | grep -E "ERROR|WARN|SCRIPT|SHOT|at:" | head -20
