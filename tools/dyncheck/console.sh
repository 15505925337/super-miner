#!/bin/zsh
# 用法：tools/dyncheck/console.sh <端口>  —— 无头 Chrome 打开四层超高档、高档演示局，各等 8 秒，打印控制台里的着色器和脚本错误
PROF=$(mktemp -d)
pkill -f "user-data-dir=$PROF"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$PROF" --remote-debugging-port=9334 --window-size=1920,1200 --use-angle=metal --enable-gpu --ignore-gpu-blocklist about:blank >/dev/null 2>&1 &
for i in $(seq 1 40); do curl -s http://127.0.0.1:9334/json >/dev/null && break; sleep 0.5; done; sleep 1
node -e "
(async()=>{const l=await (await fetch('http://127.0.0.1:9334/json')).json();const p=l.find(x=>x.type==='page');const ws=new WebSocket(p.webSocketDebuggerUrl);await new Promise(r=>ws.onopen=r);let id=0,logs=[];
ws.addEventListener('message',e=>{const d=JSON.parse(e.data);if(d.method==='Runtime.consoleAPICalled'&&d.params.type==='error'){const t=d.params.args.map(a=>a.value??a.description).join(' ');if(!/invalid UID|resource_format_binary/.test(t))logs.push(t.slice(0,200))}});
const call=(m,params)=>new Promise(r=>{const i=++id;ws.addEventListener('message',e=>{const d=JSON.parse(e.data);if(d.id===i)r(d.result)});ws.send(JSON.stringify({id:i,method:m,params}))});await call('Runtime.enable',{});
for(const q of ['ultra','high'])for(const t of [0,1,2,3]){logs=[];await call('Page.navigate',{url:'http://localhost:$1/?demo=1&tier='+t+'&q='+q});await new Promise(r=>setTimeout(r,8000));const bad=logs.filter(x=>/shader|SHADER|SCRIPT ERROR|failed/i.test(x));console.log(q,'第',t,'层：错误',logs.length,'条，其中着色器或脚本',bad.length,'条',bad.slice(0,3).join(' | '))}
ws.close()})()"
pkill -f "user-data-dir=$PROF"
