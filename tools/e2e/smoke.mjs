// 冒烟：甲开房（用输入法打名字），乙凭房间号进来，开打几秒，各截一张图。
const task = await taskSpace(SPACE);
const A = await open(task, "p1");
await front(A);
await click(A, "name_edit"); await ime(A, "jia", "甲");
await click(A, "create_vs");
let s = await waitFor(A, "甲进房间", s => s.ph === "lobby");
log("甲开了房间", s.code, JSON.stringify(s.players.map(p => p.name)));
const B = await openFresh(task, "p2");
await front(B);
await click(B, "name_edit"); await ime(B, "yi", "乙");
await click(B, "code_edit"); await B.keyboard.type(s.code);
await click(B, "join");
s = await waitFor(B, "乙进房间", s => s.ph === "lobby" && s.players.length === 2);
log("乙进来了", JSON.stringify(s.players.map(p => p.name)), "乙是房主吗", s.host);
await shot(B, "t_lobby_b");
await front(A);
await click(A, "add_bot");
await click(A, "start");
await waitFor(A, "开打", s => s.ph === "play", 15000);
for (let i = 0; i < 6; i++) { await A.keyboard.press("Space"); await sleep(900); }
s = await st(A); log("甲这边", JSON.stringify(brief(s)), "井里东西", s.items);
await shot(A, "t_play_a");
await front(B);
for (let i = 0; i < 4; i++) { await B.keyboard.press("Space"); await sleep(900); }
s = await st(B); log("乙这边", JSON.stringify(brief(s)));
await shot(B, "t_play_b");
console.log(JSON.stringify({ taskSpaceId: task.spaceId, pages: (await task.pages()).map(p => p.label) }));
