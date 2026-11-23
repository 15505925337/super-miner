// 同一台设备多人 + 房间里的各种按钮 + 对局中用道具。一个页面就够。
const task = await taskSpace(SPACE);
const A = await open(task, "p1");
await front(A);
if ((await st(A)).ph !== "") { await A.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" })); await waitFor(A, "回首页", s => s.ph === ""); }
await click(A, "create_vs");
let s = await waitFor(A, "进房间", s => s.ph === "lobby");
const out = {};
await click(A, "mode_co"); s = await waitFor(A, "换成合作", s => s.mode === "co"); out.modeSwitch = s.mode;
await click(A, "mode_vs"); s = await waitFor(A, "换回对战", s => s.mode === "vs");
await click(A, "add_local"); await click(A, "add_local"); await click(A, "add_bot");
s = await waitFor(A, "四个人", s => s.players.length === 4);
out.seats = s.you.length; out.names = s.players.map(p => p.name + (p.bot ? "(电脑)" : ""));
out.fullDisabled = !s.rects.add_bot ? "按钮没了" : "还在";
await shot(A, "p2_local_1_lobby");
const bot = s.players.find(p => p.bot);
await click(A, "kick_" + bot.id); s = await waitFor(A, "请走电脑", s => s.players.length === 3); out.afterKick = s.players.length;
await click(A, "kick_" + s.you[2]); s = await waitFor(A, "撤掉本机第三人", s => s.players.length === 2); out.afterSelfKick = s.you.length;
await click(A, "start");
await waitFor(A, "开打", s => s.ph === "play", 15000);
// 两个本机玩家各按各的键
await A.keyboard.press("Space"); await sleep(250);
s = await st(A); out.seat1AfterSpace = s.players.map(p => p.s);
await A.keyboard.press("Enter"); await sleep(250);
s = await st(A); out.seat2AfterEnter = s.players.map(p => p.s);
// 用炸药：等第一个人钩到东西（状态 2）马上按 1。货太近的话还没按就拉上来了，那次不算，再试下一钩
let used = null;
for (let i = 0; i < 150 && !used; i++) {
  s = await st(A); const me = s.players[0];
  if (me.s === 2) {
    const d0 = me.tl.d, m0 = me.m; await A.keyboard.press("Digit1"); await sleep(450);
    const t = (await st(A)).players[0];
    if (t.tl.d < d0) used = { 炸药数: d0 + " → " + t.tl.d, 用完后钩子状态: t.s, 钱: m0 + " → " + t.m };
  } else { if (me.s === 0) await A.keyboard.press("Space"); await sleep(120); }
}
out.dynamite = used;
await sleep(500); await shot(A, "p2_local_2_play");
// 点画面也能放钩（第一个人）
await waitFor(A, "钩子收回", s => s.players[0].s === 0, 15000);
await A.mouse.click(640, 400, { label: "tap to drop hook" }); await sleep(250);
out.clickFire = (await st(A)).players[0].s;
console.log("RESULT " + JSON.stringify(out));
await A.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" }));
