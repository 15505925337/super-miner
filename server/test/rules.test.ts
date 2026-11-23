// 对局规则的测试：碰撞、拉货、计分、合拉、炸药桶、宝袋、道具、过关判定、淘汰。
import test from 'node:test';
import assert from 'node:assert/strict';
import { W, H, Y0, MINL, AMP, HOOK_R, BOOM_R, HAUL_V, HELP, STRONG, ROUND_T, REND_T, SHOP_T, SW, EXT, HAUL, RET, AST, TYPES, TI, goalOf, tierOf, depthOf } from '../src/core.ts';
import { newRoom, newPlayer, startGame, nextRound, genItems, itemCounts, YMIN, endRound, fire, useTool, openBag, tickRoom, snapshot } from '../src/game.ts';
import { rng, run, playing, put, aim, DT } from './helpers.ts';

test('过关目标：按公式累计，前面多赚的能顶后面的关', () => {
  assert.equal(goalOf(1, 1), 600);
  assert.equal(goalOf(2, 1), 1530);          // 600 × (2 + 0.55)
  assert.equal(goalOf(3, 1), 2790);          // 600 × (3 + 0.55×3)
  assert.equal(goalOf(1, 4), 1650);          // (250 + 350×4)
  assert.equal(goalOf(2, 2), 2420);          // 950 × 2.55 = 2422.5 → 取整到 10
  for (let n = 1; n <= 4; n++) for (let l = 1; l < 12; l++) assert.ok(goalOf(l + 1, n) > goalOf(l, n), '目标要一关比一关高');
});

test('深度和层：每两关换一层，同屏对战一局下两层', () => {
  assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8, 20].map(tierOf), [0, 0, 1, 1, 2, 2, 3, 3, 3]);
  const room = newRoom('1', rng(1));
  room.mode = 'vs'; room.round = 2; assert.equal(depthOf(room), 3);
  room.mode = 'co'; assert.equal(depthOf(room), 2);
  room.mode = 'race'; room.round = 7; assert.equal(depthOf(room), 7);
});

test('出矿：数量照公式、不重叠、不出界、值钱的埋得深、各层才有的东西不提前出', () => {
  let checked = 0;
  for (const mode of ['co', 'vs', 'race'] as const) for (let n = 1; n <= 4; n++) for (let round = 1; round <= 8; round++) for (let seed = 1; seed <= 3; seed++) {
    const room = newRoom('1', rng(seed * 100 + round)); room.mode = mode; room.round = round;
    const L = depthOf(room), tier = tierOf(L), items = genItems(room, n), want = itemCounts(L, n, rng(seed * 100 + round));
    const have: Record<string, number> = {};
    for (const it of items) have[TYPES[it.t].k] = (have[TYPES[it.t].k] || 0) + 1;
    for (const k of Object.keys(have)) assert.ok(have[k] <= want[k] + 1, `${k} 出多了`);   // gs、gem 的数量带一点随机，最多差 1
    if (tier < 2) assert.ok(!have.rub, '红宝石在晶洞层之前不该出现');
    if (tier < 3) assert.ok(!have.gx, '巨型金块在熔岩层之前不该出现');
    for (const it of items) {
      const k = TYPES[it.t].k;
      assert.ok(it.x >= it.r + 30 && it.x <= W - it.r - 30 && it.y <= H - it.r - 22, '出界了');
      assert.ok(it.y >= (YMIN[k] || 265), `${k} 埋得太浅`);
      assert.ok(!(it.y + it.r > H - 96 && Math.abs(it.x - W / 2) < 115 + it.r), '井底正中间不该放东西');
      for (const o of items) if (o !== it) assert.ok(Math.hypot(o.x - it.x, o.y - it.y) > o.r + it.r + 14, '两个东西叠在一起了');
    }
    assert.ok(items.length >= 8, '东西太少');
    checked++;
  }
  assert.equal(checked, 3 * 4 * 8 * 3);
});

