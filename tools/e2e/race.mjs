// 分屏对战：甲、乙每人一口一模一样的井，没到累计目标的淘汰，打到只剩一个人。
// 放钩用测试用的自动瞄准：甲一直挖；乙前两关挖，第三关起不挖，等着被淘汰。
const task = await taskSpace(SPACE);
const A = await open(task, "p1"), B = await open(task, "p2");
await front(A); await freshHome(A, "jia", "甲");
await front(B); await freshHome(B, "yi", "乙");
await front(A);
await click(A, "create_race");
let s = await waitFor(A, "甲进房间", s => s.ph === "lobby");
const code = s.code; log("房间", code, "玩法", s.mode);
await front(B);
await click(B, "code_edit"); await B.keyboard.type(code);
await click(B, "join");
await waitFor(B, "乙进房间", s => s.ph === "lobby" && s.players.length === 2);
await front(A); await sleep(300);
await click(A, "start");
const done = {}, notes = [];
for (let guard = 0; guard < 500; guard++) {
  for (const [page, who] of [[A, "甲"], [B, "乙"]]) {
    await front(page);
    s = await st(page);
    if (s.ph === "over") break;
    if (s.ph === "play") {
      await auto(page, who === "甲" ? true : s.rd <= 2);
      await sleep(3500);
      s = await st(page);
      if (!done["play" + s.rd + who] && s.tl < 40) { done["play" + s.rd + who] = 1; await shot(page, "p2_race_1_play_r" + s.rd + "_" + (who === "甲" ? "a" : "b")); log("第", s.rd, "关", who, JSON.stringify(brief(s)), "目标", s.tg, "分屏", s.split); }
    } else if (s.ph === "rend") {
      if (!done["rend" + s.rd] && who === "甲") { done["rend" + s.rd] = 1; await shot(page, "p2_race_2_rend_r" + s.rd); notes.push(`第 ${s.rd} 关（累计目标 ${s.res.target}）：` + s.res.rows.map(r => `${r.id === 1 ? "甲" : "乙"}手里 ${r.m}，${r.now ? "这一关淘汰" : r.out ? "已淘汰" : "过关"}`).join("；")); log(notes[notes.length - 1]); }
      await sleep(800);
    } else if (s.ph === "shop") {
      if (!done["shop" + s.rd + who]) { done["shop" + s.rd + who] = 1; if (s.rects.ready) await click(page, "ready"); }
      await sleep(500);
    } else await sleep(500);
  }
  s = await st(A);
  if (s.ph === "over") break;
}
await front(A); s = await waitFor(A, "整场结束", s => s.ph === "over", 20000);
await shot(A, "p2_race_3_over");
await auto(A, false); await auto(B, false);
log("结束", JSON.stringify(s.res));
console.log("RESULT " + JSON.stringify({ mode: "race", code, res: s.res, notes }));
