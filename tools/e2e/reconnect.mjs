// 掉线重连：对局中乙的页面离开游戏（连接断开），甲应该看到乙"掉线"、座位还在；乙回来后自动回到原座位，钱还在。
const task = await taskSpace(SPACE);
const A = await open(task, "p1"), B = await open(task, "p2");
await front(A); await freshHome(A, "jia", "甲");
await front(B); await freshHome(B, "yi", "乙");
await front(A); await click(A, "create_vs");
let s = await waitFor(A, "甲进房间", s => s.ph === "lobby");
const code = s.code;
await front(B); await click(B, "code_edit"); await B.keyboard.type(code); await click(B, "join");
await waitFor(B, "乙进房间", s => s.ph === "lobby" && s.players.length === 2);
await front(A); await click(A, "start");
await front(B); await waitFor(B, "开打", s => s.ph === "play", 15000);
await auto(B, true);
s = await waitFor(B, "乙先挖到点钱", s => s.players[1].m > 0, 40000);
await auto(B, false);
const mine = s.you[0];
await sleep(700);                                             // 等自动瞄准真的停下，再等钩子收回，这样离开时钩子上没有货
await waitFor(B, "钩子收回", s => s.players[1].s === 0, 15000);
await sleep(300);
const before = (await st(B)).players[1].m;
// 乙离开：换到另一个地址（127.0.0.1 和 localhost 对浏览器来说是两个站，身份令牌不会丢）
await B.goto("http://127.0.0.1:8060/left-the-game", { timeout: 30000 }).catch(() => {});
await sleep(1200);
const where = await B.url();
await front(A); await sleep(800);
let a = await st(A);
const seenOff = a.players.find(p => p.id === mine);
await shot(A, "p2_reconnect_1_offline");
// 乙回来：打开带房间号的地址
await B.goto(BASE + "?test=1&r=" + code, { timeout: 60000 });
await front(B);
const back = await waitFor(B, "乙重连", s => s.up && s.ph === "play" && s.you.length === 1, 30000);
const k0 = back.fires; await B.keyboard.press("Space"); await sleep(400);
const after = await st(B);
await front(A); await sleep(800);
a = await st(A);
const seenOn = a.players.find(p => p.id === mine);
await shot(A, "p2_reconnect_2_back");
const out = { 乙离开后所在地址: where, 甲看到乙在线: seenOff.on, 名单人数: a.players.length, 乙回来后的座位: back.you[0], 原来的座位: mine, 掉线前的钱: before, 回来后的钱: back.players.find(p => p.id === mine).m, 甲再看乙在线: seenOn.on, 回来后按键能放钩: after.fires - k0 };
console.log("RESULT " + JSON.stringify(out));
for (const p of [A, B]) await p.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" }));