test('碰撞：钩子正下方的东西能钩到，变成拉货', () => {
  const { room, ps: [p] } = playing('vs', 1);
  const it = put(room, 0, 'gs', p.x, 400);
  fire(room, p);
  assert.equal(p.st, EXT);
  run(room, 2, () => p.st !== EXT);
  assert.equal(p.st, HAUL); assert.equal(p.item, it.id); assert.equal(it.by, p.id);
});

test('碰撞：擦边算钩到，差一点算钩空', () => {
  const lim = TYPES[TI.gs].r + HOOK_R;                        // 15 + 11 = 26
  const a = playing('vs', 1); put(a.room, 0, 'gs', a.ps[0].x + lim - 2, 400);
  fire(a.room, a.ps[0]); run(a.room, 2, () => a.ps[0].st !== EXT);
  assert.equal(a.ps[0].st, HAUL, '离钩尖 24 应该钩到');
  const b = playing('vs', 1); put(b.room, 0, 'gs', b.ps[0].x + lim + 3, 400);
  fire(b.room, b.ps[0]); run(b.room, 2, () => b.ps[0].st !== EXT);
  assert.equal(b.ps[0].st, RET, '离钩尖 29 应该钩空，到底后空收');
  run(b.room, 2, () => b.ps[0].st === SW);
  assert.equal(b.ps[0].st, SW); assert.equal(b.ps[0].len, MINL); assert.equal(b.ps[0].money, 0);
});

test('拉货：越重越慢，拉到顶才记钱', () => {
  const time = (k: string, drink = false) => {
    const { room, ps: [p] } = playing('vs', 1);
    if (drink) p.buff.drink = 1;
    const it = put(room, 0, k, p.x, 400);
    fire(room, p); run(room, 2, () => p.st === HAUL);
    const len0 = p.len; let t = 0;
    assert.equal(p.money, 0, '还在半路不该有钱');
    while (p.st === HAUL && t < 10) { tickRoom(room, DT); t += DT; }
    assert.equal(p.money, it.v);
    return { t, expect: (len0 - MINL) / (HAUL_V / it.w * (drink ? STRONG : 1)) };
  };
  const gs = time('gs'), rl = time('rl'), fast = time('rl', true);
  for (const r of [gs, rl, fast]) assert.ok(Math.abs(r.t - r.expect) <= 2 * DT + 1e-9, `拉货时间 ${r.t.toFixed(3)} 应约为 ${r.expect.toFixed(3)}`);
  assert.ok(rl.t > gs.t * 3, '巨石应该比小金块慢得多');
  assert.ok(Math.abs(fast.t - rl.t / STRONG) <= 3 * DT, '大力饮料应该快 1.6 倍');
});

test('计分：对战记在个人，合作记在全队', () => {
  const vs = playing('vs', 2); put(vs.room, 0, 'gm', vs.ps[0].x, 400);
  fire(vs.room, vs.ps[0]); run(vs.room, 5, () => vs.ps[0].money > 0);
  assert.equal(vs.ps[0].money, 150); assert.equal(vs.ps[1].money, 0); assert.equal(vs.ps[0].earned, 150); assert.equal(vs.ps[0].total, 150);
  const co = playing('co', 2); put(co.room, 0, 'gm', co.ps[0].x, 400);
  fire(co.room, co.ps[0]); run(co.room, 5, () => co.room.money > 0);
  assert.equal(co.room.money, 150); assert.equal(co.ps[0].money, 0); assert.equal(co.ps[0].total, 150);
  assert.equal((snapshot(co.room).P as any[])[1].m, 150, '合作模式每个人看到的钱都是全队的');
});

