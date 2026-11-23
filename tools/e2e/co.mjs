// 合作联机：甲、乙共用一口井，钱算全队，打到没过关为止。
// 放钩用测试用的自动瞄准：第 1 关两人都挖，第 2 关只有甲挖，第 3 关起都不挖，等着过不了关。
const task = await taskSpace(SPACE);
const A = await open(task, "p1");
await front(A); await freshHome(A, "jia", "甲");
await click(A, "create_co");
let s = await waitFor(A, "甲进房间", s => s.ph === "lobby");
const code = s.code; log("房间", code, "玩法", s.mode);
const B = await open(task, "p2");
await front(B); await freshHome(B, "yi", "乙");
await click(B, "code_edit"); await B.keyboard.type(code);
await click(B, "join");
await waitFor(B, "乙进房间", s => s.ph === "lobby" && s.players.length === 2);
await front(A); await sleep(300);
await shot(A, "p2_co_1_lobby");
await click(A, "start");
const done = {}, notes = [];
for (let guard = 0; guard < 500; guard++) {
  for (const [page, who] of [[A, "甲"], [B, "乙"]]) {
    await front(page);
    s = await st(page);
    if (s.ph === "over") break;
    if (s.ph === "play") {
      await auto(page, who === "甲" ? s.rd <= 2 : s.rd <= 1);
      await sleep(3500);
      s = await st(page);
      if (!done["play" + s.rd + who] && s.tl < 40) { done["play" + s.rd + who] = 1; await shot(page, "p2_co_2_play_r" + s.rd + "_" + (who === "甲" ? "a" : "b")); log("第", s.rd, "关", who, "全队", s.te, "/ 目标", s.tg); }
    } else if (s.ph === "rend") {
      if (!done["rend" + s.rd] && who === "甲") { done["rend" + s.rd] = 1; await shot(page, "p2_co_4_rend_r" + s.rd); notes.push(`第 ${s.rd} 关结算：累计目标 ${s.res.co.target}，全队手里 ${s.res.co.have}，${s.res.co.pass ? "过关" : "没过"}；这一关各人挖了 ${s.res.rows.map(r => r.e).join("、")}`); log(notes[notes.length - 1]); }
      await sleep(800);
    } else if (s.ph === "shop") {
      if (!done["shop" + s.rd + who]) {
        done["shop" + s.rd + who] = 1;
        if (who === "甲") {                                       // 合作模式花的是全队的钱：甲买一瓶大力饮料，乙那边看到的钱也少了
          const before = s.players[0].m, stock = Object.keys(s.pr);
          const pick = stock.filter(k => s.pr[k] <= before).sort((a, b) => s.pr[a] - s.pr[b])[0];
          if (pick) {
            await click(page, "item_" + pick); await click(page, "buy"); await sleep(500);
            const t = await st(page);
            notes.push(`第 ${s.rd} 关后的商店（上架 ${stock.length} 件）：甲买了一件标价 ${s.pr[pick]} 的，全队的钱 ${before} → ${t.players[0].m}，乙名下显示的也是 ${t.players[1].m}`); log(notes[notes.length - 1]);
          }
          await shot(page, "p2_co_5_shop_r" + s.rd);
        }
        await click(page, "ready");
      }
      await sleep(500);
    } else await sleep(500);
  }
  s = await st(A);
  if (s.ph === "over") break;
}
await front(A); s = await waitFor(A, "整场结束", s => s.ph === "over", 20000);
await shot(A, "p2_co_6_over");
await auto(A, false); await auto(B, false);
log("结束", JSON.stringify(s.res));
console.log("RESULT " + JSON.stringify({ mode: "co", code, res: s.res, notes }));
