#!/bin/sh
cd "$(dirname "$0")" || exit 1

if ! command -v node >/dev/null 2>&1 || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' >/dev/null 2>&1; then
    echo '需要 Node.js 24 或更新版本。请到 nodejs.org 下载安装，再重新双击启动脚本。'
    printf '按回车退出。'
    read -r ignored
    exit 1
fi

exec node server/launch.mjs