function assistSetup(mode: 'vs' | 'co') {
  const { room, ps } = playing(mode, 2);
  const [p1, p2] = ps;
  const it = put(room, 0, 'gl', 640, 500, { w: 1e9 });      // 先让它重得拉不动，等第二个人钩上
  aim(p1, it.x, it.y, Y0); fire(room, p1); run(room, 3, () => p1.st === HAUL);
  aim(p2, it.x, it.y, Y0); fire(room, p2); run(room, 3, () => p2.st !== EXT);
  return { room, p1, p2, it };
}
test('合拉：钩到别人正在拉的货变成帮拉，每多一人速度加 0.9 倍', () => {
  const { room, p1, p2, it } = assistSetup('vs');
  assert.equal(p1.st, HAUL); assert.equal(p2.st, AST); assert.equal(p2.item, it.id);
  it.w = 5.2;
  const before = p1.len; tickRoom(room, DT);
  assert.ok(Math.abs((before - p1.len) - HAUL_V / 5.2 * (1 + HELP) * DT) < 1e-6);
});
test('合拉分成：对战主拉 70%、帮拉 30%', () => {
  const { room, p1, p2, it } = assistSetup('vs'); it.w = 5.2;
  const evs = run(room, 10, () => p1.st === SW);
  assert.equal(p1.money, 350); assert.equal(p2.money, 150);
  assert.equal(p2.st, RET, '货到顶后帮拉的人空收');
  assert.deepEqual(evs.filter(e => e.e === 'get').map(e => [e.p, e.v, e.k]), [[p2.id, 150, 'gl'], [p1.id, 350, 'gl']]);
});
test('合拉分成：合作多拿 10%', () => {
  const { room, p1, it } = assistSetup('co'); it.w = 5.2;
  run(room, 10, () => p1.st === SW);
  assert.equal(room.money, 550);
});

test('炸药桶：钩到就炸，范围内的东西没了，范围外的还在，旁边的炸药桶连环炸', () => {
  const { room, ps: [p] } = playing('vs', 1);
  const tnt1 = put(room, 0, 'tnt', p.x, 400);
  const near = put(room, 0, 'gs', p.x + 60, 400);            // 离第一桶 60，在范围内
  const far = put(room, 0, 'gl', p.x, 560);                  // 离第一桶 160 > 125 + 21，离第二桶 152.6 > 146
  const tnt2 = put(room, 0, 'tnt', p.x - 80, 430);           // 离第一桶 85，会被引爆
  const chained = put(room, 0, 'gm', p.x - 200, 430);        // 离第一桶 202（炸不到），离第二桶 120（炸得到）
  fire(room, p);
  const evs = run(room, 2, () => p.st === RET);
  const ids = () => room.fields[0].items.map(o => o.id);
  assert.equal(p.st, RET, '钩到炸药桶后空收');
  assert.ok(!ids().includes(tnt1.id) && !ids().includes(near.id), '第一桶和范围内的小金块应该没了');
  assert.ok(ids().includes(far.id) && ids().includes(chained.id) && ids().includes(tnt2.id), '范围外的和第二桶这一刻还在');
  assert.equal(evs.filter(e => e.e === 'boom').length, 1);
  assert.equal((evs.find(e => e.e === 'boom') as any).r, BOOM_R);
  const evs2 = run(room, 0.3);
  assert.ok(!ids().includes(tnt2.id) && !ids().includes(chained.id), '0.14 秒后第二桶炸，带走它旁边的金块');
  assert.ok(ids().includes(far.id), '两桶都够不着的大金块还在');
  assert.equal(evs2.filter(e => e.e === 'boom').length, 1);
  assert.equal(p.money, 0, '炸掉的东西不给钱');
});

test('炸药桶：别人正在拉的货也会被炸没，对方空收', () => {
  const { room, ps: [p1, p2] } = playing('vs', 2);
  const gold = put(room, 0, 'gl', p1.x, 400, { w: 1e9 });
  fire(room, p1); run(room, 2, () => p1.st === HAUL);
  const tnt = put(room, 0, 'tnt', gold.x + 70, gold.y + 20);   // 炸药桶放在金块旁边，离它 73
  aim(p2, tnt.x, tnt.y, Y0); fire(room, p2); run(room, 2, () => p2.st === RET);
  assert.ok(!room.fields[0].items.includes(gold), '金块被炸没了');
  tickRoom(room, DT);
  assert.equal(p1.st, RET); assert.equal(p1.item, 0); assert.equal(p1.money, 0);
});

