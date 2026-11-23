// 第三期联调：合作联机，甲、乙两个页面加两个电脑，打到没过关为止。
// 看：巨型金块一个人拉不动、有人来帮才拉上来；钥匙和宝箱两个人分工；外加随机事件和颁奖。
const task = await taskSpace(SPACE);
const { A, B, code } = await room4(task, "co");
await click(A, "start");
let sawKey = 0;
const out = await playAll(A, B, "p3_co", {
  slice: 5000,
  watch: [
    { key: "巨型金块拉不动", name: "1_巨型金块拉不动", when: s => s.players.some(p => p.hv >= 0) && (s.evn.heavy || 0) >= 1 },
    { key: "有人来合拉", name: "2_合拉", when: s => (s.evn.heavy || 0) >= 1 && (s.evn.ast || 0) >= 1, wait: 150 },
    { key: "巨型金块拉上来", name: "3_巨型金块拉上来", when: s => (s.evn.heavy || 0) >= 1 && s.fk[0] && !s.fk[0].gx && s.te >= 1100, wait: 100 },
    { key: "拿到钥匙", name: "4_拿到钥匙", when: s => { if (s.ky > 0) sawKey = s.rd; return s.ky > 0; }, wait: 200 },
    { key: "宝箱打开", name: "5_宝箱打开", when: s => sawKey === s.rd && s.ky === 0 && s.fk[0] && !s.fk[0].chest, wait: 100 },
    { key: "事件", name: "6_事件", when: s => (s.evn.event || 0) >= 1, wait: 300 },
  ],
  onPlay: async (page, who, s, done) => {
    // 该看的都看到了（或者打过了第 2 关）以后，两个页面都不再挖，等全队过不了关，这一场自然结束
    const enough = s.rd >= 3 || ["巨型金块拉上来", "宝箱打开", "事件"].every(k => done["w_" + k]);
    await page.evaluate(v => { window.dmAutoGx = v; }, who === "甲" && !enough);   // 甲主动去钩巨型金块，其他人来帮
    await auto(page, !enough);
  },
});
log("结束", JSON.stringify(out.res));
console.log("RESULT " + JSON.stringify({ mode: "co", code, ...out }));
