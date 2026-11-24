#!/bin/zsh
# 动态检查一键跑：无头 Chrome（不弹窗口）+ 单人闯关自动玩 + 逐帧存图 + 核对帧号 + 统计闪烁
# 用法：tools/dyncheck/run.sh <游戏网址，如 http://localhost:8066/?test=1> <关卡，如 1,4,7,10> <输出目录>
# 服务端要先用 DM_EVENTS=none DM_ROUND_T=120 ./server.sh 端口 起好（关掉随机事件、关卡加长）。环境变量 N=每段帧数（默认 70）
cd "$(dirname "$0")/../.."; HERE=tools/dyncheck; OUT=${3:-/tmp/dyncheck}; mkdir -p "$OUT"
PROF=$(mktemp -d); CDP=${CDP:-9333}
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$PROF" --remote-debugging-port=$CDP --window-size=1920,1200 --use-angle=metal --enable-gpu --ignore-gpu-blocklist about:blank >/dev/null 2>&1 &
for i in $(seq 1 40); do curl -s http://127.0.0.1:$CDP/json >/dev/null && break; sleep 0.5; done; sleep 1
rm -f shots/dump_*.png(N)
CDP=$CDP TLMAX=${TLMAX:-115} TLMIN=${TLMIN:-80} N=${N:-70} node $HERE/capture.mjs "$OUT" "$1" "$2"
pkill -f "user-data-dir=$PROF"; rm -rf "$PROF"
for f in shots/dump_*.png(N); do b=${f:t}; seg=$(echo $b | sed -E 's/^dump_(.*)_[0-9]{3}_f[0-9]+\.png$/\1/'); idx=$(echo $b | sed -E 's/.*_([0-9]{3})_f[0-9]+\.png/\1/'); fr=$(echo $b | sed -E 's/.*_f([0-9]+)\.png/\1/'); mkdir -p "$OUT/$seg"; mv "$f" "$OUT/$seg/$idx.png"; echo "$idx $fr" >> "$OUT/$seg/frames.txt"; done
for d in "$OUT"/*/(N); do [ -f "$d/frames.txt" ] || continue; sort -o "$d/frames.txt" "$d/frames.txt"
  node -e "const L=require('fs').readFileSync('$d/frames.txt','utf8').trim().split('\n').map(l=>l.split(' ').map(Number));let g=0;for(let i=1;i<L.length;i++)if(L[i][1]-L[i-1][1]!==1)g++;console.log('${d:t}','帧数',L.length,'帧号',L[0][1],'到',L.at(-1)[1],'不连续处',g)"
  node $HERE/shake.mjs "$d"; node $HERE/still.mjs "$d" | head -1; node $HERE/flip.mjs "$d"; node $HERE/median.mjs "$d"; done
