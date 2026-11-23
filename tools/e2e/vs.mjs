// 同屏对战：甲、乙两个页面加一个电脑，打满 5 局（一局下两层，正好经过四层）。中间在商店里按标价买、还价、用输入法跟老板说话。
const task = await taskSpace(SPACE);
const A = await open(task, "p1");
await front(A);
await A.evaluate(() => { try { localStorage.removeItem("dj_name"); } catch (e) {} });
await A.goto(BASE + "?test=1"); await A.waitForFunction(() => window.dmState && window.dmState.up, undefined, { timeout: 60000 });
await click(A, "name_edit"); await ime(A, "jia", "甲");
await click(A, "create_vs");
let s = await waitFor(A, "甲进房间", s => s.ph === "lobby");
const code = s.code; log("房间", code);
const B = await openFresh(task, "p2");
await front(B);
await click(B, "name_edit"); await ime(B, "yi", "乙");
await click(B, "code_edit"); await B.keyboard.type(code);
await click(B, "join");
await waitFor(B, "乙进房间", s => s.ph === "lobby" && s.players.length === 2);
await front(A);
await click(A, "add_bot");
s = await waitFor(A, "加了电脑", s => s.players.length === 3);
log("名单", s.players.map(p => p.name + (p.bot ? "(电脑)" : "")).join("、"));
await click(A, "rounds_5");
await waitFor(A, "改成 5 局", s => !s.rects.rounds_5 || true);
await sleep(300);
await shot(A, "p2_vs_1_lobby");
await click(A, "start");

const done = {}, pressLog = {};
let shopTalk = [];
for (let guard = 0; guard < 400; guard++) {
  for (const [page, who] of [[A, "甲"], [B, "乙"]]) {
    await front(page);
    s = await st(page);
    if (s.ph === "over") break;
    if (s.ph === "play") {
      const k0 = s.keys, f0 = s.fires;
      for (let i = 0; i < 5; i++) { await page.keyboard.press("Space"); await sleep(650); }
      const s2 = await st(page);
      pressLog[who + s.rd] = (pressLog[who + s.rd] || []).concat([[s2.keys - k0, s2.fires - f0]]);
      const key = who + "_play_" + s.rd;
      if (!done[key] && s.tl < 45) { done[key] = 1; await shot(page, "p2_vs_2_play_r" + s.rd + "_" + (who === "甲" ? "a" : "b")); log("第", s.rd, "局（地下", s.dp * 30, "米）", who, JSON.stringify(brief(await st(page)))); }
    } else if (s.ph === "rend") {
      const key = "rend_" + s.rd + who;
      if (!done[key]) { done[key] = 1; if (who === "甲") { await shot(page, "p2_vs_3_rend_r" + s.rd); log("第", s.rd, "局结束", JSON.stringify(s.res.rows.map(r => [r.id, r.e, r.m]))); } }
      await sleep(800);
    } else if (s.ph === "shop") {
      const key = "shop_" + s.rd + who;
      if (!done[key]) {
        done[key] = 1;
        const me = s.players.find(p => p.id === s.you[0]);
        if (who === "甲") {
          const before = me.m, tl = { ...me.tl };
          const stock = Object.keys(s.pr);                              // 这次上架了哪几件（每次不一样）
          const nm = k => ({ d: "炸药", s: "剪刀", f: "冰冻", h: "沙漏", drink: "大力饮料", clover: "幸运草", polish: "抛光布", book: "石头图鉴" }[k]);
          log("进商店，甲手里", before, "这次上架", stock.map(k => nm(k) + "¥" + s.pr[k]).join("、"), "掌柜说：", me.ks);
          shopTalk.push(`第 ${s.rd} 局后上架 ${stock.length} 件：${stock.map(nm).join("、")}`);
          const cheap = stock.filter(k => s.pr[k] <= before).sort((a, b) => s.pr[a] - s.pr[b])[0];
          if (cheap) {                                                   // 按标价买最便宜的一件：点货，再点"买下"
            await click(page, "item_" + cheap); await click(page, "buy"); await sleep(500);
            const t = (await st(page)).players.find(p => p.id === s.you[0]);
            shopTalk.push(`按标价买${nm(cheap)}：手里 ${before} → ${t.m}（标价 ${s.pr[cheap]}），掌柜说「${t.ks}」`);
          }
          const dear = stock.filter(k => k !== cheap).sort((a, b) => s.pr[b] - s.pr[a])[0];
          if (dear) {                                                    // 对最贵的一件还价：点货，填数，点"还价"
            const offer = Math.round(s.pr[dear] * 0.75 / 10) * 10;
            let t0 = (await st(page)).players.find(p => p.id === s.you[0]);
            await click(page, "item_" + dear); await click(page, "offer_edit");
            await page.keyboard.type(String(offer)); await sleep(200);
            await click(page, "offer_btn"); await sleep(700);
            const t = (await st(page)).players.find(p => p.id === s.you[0]);
            shopTalk.push(`对${nm(dear)}（标价 ${s.pr[dear]}）出价 ${offer}：掌柜说「${t.ks}」，要价变成 ${t.ak[dear]}，手里 ${t0.m} → ${t.m}，耐心 ${t0.km} → ${t.km}`);
          }
          let t1 = (await st(page)).players.find(p => p.id === s.you[0]);
          await click(page, "say_edit"); await ime(page, "zhangguizhenshuai", "掌柜真帅"); await click(page, "say_btn"); await sleep(700);   // 用输入法说句话
          const t2 = (await st(page)).players.find(p => p.id === s.you[0]);
          shopTalk.push(`说「掌柜真帅」：掌柜说「${t2.ks}」，耐心 ${t1.km} → ${t2.km}`);
          await shot(page, "p2_vs_4_shop_r" + s.rd);
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
await shot(A, "p2_vs_5_over_a");
await front(B); await sleep(600); await shot(B, "p2_vs_5_over_b");
log("结束", JSON.stringify({ round: s.res.round, final: s.res.final, rows: s.res.rows }));
for (const l of shopTalk) log("商店", l);
for (const k of Object.keys(pressLog)) log("按键", k, "每轮按 5 次，页面收到/发出：", JSON.stringify(pressLog[k]));
console.log("RESULT " + JSON.stringify({ mode: "vs", code, res: s.res, names: s.players.map(p => [p.id, p.name]), shop: shopTalk }));