test('爆炸事件：撞桶只标记出钩的玩家，连环炸没有触发者', () => {
  const { room, ps: [, p] } = playing('vs', 2);
  put(room, 0, 'tnt', p.x, 400);
  put(room, 0, 'tnt', p.x - 80, 430);
  fire(room, p);
  const hit = run(room, 2, () => p.st === RET).filter(e => e.e === 'boom');
  assert.deepEqual(hit, [{ e: 'boom', f: 0, x: p.x, y: 400, r: BOOM_R, p: p.id, src: 'tnt' }]);
  const chain = run(room, 0.3).filter(e => e.e === 'boom');
  assert.deepEqual(chain, [{ e: 'boom', f: 0, x: p.x - 80, y: 430, r: BOOM_R }]);
});

test('宝袋：开出什么由生成时定好的两个数决定', () => {
  const { room, ps: [p] } = playing('vs', 1);
  const bag = (roll: number, roll2: number) => openBag(room, p, { id: 0, t: TI.bag, x: 0, y: 0, r: 19, v: 0, w: 2, by: 0, vx: 0, x0: 0, x1: 0, roll, roll2 });
  assert.deepEqual(bag(0.3, 0.5), { v: 260 });               // 60 + 0.5×390 = 255 → 取整到 10
  assert.deepEqual(bag(0.0, 0.0), { v: 60 }); assert.deepEqual(bag(0.54, 0.999), { v: 450 });
  const s0 = p.tools.s;
  assert.deepEqual(bag(0.6, 0.5), { v: 0, s: '剪刀 ×1' }); assert.equal(p.tools.s, s0 + 1);   // 对战的道具顺序是 炸药、剪刀、冰冻
  p.tools.d = 5; bag(0.6, 0.0); assert.equal(p.tools.d, 5, '道具最多 5 个');
  assert.equal(p.strongR, false); assert.deepEqual(bag(0.8, 0.5), { v: 0, s: '大力！' }); assert.equal(p.strongR, true);
  assert.deepEqual(bag(0.95, 0.5), { v: 5, s: '空袋子' });
  p.buff.clover = 1;                                          // 幸运草：必出好东西
  assert.deepEqual(bag(0.5, 0.5), { v: 580 }); assert.equal(bag(0.99, 0.5).v, 100);
  const co = playing('co', 1);
  assert.deepEqual(openBag(co.room, co.ps[0], { id: 0, t: TI.bag, x: 0, y: 0, r: 19, v: 0, w: 2, by: 0, vx: 0, x0: 0, x1: 0, roll: 0.6, roll2: 0.9 }), { v: 0, s: '沙漏 ×1' });
});

test('宝袋：拉上来按开出的钱记账', () => {
  const { room, ps: [p] } = playing('vs', 1);
  put(room, 0, 'bag', p.x, 400, { roll: 0.3, roll2: 0.5, w: 1.5 });
  fire(room, p); const evs = run(room, 5, () => p.money > 0);
  assert.equal(p.money, 260); assert.equal(evs.find(e => e.e === 'get').s, '宝袋');
});

test('增益：抛光布让晶石类 ×1.5，石头图鉴让石头 ×5', () => {
  const a = playing('vs', 1); a.ps[0].buff.polish = 1; put(a.room, 0, 'gem', a.ps[0].x, 450);
  fire(a.room, a.ps[0]); run(a.room, 5, () => a.ps[0].money > 0); assert.equal(a.ps[0].money, 900);
  const b = playing('vs', 1); b.ps[0].buff.book = 1; put(b.room, 0, 'rs', b.ps[0].x, 400);
  fire(b.room, b.ps[0]); run(b.room, 8, () => b.ps[0].money > 0); assert.equal(b.ps[0].money, 55);
  const c = playing('vs', 1); c.ps[0].buff.polish = 1; put(c.room, 0, 'gs', c.ps[0].x, 400);
  fire(c.room, c.ps[0]); run(c.room, 5, () => c.ps[0].money > 0); assert.equal(c.ps[0].money, 50, '抛光布不管金块');
});

