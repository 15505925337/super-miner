// 动态检查：无头 Chrome 里开单人闯关自动玩，指定关卡各存两段连续渲染帧（空摆、拉回），用游戏的 frameDump（test=1，固定步长）。
// 用法：见 README.md。输出：shots/dump_<关>_<段>_<序号>_f<帧号>.png
// 动态检查：独立 Chrome（调试端口 9333）里单人闯关自动玩，第 1/4/7/10 关各截整屏，并录"空摆"和"拉回"两段连续帧
import fs from 'node:fs';
const OUT = process.argv[2], URL0 = process.argv[3], LEVELS = (process.argv[4] || '1,4,7,10').split(',').map(Number);
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });
const l = await (await fetch('http://127.0.0.1:' + (process.env.CDP || 9333) + '/json')).json(); const p = l.find(x => x.type === 'page');
const ws = new WebSocket(p.webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id = 0; const waiters = {}; let frameSink = null;
ws.addEventListener('message', e => { const d = JSON.parse(e.data);
  if (d.id && waiters[d.id]) { waiters[d.id](d.result || d.error); delete waiters[d.id]; }
  if (d.method === 'Page.screencastFrame') { if (frameSink) frameSink.push({ t: d.params.metadata.timestamp, data: d.params.data }); call('Page.screencastFrameAck', { sessionId: d.params.sessionId }); } });
const call = (m, params = {}) => new Promise(r => { const i = ++id; waiters[i] = r; ws.send(JSON.stringify({ id: i, method: m, params })); });
const ev = async expr => (await call('Runtime.evaluate', { expression: expr, returnByValue: true })).result?.value;
const st = () => ev('window.dmState||null');
const push = c => ev(`(window.dmQ=window.dmQ||[]).push(${JSON.stringify(c)})`);
await call('Page.enable'); await call('Runtime.enable');
await call('Emulation.setDeviceMetricsOverride', { width: Number(process.env.W || 1920), height: Number(process.env.H || 1080), deviceScaleFactor: 1, mobile: false });
await call('Page.navigate', { url: URL0 });
for (let i = 0; i < 120; i++) { await sleep(500); const s = await st(); if (s && s.up) break; }
await sleep(800);
await push({ t: 'create', name: '测试', mode: 'solo', c: 0 });
for (let i = 0; i < 60; i++) { await sleep(300); const s = await st(); if (s && (s.ph === 'play' || s.ph === 'count')) break; }
await ev('window.dmAuto=true');
const SHOTS = process.env.SHOTS || new URL('../../shots', import.meta.url).pathname;
const N = Number(process.env.N || 70);
const countDump = name => fs.readdirSync(SHOTS).filter(f => f.startsWith(`dump_${name}_`)).length;
async function record(name) {
  await push({ t: 'frameDump', n: N, name }); const t0 = Date.now();
  while (countDump(name) < N && Date.now() - t0 < 180000) await sleep(400);
  log(name, '存了', countDump(name), '帧，用时', ((Date.now() - t0) / 1000).toFixed(1), '秒');
}
const done = new Set(); let lastShop = 0, lastOver = -1; const t0 = Date.now();
while (Date.now() - t0 < 60 * 60000 && done.size < LEVELS.length) {
  const s = await st(); if (!s) { await sleep(500); continue; }
  if (Date.now() - (globalThis.lastLog || 0) > 15000) { globalThis.lastLog = Date.now(); log('状态', s.ph, '第', s.rd, '关 tl', Math.round(s.tl), '钱', JSON.stringify(s.players && s.players.map(p => p.m)), '目标', s.tg, 'auto', await ev('window.dmAuto'), 'dump', JSON.stringify(s.dump || null)); }
  if (s.ph === 'shop' && lastShop !== s.rd) { lastShop = s.rd; await sleep(400); await push({ t: 'ready' }); }
  if ((s.ph === 'over' || s.ph === 'solo_over') && lastOver !== s.rd) { lastOver = s.rd; log('结束于第', s.rd, '关，再来一局'); await sleep(800); await push({ t: 'again' }); done.clear(); }
  if (s.ph === 'play' && LEVELS.includes(s.rd) && !done.has(s.rd) && s.tl < Number(process.env.TLMAX || 195) && s.tl > Number(process.env.TLMIN || 160)) {
    done.add(s.rd); const L = s.rd;
    const shot = await call('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(`${OUT}/L${L}_full.png`, Buffer.from(shot.data, 'base64'));
    await ev('window.dmAuto=false'); await sleep(1500);      // 等钩子收回、空摆
    for (let i = 0; i < 40; i++) { const q = await st(); if (q.players[0] && q.players[0].s === 0) break; await sleep(150); }
    await record(`L${L}_idle`, 3500);
    await ev('window.dmAuto=true');
    let ok = false; for (let i = 0; i < 80; i++) { const q = await st(); const ps = q.players[0]?.s; if (ps === 2 || ps === 4) { ok = true; break; } await sleep(80); }
    await record(`L${L}_haul${ok ? '' : '_x'}`, 3500);
    log('第', L, '关录完', 'tl', Math.round(s.tl));
  }
  await sleep(300);
}
await ev('window.dmAuto=false'); log('完成', [...done].join(',')); ws.close();
