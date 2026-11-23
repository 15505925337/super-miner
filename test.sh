#!/bin/bash
# 跑服务端的自动测试（规则、商店还价、房间、联网）。
cd "$(dirname "$0")/server"
exec node --test "test/*.test.ts"