test('道具·炸药：只有正在拉货时能用，炸掉货马上收钩，不给钱', () => {
  const { room, ps: [p] } = playing('vs', 1);
  assert.equal(p.tools.d, 1, '开局送 1 个炸药');
  useTool(room, p, 'd'); assert.equal(p.tools.d, 1, '没在拉货，不消耗');
  const it = put(room, 0, 'rl', p.x, 400);
  fire(room, p); run(room, 2, () => p.st === HAUL);
  useTool(room, p, 'd');
  assert.equal(p.tools.d, 0); assert.equal(p.st, RET); assert.ok(!room.fields[0].items.includes(it));
  run(room, 3, () => p.st === SW); assert.equal(p.money, 0);
});

test('爆炸事件：使用炸药标记道具使用者和所属的井', () => {
  const { room, ps: [, p] } = playing('race', 2);
  put(room, 1, 'rl', p.x, 400);
  fire(room, p);
  run(room, 2, () => p.st === HAUL);
  useTool(room, p, 'd');
  assert.deepEqual(room.ev.filter(e => e.e === 'boom').map(e => [e.f, e.p, e.src]), [[1, p.id, 'd']]);
});

test('道具·剪刀：剪正在拉最值钱货的那个对手，货留在原地；没人拉货不消耗', () => {
  const { room, ps: [p1, p2, p3] } = playing('vs', 3);
  p3.tools.s = 2;
  useTool(room, p3, 's'); assert.equal(p3.tools.s, 2, '没人在拉货，不消耗');
  const cheap = put(room, 0, 'gs', p1.x, 400, { w: 1e9 }), rich = put(room, 0, 'gl', p2.x, 500, { w: 1e9 });
  fire(room, p1); fire(room, p2); run(room, 3, () => p1.st === HAUL && p2.st === HAUL);
  const evs: any[] = []; useTool(room, p3, 's'); evs.push(...room.ev);
  assert.equal(p3.tools.s, 1);
  assert.equal(p2.st, RET, '拉大金块的被剪'); assert.equal(p1.st, HAUL, '拉小金块的没事');
  assert.equal(rich.by, 0); assert.ok(room.fields[0].items.includes(rich), '货掉在原地');
  assert.equal(cheap.by, p1.id);
  assert.ok(evs.some(e => e.e === 'cut'));
});

test('道具·冰冻：所有对手冻 3 秒，冻住时不能放钩、钩子不动', () => {
  const { room, ps: [p1, p2] } = playing('vs', 2);
  put(room, 0, 'gs', 100, 650);                              // 井里留一个东西，不然这一关会因为"挖空了"立刻结束
  p1.tools.f = 1; useTool(room, p1, 'f');
  assert.equal(p1.tools.f, 0); assert.equal(p1.frozen, 0); assert.ok(p2.frozen > room.now);
  const a0 = p2.ang; fire(room, p2); assert.equal(p2.st, SW, '冻住不能放钩');
  run(room, 2.9); assert.equal(p2.ang, a0, '冻住时钩子不摆');
  assert.equal((snapshot(room).P as any[])[1].fz, 1);
  run(room, 0.2); fire(room, p2); assert.equal(p2.st, EXT, '3 秒后解冻');
});

test('道具·沙漏：只有合作能用，本关 +8 秒；各玩法只能用自己的道具', () => {
  const co = playing('co', 1); co.ps[0].tools.h = 1; co.ps[0].tools.s = 1; co.ps[0].tools.f = 1;
  const tl = co.room.tl; useTool(co.room, co.ps[0], 'h');
  assert.equal(co.room.tl, tl + 8); assert.equal(co.ps[0].tools.h, 0);
  useTool(co.room, co.ps[0], 's'); useTool(co.room, co.ps[0], 'f');
  assert.equal(co.ps[0].tools.s, 1); assert.equal(co.ps[0].tools.f, 1);
  const vs = playing('vs', 2); vs.ps[0].tools.h = 1; const tl2 = vs.room.tl;
  useTool(vs.room, vs.ps[0], 'h'); assert.equal(vs.room.tl, tl2); assert.equal(vs.ps[0].tools.h, 1);
});

