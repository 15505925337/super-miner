// 第三期联调：分屏对战，甲、乙两个页面加两个电脑。
// 甲一直用自动瞄准挖（连续钩中会往对手井里丢石头）；乙第 1 关不挖，被淘汰，第 2 关起当捣乱的：按放钩键往领先的人井里丢石头。
const task = await taskSpace(SPACE);
const { A, B, code } = await room4(task, "race");
await click(A, "start");
const out = await playAll(A, B, "p3_race", {
  watch: [
    { key: "连钩计数", name: "1_连钩计数", when: (s, who) => who === "甲" && me(s).cb >= 1 },
    { key: "连续钩中丢石头", name: "2_连续钩中丢石头", when: (s, who) => who === "甲" && (s.evn.atk || 0) - (s.evn.ghost || 0) >= 1, wait: 200 },
    { key: "淘汰后的提示", name: "3_乙淘汰后的提示", when: (s, who) => who === "乙" && me(s).out === 1 && me(s).gn > 0, wait: 300 },
    { key: "淘汰的人丢石头", name: "4_乙丢了石头", when: (s, who) => who === "乙" && me(s).out === 1 && me(s).gn >= 0 && me(s).gn < 5 && (s.evn.ghost || 0) >= 1, wait: 200 },
    { key: "甲看到被淘汰的人丢来石头", name: "5_甲看到乙丢来的石头", when: (s, who) => who === "甲" && (s.evn.ghost || 0) >= 1 && /已淘汰/.test(s.toast), wait: 100 },
    { key: "事件", name: "6_事件", when: s => (s.evn.event || 0) >= 1, wait: 300 },
  ],
  onPlay: async (page, who, s, done) => {
    if (who === "甲") { await auto(page, true); return; }
    await auto(page, false);
    const m = me(s);
    if (m.out === 1 && m.gn > 0) {                              // 乙淘汰了：等冷却好了按空格丢石头，然后马上切回甲看
      for (let i = 0; i < 20 && (await st(page)).players.find(p => p.id === s.you[0]).gc > 0; i++) await sleep(300);
      const before = me(await st(page)).gn;
      await page.keyboard.press("Space"); await sleep(500);
      const after = me(await st(page));
      log("乙（已淘汰）按空格：本关还能丢", before, "→", after.gn, "块；冷却", after.gc, "秒");
      if (!done.spamG) { done.spamG = 1; await page.keyboard.press("Space"); await sleep(300); log("冷却中再按一次：还能丢", me(await st(page)).gn, "块（应该不变）"); }
      await shot(page, "p3_race_4_乙丢了石头_乙的画面");
      await front(A); await sleep(250);
      const a = await st(A);
      if (/已淘汰/.test(a.toast) && !done.aSaw) { done.aSaw = 1; await shot(A, "p3_race_5_甲看到乙丢来的石头"); log("甲的提示条：", a.toast, "；甲井里的碎石", JSON.stringify(a.fk.map(f => f.rs || 0))); }
    }
  },
});
log("结束", JSON.stringify(out.res));
console.log("RESULT " + JSON.stringify({ mode: "race", code, ...out }));
