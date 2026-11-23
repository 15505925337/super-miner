#!/bin/bash
# 启动服务端（同时把导出好的网页版发给浏览器）。用法：./server.sh [端口，默认 8060]
# 默认只允许本机访问；要让同一 WiFi 的设备进来：HOST=0.0.0.0 ./server.sh
cd "$(dirname "$0")"
exec node server/src/main.ts "$@"