test('放钩的角度补偿：以玩家看到的角度为准，差太多不认', () => {
  const set = () => { const g = playing('vs', 1); g.ps[0].ang = 0.5; g.ps[0].phase = Math.asin(0.5 / AMP); return g; };
  let g = set(); fire(g.room, g.ps[0], 0.7); assert.equal(g.ps[0].ang, 0.7); assert.equal(g.ps[0].st, EXT);
  g = set(); fire(g.room, g.ps[0], 1.0); assert.equal(g.ps[0].ang, 0.5, '差 0.5 弧度，不认'); assert.equal(g.ps[0].st, EXT, '但钩还是放出去');
  g = set(); g.ps[0].ang = 1.2; fire(g.room, g.ps[0], 1.3); assert.equal(g.ps[0].ang, 1.2, '超出摆幅，不认');
  g = set(); fire(g.room, g.ps[0], 'abc'); assert.equal(g.ps[0].ang, 0.5);
  g = set(); g.room.ph = 'shop'; fire(g.room, g.ps[0], 0.5); assert.equal(g.ps[0].st, SW, '不在挖矿阶段不能放钩');
});

test('晶甲虫：自己来回跑，被钩住就不跑了', () => {
  const { room, ps: [p] } = playing('vs', 1);
  const bug = put(room, 0, 'bug', 300, 600, { vx: 80, x0: 250, x1: 350 });
  run(room, 0.5); assert.ok(Math.abs(bug.x - 340) < 3);
  run(room, 0.5); assert.ok(bug.x <= 350 && bug.vx < 0, '到头了往回跑');
  bug.by = p.id; const x = bug.x; run(room, 0.5); assert.equal(bug.x, x);
});

test('过关判定·合作：全队手里的钱到了累计目标才过关', () => {
  const pass = playing('co', 2); pass.room.money = pass.room.target; endRound(pass.room);
  assert.equal(pass.room.final, false); assert.deepEqual((pass.room.res as any).co, { target: goalOf(1, 2), have: goalOf(1, 2), pass: true });
  const fail = playing('co', 2); fail.room.money = fail.room.target - 10; endRound(fail.room);
  assert.equal(fail.room.final, true); assert.equal((fail.room.res as any).co.pass, false);
});

test('淘汰·分屏：没到目标的淘汰，剩一个人就结束，比谁过关多', () => {
  const g = playing('race', 3);
  assert.equal(g.room.target, 600, '分屏按单人规模定目标');
  assert.equal(g.room.fields.length, 3, '每人一口井');
  const [a, b, c] = g.ps; a.money = 600; b.money = 590; c.money = 2000;
  endRound(g.room);
  assert.deepEqual([a.out, b.out, c.out], [false, true, false]);
  assert.equal(g.room.final, false, '还剩两个人，继续');
  assert.deepEqual((g.room.res as any).rows.map((r: any) => [r.ps, r.out, r.now]), [[1, 0, 0], [0, 1, 1], [1, 0, 0]]);
  nextRound(g.room);
  assert.equal(g.room.target, 1530, '第二关看累计目标');
  assert.equal(g.room.fields[1].items.length, 0, '淘汰的人井里是空的');
  assert.deepEqual(g.room.fields[0].items.map(i => [i.t, i.x, i.y]), g.room.fields[2].items.map(i => [i.t, i.x, i.y]), '没淘汰的人拿到一模一样的井');
  endRound(g.room);                                          // a 手里 600 < 1530，c 手里 2000 ≥ 1530
  assert.deepEqual([a.out, c.out], [true, false]); assert.equal(g.room.final, true, '只剩一个人，结束');
  assert.deepEqual((g.room.res as any).rows.map((r: any) => r.ps), [1, 0, 2]);
});

test('淘汰·分屏单人：过关就继续，没过就结束', () => {
  const g = playing('race', 1); g.ps[0].money = 600; endRound(g.room); assert.equal(g.room.final, false);
  nextRound(g.room); endRound(g.room); assert.equal(g.room.final, true); assert.equal(g.ps[0].passed, 1);
});

