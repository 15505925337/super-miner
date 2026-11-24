#!/bin/bash
# 跑一个联调脚本。用法：tools/e2e/run.sh smoke|local|vs|co|race|tiers
# 需要：服务端在跑（./server.sh）、网页版已导出（./export.sh --only）、本机装了 ego 浏览器。
# 会在 ego 里用一个名叫"深井夺金联调"的任务空间，里面开两个标签页，跑完留着下次接着用。
cd "$(dirname "$0")"
# 默认连 8060 的服务端；要连临时的短局服务端：BASE=http://localhost:8062/ tools/e2e/run.sh fun_vs
(echo "const SHOTS = \"$(cd ../.. && pwd)/shots/\";"; echo 'const SPACE = "深井夺金联调";'; echo "const BASE = \"${BASE:-http://localhost:8060/}\";"; cat lib.mjs "$1.mjs") | ego-browser nodejs
