// 看图用：几种不是整数倍的窗口大小下，画面是否铺满、字是否清楚。
const task = await taskSpace(SPACE);
const A = await open(task, "p1");
await front(A);
for (const [w, h] of [[1194, 716], [1440, 900], [1000, 700], [1920, 1080]]) {
  await A.cdp("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 1, mobile: false });
  await A.goto(BASE + "?test=1&tier=1", { timeout: 60000 });
  await A.waitForFunction(() => window.dmState && window.dmState.up, undefined, { timeout: 60000 });
  await sleep(400);
  if ((await st(A)).ph !== "") { await A.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" })); await waitFor(A, "回首页", s => s.ph === ""); }
  await click(A, "create_co"); await waitFor(A, "进房间", s => s.ph === "lobby");
  await click(A, "add_local"); await click(A, "add_bot");
  if (w === 1194) await shot(A, "p2_size_" + w + "x" + h + "_lobby");
  await click(A, "start");
  await waitFor(A, "开打", s => s.ph === "play", 15000);
  for (let i = 0; i < 5; i++) { await A.keyboard.press("Space"); await sleep(300); await A.keyboard.press("Enter"); await sleep(500); }
  await shot(A, "p2_size_" + w + "x" + h);
  const s = await st(A); log(w + "×" + h, "倍数", s.k, JSON.stringify(brief(s)));
  await A.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" })); await sleep(400);
}
await A.cdp("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
