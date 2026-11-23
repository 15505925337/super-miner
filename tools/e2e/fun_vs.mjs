// 第三期联调：同屏对战，甲、乙两个页面加两个电脑，打满 3 局。
// 服务端用 DM_EVENTS=rain,cave,dark 起，三局依次是金矿雨、塌方、黑灯。看：事件预告和发生、喊话、颁奖。
const task = await taskSpace(SPACE);
const { A, B, code } = await room4(task, "vs");
await shot(A, "p3_vs_0_房间");
await click(A, "help"); await sleep(500); await shot(A, "p3_vs_0_玩法说明"); await click(A, "help_close");
await click(A, "start");
const out = await playAll(A, B, "p3_vs", {
  watch: [
    { key: "金矿雨", name: "r1_1_金矿雨", when: s => s.ev[0] === "rain" && s.ev[1] === 2 && (s.evn.event || 0) >= 1, wait: 250 },
    { key: "塌方", name: "r2_1_塌方", when: s => s.ev[0] === "cave" && s.ev[1] === 2 && (s.evn.event || 0) >= 1, wait: 250 },
    { key: "黑灯", name: "r3_1_黑灯", when: s => s.ev[0] === "dark" && s.ev[1] === 1, wait: 1500 },
    { key: "喊话(按键)", name: "r1_2_喊话_甲按键", when: (s, who) => who === "甲" && s.emo >= 1, wait: 300 },
    { key: "喊话(点按钮)", name: "r1_3_喊话_乙点按钮", when: (s, who) => who === "乙" && s.emo >= 2, wait: 300 },
  ],
  onPlay: async (page, who, s, done) => {
    await auto(page, true);
    if (who === "甲" && !done.emoA) { done.emoA = 1; const n = s.emo; await page.keyboard.press("z"); await sleep(400); log("甲按 Z 喊话，喊话计数", n, "→", (await st(page)).emo); }
    if (who === "乙" && !done.emoB) { done.emoB = 1; const n = s.emo; await click(page, "emo_btn"); await shot(page, "p3_vs_r1_3_喊话_菜单"); await click(page, "emo_1"); await sleep(400); log("乙点按钮喊话，喊话计数", n, "→", (await st(page)).emo); }
    if (who === "甲" && s.rd === 2 && !done.spam) {            // 连按 5 次，服务端 2 秒只收一次
      done.spam = 1; const n = s.emo; for (let i = 0; i < 5; i++) { await page.keyboard.press("x"); await sleep(60); } await sleep(500);
      log("甲 0.3 秒内连按 5 次 X，喊话计数", n, "→", (await st(page)).emo, "（限频率：应该只多 1）");
    }
  },
});
log("结束", JSON.stringify(out.res));
console.log("RESULT " + JSON.stringify({ mode: "vs", code, ...out }));
