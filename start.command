#!/bin/sh
# macOS 在 Finder 双击这个入口，启动逻辑和 Linux 共用。
cd "$(dirname "$0")" || exit 1
exec ./start.sh
