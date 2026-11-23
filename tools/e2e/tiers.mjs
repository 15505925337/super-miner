// 看图用：四层各开一局（自己加两个电脑），打几秒截一张。层是用网址参数强制的，只影响显示。
const task = await taskSpace(SPACE);
const A = await open(task, "p1");
await front(A);
await shot(A, "p2_home");
for (const tier of [0, 1, 2, 3]) {
  await A.goto(BASE + "?test=1&tier=" + tier, { timeout: 60000 });
  await A.waitForFunction(() => window.dmState && window.dmState.up, undefined, { timeout: 60000 });
  await sleep(400);
  if ((await st(A)).ph !== "") { await A.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" })); await waitFor(A, "回首页", s => s.ph === ""); }
  await click(A, "create_vs"); await waitFor(A, "进房间", s => s.ph === "lobby");
  await click(A, "add_bot"); await click(A, "add_bot");
  if (tier === 0) await shot(A, "p2_lobby");
  await click(A, "start");
  await waitFor(A, "开打", s => s.ph === "play", 15000);
  for (let i = 0; i < 9; i++) { await A.keyboard.press("Space"); await sleep(800); }
  await shot(A, "p2_tier" + tier);
  const s = await st(A); log("第", tier, "层", JSON.stringify(brief(s)), "按键", s.keys, "发出", s.fires, "倍数", s.k);
  await A.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" })); await sleep(500);
}
console.log(JSON.stringify({ taskSpaceId: task.spaceId }));
