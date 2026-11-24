// 联调脚本的公共部分。用 ego 浏览器开两个页面，像真人一样点按钮、按键、用输入法打字。
// 这些函数会被拼到各个联调脚本前面，再交给 `ego-browser nodejs` 执行（见 tools/e2e/run.sh）。
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function open(task, label, query) {
  const have = (await task.pages()).map(p => p.label);
  const page = have.includes(label) ? task.page(label) : await task.newPage();
  await page.cdp("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await page.goto(BASE + "?test=1" + (query || ""), { timeout: 60000 });
  await page.waitForFunction(() => window.dmState && window.dmState.up, undefined, { timeout: 60000 });
  return page;
}
// 第二个玩家：同一个浏览器里存着上一个人的名字，先清掉，当成一台新设备
async function openFresh(task, label) {
  const page = await open(task, label);
  await page.evaluate(() => { try { localStorage.removeItem("dj_name"); sessionStorage.removeItem("dj_token"); } catch (e) {} });
  return open(task, label);
}
// 同一个窗口里只有最前面的标签页在跑画面，所以操作谁就先把谁切到前面
async function front(page) { await page.cdp("Page.bringToFront", {}); await sleep(350); }
const st = page => page.evaluate(() => window.dmState);
async function click(page, key) {
  const s = await st(page), r = s.rects[key];
  if (!r) throw new Error("画面上没有这个按钮：" + key + "（当前阶段 " + s.ph + "，有 " + Object.keys(s.rects).join(",") + "）");
  await page.mouse.click(r[0], r[1], { label: "click " + key });
  await sleep(300);
}
// 模拟拼音输入法：先组字（出现拼音），再上屏
async function ime(page, pinyin, text) {
  for (let i = 1; i <= pinyin.length; i++) { await page.cdp("Input.imeSetComposition", { text: pinyin.slice(0, i), selectionStart: i, selectionEnd: i }); await sleep(40); }
  await page.cdp("Input.insertText", { text }); await sleep(250);
}
async function waitFor(page, what, ok, ms = 30000) {
  const t0 = Date.now();
  for (;;) {
    const s = await st(page);
    if (ok(s)) return s;
    if (Date.now() - t0 > ms) throw new Error("等不到：" + what + "（当前阶段 " + s.ph + "）");
    await sleep(200);
  }
}
// 回到首页并把名字改掉：全选原来的名字，再用输入法打新的
async function freshHome(page, pinyin, name) {
  if ((await st(page)).ph !== "") { await page.evaluate(() => (window.dmQ = window.dmQ || []).push({ t: "leave" })); await waitFor(page, "回首页", s => s.ph === ""); }
  await click(page, "name_edit");
  for (let i = 0; i < 12; i++) await page.keyboard.press("Backspace");
  for (let i = 0; i < 12; i++) await page.keyboard.press("Delete");
  await ime(page, pinyin, name);
}
// 打开或关掉测试用的自动瞄准（代替脚本乱按键）
const auto = (page, on) => page.evaluate(v => { window.dmAuto = v; }, on);
const shot = (page, name) => page.screenshot({ path: SHOTS + name + ".png" });
const brief = s => ({ ph: s.ph, rd: s.rd, tl: Math.round(s.tl), players: s.players.map(p => `${p.name}:¥${p.m}${p.out ? "(淘汰)" : ""}`).join(" ") });

/* ───── 第三期（联机乐趣）的联调：两个页面加两个电脑，一共四个客户端 ───── */
async function room4(task, mode) {
  const A = await open(task, "p1"); await front(A); await freshHome(A, "jia", "甲");
  await click(A, "create_" + mode);
  let s = await waitFor(A, "甲进房间", s => s.ph === "lobby");
  const code = s.code;
  const B = await open(task, "p2"); await front(B); await freshHome(B, "yi", "乙");
  await click(B, "code_edit"); await B.keyboard.type(code); await click(B, "join");
  await waitFor(B, "乙进房间", s => s.ph === "lobby" && s.players.length === 2);
  await front(A); await sleep(300);
  await click(A, "add_bot"); await click(A, "add_bot");
  s = await waitFor(A, "四个人到齐", s => s.players.length === 4);
  log("房间", code, "玩法", s.mode, "四个人：", s.players.map(p => p.name + (p.bot ? "(电脑)" : "")).join("、"));
  return { A, B, code };
}
// 打完一整场。两个页面轮流切到前面（只有前面的页面在跑），每次盯几秒：
//   watch：[{ key, when(s, who), name, wait }]，条件第一次成立时截一张图（每个 key 只截一次）
//   onPlay(page, who, s, done)：每次轮到这个页面、正在挖的时候做的事（开关自动瞄准、按键）
async function playAll(A, B, tag, { watch = [], onPlay, slice = 3500 } = {}) {
  const done = {}, hits = {}, notes = [];
  let s;
  for (let guard = 0; guard < 600; guard++) {
    for (const [page, who] of [[A, "甲"], [B, "乙"]]) {
      await front(page);
      s = await st(page);
      if (s.ph === "over") break;
      if (s.ph === "count") {
        if (s.ev && s.ev.length && !done["count" + s.rd]) { done["count" + s.rd] = 1; await sleep(500); await shot(page, `${tag}_r${s.rd}_0_预告_${s.ev[0]}`); notes.push(`第 ${s.rd} 关倒计时预告事件 ${s.ev[0]}`); }
        await sleep(400);
      } else if (s.ph === "play") {
        if (onPlay) await onPlay(page, who, s, done);
        const t0 = Date.now();
        while (Date.now() - t0 < slice) {
          s = await st(page);
          if (s.ph !== "play") break;
          for (const w of watch) {
            if (done["w_" + w.key] || !w.when(s, who)) continue;
            done["w_" + w.key] = 1;
            if (w.wait) await sleep(w.wait);
            await shot(page, `${tag}_${w.name}`);
            const t = await st(page);
            hits[w.key] = { round: t.rd, who, toast: t.toast, evn: t.evn };
            log("✔", w.key, "第", t.rd, "关", who, "看到；提示条：", t.toast, "；事件计数", JSON.stringify(t.evn));
          }
          await sleep(200);
        }
      } else if (s.ph === "rend") {
        if (!done["rend" + s.rd] && who === "甲") { done["rend" + s.rd] = 1; await shot(page, `${tag}_r${s.rd}_9_结算`); notes.push(`第 ${s.rd} 关结算 ` + JSON.stringify(brief(s))); log(notes[notes.length - 1]); }
        await sleep(600);
      } else if (s.ph === "shop") {
        if (!done["shop" + s.rd + who]) { done["shop" + s.rd + who] = 1; notes.push(`第 ${s.rd} 关后的商店上架 ${Object.keys(s.pr).join("、")}`); if (s.rects.ready) await click(page, "ready"); }
        await sleep(400);
      } else await sleep(400);
    }
    s = await st(A);
    if (s.ph === "over") break;
  }
  await front(A); s = await waitFor(A, "整场结束", s => s.ph === "over", 30000);
  await sleep(600); await shot(A, `${tag}_z_颁奖`);
  await auto(A, false); await auto(B, false);
  const sb = await (async () => { await front(B); await sleep(500); return st(B); })();
  const missing = watch.filter(w => !done["w_" + w.key]).map(w => w.key);
  return { res: s.res, hits, notes, evnA: s.evn, evnB: sb.evn, sfxA: s.sfx, sfxB: sb.sfx, missing };
}
const me = (s) => s.players.find(p => p.id === s.you[0]);
