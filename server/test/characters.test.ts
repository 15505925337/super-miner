// 角色选择和技能都走服务端入口。用固定随机数对照有无加成的结果。
import test from 'node:test';
import assert from 'node:assert/strict';
import { BAG, EXT, EXT_V, HAUL, HAUL_V, HELP, RET, RET_V, STRONG, SW, AST, Y0 } from '../src/core.ts';
import { botThink, openBag, snapshot, stepPlayer } from '../src/game.ts';
import { Hub } from '../src/rooms.ts';
import { buyClick, keeperAct, openShop } from '../src/shop.ts';
import { DT, fakeConn, playing, put, rng } from './helpers.ts';

function lobby() {
  const hub = new Hub(rng(42));
  const host = fakeConn('character-host');
  const guest = fakeConn('character-guest');
  hub.onMsg(host, { t: 'create', name: '甲' });
  const room = host.room!;
  hub.onMsg(guest, { t: 'join', code: room.code, name: '乙' });
  return { hub, room, host, guest, p: room.players[0], q: room.players[1] };
}

test('选角色：默认按空位分配，改选广播给所有人，真人占用的角色拒绝重复选择', () => {
  const { hub, room, host, guest, p, q } = lobby();
  assert.deepEqual(room.players.map(player => player.c), [0, 1]);
  hub.onMsg(guest, { t: 'pick', i: q.id, c: 3 });
  for (const conn of [host, guest]) {
    assert.deepEqual(conn.got.at(-1).players.map((player: { c: number }) => player.c), [0, 3]);
  }
  hub.onMsg(host, { t: 'pick', i: p.id, c: 3 });
  assert.match(host.got.at(-1).msg, /已有玩家/);
  hub.onMsg(host, { t: 'start' });
  hub.tick(DT);
  assert.deepEqual(guest.got.at(-1).P.map((player: { c: number }) => player.c), [0, 3]);
  hub.onMsg(guest, { t: 'pick', i: q.id, c: 2 });
  assert.equal(q.c, 3, '离开房间等待阶段后锁定角色');
});

test('选角色：同机座位各自能选，其他连接和非法编号不能替它改选', () => {
  const { hub, room, host, guest, p } = lobby();
  hub.onMsg(host, { t: 'addLocal' });
  const local = room.players[2];
  hub.onMsg(guest, { t: 'pick', i: local.id, c: 3 });
  assert.equal(local.c, 2);
  for (const c of [-1, 4, 2.5, '3', null, undefined]) {
    hub.onMsg(host, { t: 'pick', i: local.id, c });
    assert.match(host.got.at(-1).msg, /编号无效/);
    assert.equal(local.c, 2);
  }
  hub.onMsg(host, { t: 'pick', i: local.id, c: 3 });
  hub.onMsg(host, { t: 'pick', i: p.id, c: 2 });
  hub.onMsg(host, { t: 'pick', i: p.id, c: 3 });
  assert.match(host.got.at(-1).msg, /已有玩家/);
  assert.deepEqual(room.players.map(player => player.c), [2, 1, 3]);
});

test('选角色：满员时电脑接手真人腾出的角色，座位和名字保持原样', () => {
  const { hub, room, host, guest, q } = lobby();
  hub.onMsg(host, { t: 'addBot' });
  hub.onMsg(host, { t: 'addBot' });
  const seats = room.players.map(p => [p.id, p.name, p.x]);
  assert.deepEqual(room.players.map(p => p.c), [0, 1, 2, 3]);
  hub.onMsg(guest, { t: 'pick', i: q.id, c: 3 });
  const meta = host.got.at(-1);
  assert.deepEqual(meta.players.map((p: { c: number }) => p.c), [0, 3, 2, 1]);
  assert.deepEqual(room.players.map(p => [p.id, p.name, p.x]), seats);
});

test('选角色：单人开局带角色，保留自定义名，再开一局沿用同一角色', () => {
  const hub = new Hub(rng(11));
  const solo = fakeConn('character-solo');
  hub.onMsg(solo, { t: 'create', name: ' 自己的名字 ', mode: 'solo', c: 4 });
  assert.match(solo.got.at(-1).msg, /编号无效/);
  assert.equal(hub.rooms.size, 0);
  hub.onMsg(solo, { t: 'create', name: ' 自己的名字 ', mode: 'solo', c: 3 });
  assert.equal(solo.got[1].players[0].c, 3);
  assert.equal(solo.got[1].players[0].name, '自己的名字');
  assert.equal(solo.got.at(-1).ph, 'count');
  assert.equal(solo.got.at(-1).P[0].c, 3);
  solo.room!.ph = 'over';
  hub.onMsg(solo, { t: 'again' });
  assert.equal(solo.got.at(-1).P[0].c, 3);
  hub.onMsg(solo, { t: 'leave' });
  hub.onMsg(solo, { t: 'create', mode: 'solo', c: 2 });
  assert.equal(solo.room!.players[0].name, '女机械师');
});

test('愣头青：同一组预生成随机数保留原来的好结果，按比例把空袋补到 100% 好结果', () => {
  const { room, ps: [p, q] } = playing('race', 2);
  room.rnd = () => { throw new Error('开袋不应再抽随机数'); };
  const bag = put(room, 0, 'bag', 500, 450, { roll2: 0.1 });
  const counts = [{ 钱: 0, 道具: 0, 大力: 0, 空袋子: 0 }, { 钱: 0, 道具: 0, 大力: 0, 空袋子: 0 }];
  for (let i = 0; i < 10000; i++) {
    const roll = (i + 0.5) / 10000;
    bag.roll = roll;
    const boosted = openBag(room, p, bag);
    const base = openBag(room, q, bag);
    if (roll < BAG.strongBelow) assert.deepEqual(boosted, base);
    for (const [idx, reward] of [boosted, base].entries()) {
      const kind = reward.s === '空袋子' ? '空袋子' : reward.s === '大力！' ? '大力' : reward.s ? '道具' : '钱';
      counts[idx][kind]++;
    }
    assert.equal(bag.roll, roll);
  }
  assert.deepEqual(counts, [{ 钱: 6111, 道具: 2222, 大力: 1667, 空袋子: 0 }, { 钱: 5500, 道具: 2000, 大力: 1500, 空袋子: 1000 }]);
});