test('同屏对战：打满设定的局数才结束', () => {
  const g = playing('vs', 2); g.room.rounds = 3;
  endRound(g.room); assert.equal(g.room.final, false); nextRound(g.room);
  endRound(g.room); assert.equal(g.room.final, false); nextRound(g.room);
  endRound(g.room); assert.equal(g.room.final, true); assert.equal(g.room.round, 3);
});

test('提前结束：井里只剩炸药桶、所有钩子都收回，这一关立刻结束', () => {
  const { room, ps: [p] } = playing('vs', 1);
  put(room, 0, 'tnt', 100, 600); put(room, 0, 'gs', p.x, 400);
  tickRoom(room, DT); assert.equal(room.ph, 'play');
  fire(room, p); run(room, 5, () => room.ph !== 'play');
  assert.equal(room.ph, 'rend'); assert.equal(p.money, 50); assert.ok(room.tl > REND_T - 0.1);
});

test('整局流程：倒计时 → 挖矿 60 秒 → 结算 → 商店 → 下一关；没过关就结束', () => {
  const room = newRoom('1', rng(7)); room.mode = 'co';
  const p = newPlayer(room, { token: 'tttttttt', room: null, send() {}, close() {} }, '甲');
  startGame(room);
  assert.equal(room.ph, 'count'); assert.equal(p.tools.d, 1);
  run(room, 3.1); assert.equal(room.ph, 'play'); assert.ok(Math.abs(room.tl - ROUND_T) < 0.2);
  room.money = 5000;
  run(room, ROUND_T + 1, () => room.ph !== 'play'); assert.equal(room.ph, 'rend');
  run(room, REND_T + 0.2, () => room.ph !== 'rend'); assert.equal(room.ph, 'shop'); assert.ok(Math.abs(room.tl - SHOP_T) < 0.2);
  p.ready = true; run(room, 0.1);
  assert.equal(room.ph, 'count'); assert.equal(room.round, 2); assert.equal(room.target, goalOf(2, 1));
  run(room, 3.1); room.money = 0;
  run(room, ROUND_T + 1, () => room.ph !== 'play');
  run(room, REND_T + 0.2, () => room.ph !== 'rend');
  assert.equal(room.ph, 'over'); assert.equal((room.res as any).final, true);
});

test('商店没人点"准备好了"，45 秒后自动进下一关', () => {
  const g = playing('vs', 1); endRound(g.room);
  run(g.room, REND_T + 0.2, () => g.room.ph === 'shop');
  run(g.room, SHOP_T - 1); assert.equal(g.room.ph, 'shop');
  run(g.room, 1.2); assert.equal(g.room.ph, 'count');
});

for (const [mode, humans, bots] of [['vs', 0, 4], ['co', 0, 3], ['race', 0, 4], ['vs', 0, 1]] as const) {
  test(`电脑玩家打完整场（${mode}，${bots} 个电脑）：能走到结束，钱的进出对得上`, () => {
    for (let seed = 1; seed <= 3; seed++) {
      const room = newRoom('1', rng(seed)); room.mode = mode; room.rounds = 3;
      for (let i = 0; i < bots; i++) newPlayer(room, null, 'B' + i, true);
      startGame(room);
      const evs = run(room, 60 * 60, () => room.ph === 'over');
      assert.equal(room.ph, 'over', '一小时内应该打完');
      const got = evs.filter(e => e.e === 'get').reduce((s, e) => s + e.v, 0), total = room.players.reduce((s, p) => s + p.total, 0);
      assert.equal(got, total, '每一笔进账都有记录');
      assert.ok(total > 0, '电脑应该能挖到东西');
      if (mode === 'vs') { assert.equal(room.round, 3); for (const p of room.players) assert.ok(p.money <= p.total, '手里的钱不会比赚的多'); }
      if (mode === 'race') assert.ok(room.players.filter(p => !p.out).length <= 1);
      if (mode === 'co') assert.ok(room.money < room.target);
      for (const p of room.players) assert.ok(p.money >= 0);
    }
  });
}