test('愣头青：幸运草照原来的比例给钱或道具，角色加成不重复叠到奖励档', () => {
  const { room, ps: [p, q] } = playing('race', 2);
  const bag = put(room, 0, 'bag', 500, 450, { roll2: 0.5 });
  p.buff.clover = q.buff.clover = 1;
  bag.roll = 0.59;
  assert.deepEqual(openBag(room, p, bag), { v: 580 });
  assert.deepEqual(openBag(room, q, bag), { v: 580 });
  bag.roll = 0.95;
  assert.deepEqual(openBag(room, p, bag), { v: 100, s: '剪刀 ×1' });
  assert.deepEqual(openBag(room, q, bag), { v: 100, s: '剪刀 ×1' });
});

test('老把式：重量达到 3 才加速，重物速度与大力饮料和合拉相乘', () => {
  const { room, ps: [p, helper] } = playing('co', 2);
  const it = put(room, 0, 'fos', p.x, 470, { by: p.id });
  const travel = (c: number, w: number) => {
    p.c = c; p.len = 300; p.st = HAUL; p.item = it.id; it.w = w;
    stepPlayer(room, p, DT);
    return 300 - p.len;
  };
  assert.equal(travel(0, 2.99), travel(1, 2.99));
  const base = travel(0, 3);
  assert.ok(Math.abs(travel(1, 3) - base * 1.10) < 1e-9);
  p.buff.drink = 1;
  helper.st = AST; helper.item = it.id;
  const combined = travel(0, 3);
  assert.ok(Math.abs(combined - HAUL_V / 3 * STRONG * (1 + HELP) * DT) < 1e-9);
  assert.ok(Math.abs(travel(1, 3) - combined * 1.10) < 1e-9);
});

test('女机械师：钩爪伸出与空收快 8%，拉货速度相同', () => {
  const { room, ps: [p] } = playing('solo', 1);
  const it = put(room, 0, 'fos', p.x, 670, { by: p.id });
  const travel = (c: number, state: number) => {
    p.c = c; p.len = 160; p.st = state; p.item = it.id;
    stepPlayer(room, p, DT);
    return Math.abs(p.len - 160);
  };
  for (const [state, speed] of [[EXT, EXT_V], [RET, RET_V]]) {
    assert.ok(Math.abs(travel(0, state) - speed * DT) < 1e-9);
    assert.ok(Math.abs(travel(2, state) - speed * DT * 1.08) < 1e-9);
  }
  assert.equal(travel(2, HAUL), travel(0, HAUL));
});

test('电脑按角色拉货速度判断时间，同一块重物只有老把式赶得及', () => {
  const { room, ps: [human, bot] } = playing('vs', 1, 1, 1);
  put(room, 0, 'gl', bot.x, Y0 + 320, { w: 3 });
  room.rnd = () => 0;
  room.tl = 0.9;
  bot.botCd = 0;
  bot.c = 0; human.c = 1;
  botThink(room, bot, DT);
  assert.equal(bot.st, SW);
  bot.c = 1; human.c = 0;
  botThink(room, bot, DT);
  assert.equal(bot.st, EXT);
});

test('老学究：特价也按 9 折，快照显示的每座位要价和实扣一致', () => {
  const { room, ps: [normal, scholar] } = playing('vs', 2);
  scholar.c = 3;
  room.rnd = () => 0.49;
  openShop(room, ['d', 'drink']);
  assert.equal(room.sale, 'd');
  const s = snapshot(room);
  assert.deepEqual(s.P[0].ak, s.pr);
  assert.deepEqual(s.P[1].ak, { d: s.pr.d * 0.9, drink: s.pr.drink * 0.9 });
  normal.money = scholar.money = 1000;
  assert.equal(buyClick(room, normal, 'd'), true);
  assert.equal(buyClick(room, scholar, 'd'), true);
  assert.equal(1000 - normal.money, s.pr.d);
  assert.equal(1000 - scholar.money, s.P[1].ak.d);
});

test('老学究：还价掉耐心少 20%，折后底价不被十元取整压低', () => {
  const { room, ps: [normal, scholar] } = playing('vs', 2);
  scholar.c = 3;
  room.rnd = () => 0.49;
  openShop(room, ['d', 'drink']);
  normal.mood = scholar.mood = 80;
  normal.money = scholar.money = 1000;
  const now = Date.now() + 1000;
  keeperAct(room, normal, 'offer', 'd', 1, null, now);
  keeperAct(room, scholar, 'offer', 'd', 1, null, now);
  assert.deepEqual([normal.mood, scholar.mood], [55, 60]);
  assert.equal(room.floor.d, 60);
  keeperAct(room, scholar, 'offer', 'd', 50, null, now + 1000, () => ({ action: 'counter', price: 53 }));
  assert.equal(scholar.deal.d.ask, 54);
  keeperAct(room, scholar, 'offer', 'd', 53, null, now + 2000, () => ({ action: 'accept' }));
  assert.equal(scholar.deal.d.ask, 54);
  assert.equal(scholar.money, 1000);
  keeperAct(room, scholar, 'offer', 'd', 54, null, now + 3000);
  assert.equal(scholar.money, 946);
  assert.equal(scholar.ka, 'sigh');
});
