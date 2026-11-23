// 第三期（联机乐趣）的测试：分屏互相干扰、淘汰后捣乱、合作必须配合的东西、快捷喊话、随机事件、颁奖、对局记录。
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Y0, SW, HAUL, AST, TI, TYPES, FUN } from '../src/core.ts';
import type { Room, Player } from '../src/core.ts';
import { newRoom, newPlayer, startGame, nextRound, endRound, fire, useTool, snapshot } from '../src/game.ts';
import { throwRock, pickEvent, emote, awardsFor } from '../src/fun.ts';
import { openShop, buy } from '../src/shop.ts';
import { Hub } from '../src/rooms.ts';
import { playing, put, aim, run, rng, fakeConn, DT } from './helpers.ts';

const fi = (room: Room, p: Player) => room.fields.indexOf(p.f!);
const count = (room: Room, f: number, k: string) => room.fields[f].items.filter(it => it.t === TI[k]).length;
// 每口井角落里留一块巨石：井里一个东西都没有的话这一关会立刻结束
const keep = (room: Room) => room.fields.forEach((_, i) => put(room, i, 'rl', 60, 690));
// 在某人正下方放一件东西，让他钩上来，返回期间的事件
function haul(room: Room, p: Player, k = 'gs', y = 300): any[] {
  const it = put(room, fi(room, p), k, p.x, y, { hx: p.x, hy: y });
  p.ang = 0; p.phase = 0; fire(room, p);
  return run(room, 30, () => p.st === SW && (!p.f!.items.includes(it) || it.by === 0));
}
function miss(room: Room, p: Player): any[] { p.ang = 0; p.phase = 0; fire(room, p); return run(room, 10, () => p.st === SW); }

/* ───────── 1. 分屏：互相干扰 ───────── */
test('分屏：落后的人连续钩中 2 次，领先的对手井里多一块碎石', () => {
  const { room, ps: [a, b] } = playing('race', 2); keep(room);
  b.money = 500;                                             // b 领先，a 落后
  let evs = haul(room, a);
  assert.equal(a.combo, 1); assert.equal(count(room, 1, 'rs'), 0);
  assert.equal(snapshot(room).P[0].cb, 1); assert.equal(snapshot(room).P[0].cn, 2);
  evs = haul(room, a);
  const atk = evs.find(e => e.e === 'atk');
  assert.ok(atk, '应该有丢石头的事件'); assert.equal(atk.by, a.id); assert.equal(atk.to, b.id); assert.equal(atk.g, 0);
  assert.equal(count(room, 1, 'rs'), 1); assert.equal(count(room, 0, 'rs'), 0, '自己井里不掉');
  assert.equal(a.combo, 0, '丢完从头数'); assert.equal(b.rocksGot, 1); assert.equal(a.stats.thrown, 1);
});

test('分屏：领先的人要连续钩中 3 次才丢得出石头', () => {
  const { room, ps: [a, b] } = playing('race', 2); keep(room);
  a.money = 2000;
  haul(room, a); haul(room, a);
  assert.equal(count(room, 1, 'rs'), 0, '领先的人 2 次不够'); assert.equal(snapshot(room).P[0].cn, 3);
  haul(room, a);
  assert.equal(count(room, 1, 'rs'), 1); assert.equal(b.rocksGot, 1);
});

test('分屏：钩空、钩到石头、钩炸炸药桶都会断掉连续钩中', () => {
  const { room, ps: [a, b] } = playing('race', 2); keep(room);
  b.money = 500;
  haul(room, a); assert.equal(a.combo, 1);
  miss(room, a); assert.equal(a.combo, 0, '钩空断了');
  haul(room, a); haul(room, a, 'rs'); assert.equal(a.combo, 0, '钩到石头断了');
  haul(room, a); put(room, 0, 'tnt', a.x, 300); miss(room, a); assert.equal(a.combo, 0, '炸药桶断了');
  assert.equal(count(room, 1, 'rs'), 0, '一直没凑够，对手井里没有多石头');
});

test('分屏：每人每关最多挨 4 块石头，不会被砸得没法玩；下一关重新算', () => {
  const { room, ps: [a, b] } = playing('race', 2); keep(room);
  b.money = 500;
  const got = [1, 2, 3, 4, 5, 6].map(() => throwRock(room, a, false));
  assert.deepEqual(got, [true, true, true, true, false, false]);
  assert.equal(count(room, 1, 'rs'), FUN.race.rockCap);
  a.money = 9999; b.money = 9999; endRound(room); room.final = false; nextRound(room);
  assert.equal(b.rocksGot, 0); assert.equal(a.combo, 0);
});

test('同屏对战和合作：连续钩中不会丢石头', () => {
  for (const mode of ['vs', 'co'] as const) {
    const { room, ps: [a, b] } = playing(mode, 2); keep(room);
    b.money = 500;
    const evs = [...haul(room, a), ...haul(room, a), ...haul(room, a)];
    assert.ok(!evs.some(e => e.e === 'atk')); assert.equal(count(room, 0, 'rs'), 0);
    assert.equal(snapshot(room).P[0].cb, undefined);
  }
});

/* ───────── 3. 淘汰的人能捣乱 ───────── */
test('分屏：淘汰的人按放钩键是往钱最多的对手井里丢石头；开局 3 秒后才能丢，每次间隔 12 秒', () => {
  const { room, ps: [a, b, c] } = playing('race', 3); keep(room);
  c.out = true; a.money = 100; b.money = 900; room.now = 1;
  fire(room, c); assert.equal(c.ghostN, 0, '头 3 秒不行');
  room.now = FUN.race.ghostFirst + 0.1;
  fire(room, c);
  const atk = room.ev.find((e: any) => e.e === 'atk') as any;
  assert.ok(atk); assert.equal(atk.to, b.id, '丢给钱最多的'); assert.equal(atk.g, 1);
  assert.equal(count(room, 1, 'rs'), 1); assert.equal(count(room, 0, 'rs'), 0); assert.equal(c.ghostN, 1);
  assert.equal(c.st, SW, '淘汰的人自己的钩子不会动'); assert.equal(c.stats.shots, 0);
  fire(room, c); assert.equal(c.ghostN, 1, '冷却中不行');
  const snap = snapshot(room).P[2];
  assert.ok(snap.gc > 11 && snap.gc <= 12); assert.equal(snap.gn, FUN.race.ghostCap - 1);
  room.now += FUN.race.ghostCd + 0.1;
  fire(room, c); assert.equal(c.ghostN, 2); assert.equal(count(room, 1, 'rs'), 2);
});

test('分屏：淘汰的人每关最多丢 5 次；没淘汰的人、别的玩法都不能这样丢', () => {
  const { room, ps: [a, b, c] } = playing('race', 3); keep(room);
  c.out = true; b.money = 900;
  for (let i = 0; i < 8; i++) { room.now += 20; b.rocksGot = 0; fire(room, c); }
  assert.equal(c.ghostN, FUN.race.ghostCap); assert.equal(c.stats.thrown, FUN.race.ghostCap);
  const before = count(room, 1, 'rs') + count(room, 0, 'rs');
  a.ang = 0.9; fire(room, a);                               // 没淘汰的人按放钩键就是正常放钩
  assert.equal(count(room, 1, 'rs') + count(room, 0, 'rs'), before);
  const g = playing('vs', 3); keep(g.room); g.ps[2].out = true; g.room.now = 30; fire(g.room, g.ps[2]);
  assert.equal(g.room.fields[0].items.filter(it => it.t === TI.rs).length, 0);
});

test('分屏：淘汰了的电脑也会捣乱', () => {
  const { room, ps } = playing('race', 1, 3, 2); keep(room);
  ps[2].out = true; ps[0].money = 500;
  run(room, 20);
  assert.ok(ps[2].ghostN >= 1, '20 秒里电脑至少丢了一次'); assert.ok(ps[0].rocksGot >= 1);
});

/* ───────── 2. 合作：必须配合的东西 ───────── */
test('合作：巨型金块一个人拉不动，吊着等人；6 秒没人帮就松手，金块留在原地', () => {
  const { room, ps: [a] } = playing('co', 2);
  const gx = put(room, 0, 'gx', a.x, 500);
  a.ang = 0; fire(room, a);
  const evs = run(room, 3);
  assert.equal(a.st, HAUL); assert.equal(gx.by, a.id); assert.equal(gx.y, 500, '没被拉动');
  assert.ok(evs.some(e => e.e === 'heavy' && e.p === a.id), '要提示太重了');
  const hv = snapshot(room).P[0].hv; assert.ok(hv > 0 && hv < FUN.coop.giantWait);
  run(room, FUN.coop.giantWait);
  assert.equal(gx.by, 0); assert.equal(a.item, 0); assert.ok(room.fields[0].items.includes(gx)); assert.equal(room.money, 0);
});

test('合作：第二个人钩上去合拉，巨型金块才拉得上来，钱进队伍的钱包', () => {
  const { room, ps: [a, b] } = playing('co', 2);
  const gx = put(room, 0, 'gx', a.x, 500);
  a.ang = 0; fire(room, a); run(room, 2);
  aim(b, gx.x, gx.y, Y0); fire(room, b);
  run(room, 20, () => !room.fields[0].items.includes(gx));
  assert.ok(!room.fields[0].items.includes(gx), '拉上来了');
  assert.equal(room.money, Math.round(TYPES[TI.gx].v * 1.1)); assert.equal(b.stats.assists, 1); assert.equal(a.hold, 0);
});

test('合作：只有一个人时（单人闯关），巨型金块自己拉得动，也不出钥匙和宝箱', () => {
  const { room, ps: [a] } = playing('co', 1);
  const gx = put(room, 0, 'gx', a.x, 500);
  a.ang = 0; fire(room, a);
  run(room, 30, () => !room.fields[0].items.includes(gx));
  assert.equal(room.money, TYPES[TI.gx].v);
  for (let seed = 1; seed <= 10; seed++) {
    const r = newRoom('1', rng(seed)); r.mode = 'co'; newPlayer(r, fakeConn('solo-token-1'), '独'); startGame(r);
    assert.equal(r.fields[0].items.filter(it => it.t === TI.key || it.t === TI.chest).length, 0);
  }
});

test('合作：两人以上每关都有一块巨型金块、一把钥匙、一个宝箱；对战和分屏没有钥匙宝箱', () => {
  for (let seed = 1; seed <= 20; seed++) {
    const r = newRoom('1', rng(seed)); r.mode = 'co';
    newPlayer(r, fakeConn('co-token-a'), '甲'); newPlayer(r, fakeConn('co-token-b'), '乙'); startGame(r);
    const n = (k: string) => r.fields[0].items.filter(it => it.t === TI[k]).length;
    assert.equal(n('gx'), 1, 'seed ' + seed); assert.equal(n('key'), 1); assert.equal(n('chest'), 1);
    for (const mode of ['vs', 'race'] as const) {
      const q = newRoom('2', rng(seed)); q.mode = mode;
      newPlayer(q, fakeConn('vs-token-a'), '甲'); newPlayer(q, fakeConn('vs-token-b'), '乙'); startGame(q);
      assert.ok(q.fields.every(f => f.items.every(it => it.t !== TI.key && it.t !== TI.chest)));
    }
  }
});

test('合作：宝箱没钥匙打不开，掉回原处；拿钥匙的人自己拉也不行，得另一个人拉', () => {
  const { room, ps: [a, b] } = playing('co', 2);
  let evs = haul(room, a, 'chest', 420);
  const chest = room.fields[0].items.find(it => it.t === TI.chest)!;
  assert.ok(chest, '宝箱还在'); assert.equal(chest.y, 420); assert.equal(chest.by, 0); assert.equal(room.money, 0);
  assert.equal(evs.find(e => e.e === 'lock').s, '锁着，先钩钥匙');
  haul(room, a, 'key', 300);
  assert.equal(room.keyBy, a.id); assert.equal(room.money, TYPES[TI.key].v); assert.equal(snapshot(room).ky, a.id);
  a.ang = 0; a.phase = 0; fire(room, a);                    // 拿钥匙的人自己去拉宝箱
  evs = run(room, 30, () => a.st === SW && chest.by === 0);
  assert.equal(evs.find(e => e.e === 'lock').s, '得换个人来拉'); assert.ok(room.fields[0].items.includes(chest));
  aim(b, chest.x, chest.y, Y0); fire(room, b);              // 换另一个人
  evs = run(room, 30, () => !room.fields[0].items.includes(chest));
  assert.equal(room.money, TYPES[TI.key].v + TYPES[TI.chest].v); assert.equal(room.keyBy, 0);
  assert.equal(evs.find(e => e.e === 'get' && e.k === 'chest').s, '开箱！');
});

test('合作：拿钥匙的人在拉宝箱时有人帮着合拉，也算两个人，打得开', () => {
  const { room, ps: [a, b] } = playing('co', 2);
  const chest = put(room, 0, 'chest', a.x, 450, { hx: a.x, hy: 450, w: 40 });   // 调得很重，拉得慢，另一个人才来得及钩上
  haul(room, a, 'key', 300);
  a.ang = 0; a.phase = 0; fire(room, a); run(room, 1.2);
  assert.equal(a.st, HAUL);
  aim(b, chest.x, chest.y, Y0); fire(room, b);
  run(room, 0.8); assert.equal(b.st, AST, '钩上去合拉了');
  run(room, 40, () => !room.fields[0].items.includes(chest));
  assert.equal(room.money, TYPES[TI.key].v + Math.round(TYPES[TI.chest].v * 1.1));
});

test('合作：有人吊着巨型金块时，电脑会过来帮忙；电脑自己不先去钩巨型金块', () => {
  const { room, ps: [a, bot] } = playing('co', 1, 7, 1);
  const gx = put(room, 0, 'gx', a.x, 480);
  run(room, 8);
  assert.equal(gx.by, 0, '电脑不先动手'); assert.equal(bot.stats.shots, 0);
  a.ang = 0; a.phase = 0; a.st = SW; fire(room, a);
  run(room, FUN.coop.giantWait + 6, () => !room.fields[0].items.includes(gx));
  assert.ok(!room.fields[0].items.includes(gx), '电脑帮着拉上来了'); assert.equal(bot.stats.assists, 1);
  assert.equal(room.money, Math.round(TYPES[TI.gx].v * 1.1));
});

/* ───────── 4. 快捷喊话 ───────── */
test('喊话：发出去所有人收得到，只收编号；2 秒内不能连发；编号不对、别人的座位、还没开打都不行', () => {
  const hub = new Hub(rng(3));
  const c1 = fakeConn('emo-token-1'), c2 = fakeConn('emo-token-2');
  hub.onMsg(c1, { t: 'create', name: '甲', mode: 'vs' }); const room = c1.room!;
  hub.onMsg(c2, { t: 'join', code: room.code, name: '乙' });
  const [a, b] = room.players;
  hub.onMsg(c1, { t: 'emote', i: a.id, k: 0 });
  assert.equal(a.stats.emotes, 0, '在房间里等人的时候不行');
  hub.onMsg(c1, { t: 'start' });
  hub.onMsg(c1, { t: 'emote', i: a.id, k: 1 });
  assert.deepEqual(room.ev.filter((e: any) => e.e === 'emo'), [{ e: 'emo', p: a.id, k: 1 }]);
  c2.got.length = 0; hub.tick(DT, 1e9);
  const s = c2.got.find(m => m.t === 's');
  assert.ok(s.E.some((e: any) => e.e === 'emo' && e.p === a.id && e.k === 1), '另一个人收到了');
  hub.onMsg(c1, { t: 'emote', i: a.id, k: 2 }); assert.equal(a.stats.emotes, 1, '2 秒内第二次不行');
  hub.onMsg(c1, { t: 'emote', i: b.id, k: 2 }); assert.equal(b.stats.emotes, 0, '不能替别人喊');
  for (const k of [-1, 6, 1.5, 'abc', null, '你好啊']) hub.onMsg(c2, { t: 'emote', i: b.id, k });
  assert.equal(b.stats.emotes, 0, '编号不对的不收');
  const t0 = Date.now() + 10_000;
  assert.equal(emote(room, a, 3, t0), true); assert.equal(emote(room, a, 3, t0 + 1900), false); assert.equal(emote(room, a, 3, t0 + 2100), true);
  assert.equal(FUN.emotes.length, 6);
});

/* ───────── 6. 随机事件 ───────── */
test('随机事件：第 1 关没有；之后每关最多一个，大约七成的关有，三种都会出', () => {
  const room = newRoom('1', rng(11));
  room.round = 1; pickEvent(room); assert.equal(room.event, null);
  const seen: Record<string, number> = {}; let n = 0;
  for (let i = 0; i < 600; i++) { room.round = 2 + (i % 8); pickEvent(room); if (room.event) { n++; seen[room.event.k] = (seen[room.event.k] || 0) + 1; assert.equal(room.event.st, 0); } }
  assert.ok(n / 600 > 0.62 && n / 600 < 0.78, '有事件的关占 ' + n / 600);
  assert.deepEqual(Object.keys(seen).sort(), ['cave', 'dark', 'rain']);
  for (const k of Object.keys(seen)) assert.ok(seen[k] > 100, k + ' 出现 ' + seen[k] + ' 次');
  assert.equal(room.evHist.length, 601);
});

test('随机事件：倒计时阶段就告诉大家这一关是什么事件、多少秒后来', () => {
  const room = newRoom('1', rng(2)); room.mode = 'vs'; room.forceEvents = ['cave', 'rain'];
  newPlayer(room, fakeConn('ev-token-1'), '甲'); startGame(room);
  assert.equal(room.ph, 'count');
  assert.deepEqual(snapshot(room).ev, ['cave', 0, FUN.events.cave.at]);
  endRound(room); room.final = false; nextRound(room);
  assert.deepEqual(snapshot(room).ev, ['rain', 0, FUN.events.rain.at]);
  endRound(room); room.final = false; nextRound(room);
  assert.equal(snapshot(room).ev, undefined, '没指定的关没有事件');
  assert.deepEqual(room.evHist, ['cave', 'rain', '']);
});

test('金矿雨：第 12 秒每口井掉下 6 块小金块、2 块金块；分屏每口井掉的位置一样，淘汰的人井里不掉', () => {
  const { room, ps } = playing('race', 3); keep(room);
  ps[2].out = true; room.fields[2].items = [];
  room.event = { k: 'rain', st: 0, at: FUN.events.rain.at, until: 0 };
  let evs = run(room, FUN.events.rain.at - 0.5);
  assert.equal(count(room, 0, 'gs'), 0, '还没到时间');
  evs = run(room, 1);
  assert.ok(evs.some(e => e.e === 'event' && e.k === 'rain' && e.on === 1));
  for (const f of [0, 1]) { assert.equal(count(room, f, 'gs'), 6); assert.equal(count(room, f, 'gm'), 2); }
  const pos = (f: number) => room.fields[f].items.filter(it => it.t !== TI.rl).map(it => it.t + ':' + it.x + ',' + it.y).sort().join(' ');
  assert.equal(pos(0), pos(1)); assert.equal(room.fields[2].items.length, 0);
  assert.equal(room.event.st, 2); assert.equal(snapshot(room).ev[1], 2);
  run(room, 5); assert.equal(count(room, 0, 'gs'), 6, '只掉一次');
});

test('塌方：第 18 秒掉下 3 块碎石、2 块巨石，不会压在已有的东西上', () => {
  const { room } = playing('vs', 2); keep(room);
  for (let i = 0; i < 12; i++) put(room, 0, 'gm', 120 + i * 90, 400);
  room.event = { k: 'cave', st: 0, at: FUN.events.cave.at, until: 0 };
  const evs = run(room, FUN.events.cave.at + 0.5);
  assert.ok(evs.some(e => e.e === 'event' && e.k === 'cave'));
  assert.equal(count(room, 0, 'rs'), 3); assert.equal(count(room, 0, 'rl'), 1 + 2);
  const its = room.fields[0].items;
  for (let i = 0; i < its.length; i++) for (let j = i + 1; j < its.length; j++) {
    assert.ok(Math.hypot(its[i].x - its[j].x, its[i].y - its[j].y) > its[i].r + its[j].r, '两个东西叠在一起了');
  }
});

test('黑灯：第 10 秒开始，持续 15 秒后恢复；状态里能看到正在黑灯和还剩几秒', () => {
  const { room } = playing('co', 2); keep(room);
  room.event = { k: 'dark', st: 0, at: FUN.events.dark.at, until: 0 };
  let evs = run(room, FUN.events.dark.at + 0.5);
  assert.ok(evs.some(e => e.e === 'event' && e.k === 'dark' && e.on === 1));
  let s = snapshot(room).ev; assert.equal(s[0], 'dark'); assert.equal(s[1], 1); assert.ok(s[2] > 14 && s[2] <= 15);
  evs = run(room, FUN.events.dark.secs + 0.2);
  assert.ok(evs.some(e => e.e === 'event' && e.k === 'dark' && e.on === 0));
  assert.equal(snapshot(room).ev[1], 2);
  assert.equal(room.fields[0].items.length, 1, '黑灯不动井里的东西');
});

/* ───────── 5. 颁奖 ───────── */
test('颁奖：整场打完每人正好一个奖，按数据发；没到最后一关不颁', () => {
  const { room, ps: [a, b, c, d] } = playing('vs', 4); keep(room);
  Object.assign(a.stats, { shots: 10, hits: 9 });
  Object.assign(b.stats, { shots: 10, hits: 3, tnt: 3 });
  Object.assign(c.stats, { shots: 10, hits: 5, rocks: 6, miss: 5 });
  Object.assign(d.stats, { shots: 2, hits: 0, miss: 2 });
  endRound(room);
  assert.equal(room.final, false); assert.equal((room.res as any).awards, undefined);
  room.round = room.rounds; endRound(room);
  const aw = (room.res as any).awards as { id: number; n: string; say: string }[];
  assert.equal(aw.length, 4); assert.equal(new Set(aw.map(x => x.id)).size, 4, '每人一个');
  const of = (p: Player) => aw.find(x => x.id === p.id)!.n;
  assert.equal(of(a), '最准'); assert.equal(of(b), '炸药桶爱好者'); assert.equal(of(c), '石头王'); assert.equal(of(d), '重在参与');
  assert.match(aw.find(x => x.id === a.id)!.say, /放钩 10 次，钩中 9 次/);
});

test('颁奖：捣蛋鬼、好帮手、一钩暴富、最倒霉、话最多各有条件', () => {
  const { room, ps: [a, b, c, d] } = playing('race', 4);
  a.stats.thrown = 3; b.stats.assists = 2; c.stats.best = 900; d.stats.miss = 7;
  const names = Object.fromEntries(awardsFor(room).map(x => [x.id, x.n]));
  assert.equal(names[a.id], '捣蛋鬼'); assert.equal(names[b.id], '好帮手'); assert.equal(names[c.id], '一钩暴富'); assert.equal(names[d.id], '最倒霉');
  const g = playing('vs', 1); g.ps[0].stats.emotes = 5;
  assert.equal(awardsFor(g.room)[0].n, '话最多');
});

/* ───────── 9. 对局记录 ───────── */
test('每人的数据：出手、钩中、钩空、石头、炸药桶、最值钱的一钩、用了什么道具、买了什么、每关收入', () => {
  const { room, ps: [a] } = playing('vs', 1); keep(room);
  miss(room, a);
  haul(room, a, 'gs'); haul(room, a, 'rs'); haul(room, a, 'gl');
  put(room, 0, 'tnt', a.x, 300); miss(room, a);
  const rl = put(room, 0, 'rl', a.x, 320); a.ang = 0; a.phase = 0; fire(room, a); run(room, 1); useTool(room, a, 'd'); run(room, 3, () => a.st === SW);
  assert.ok(!room.fields[0].items.includes(rl));
  const s = a.stats;
  assert.equal(s.shots, 6); assert.equal(s.hits, 5); assert.equal(s.miss, 1); assert.equal(s.rocks, 1); assert.equal(s.tnt, 1);
  assert.equal(s.best, 500); assert.deepEqual(s.tools, { d: 1 });
  endRound(room); assert.deepEqual(s.rounds, [50 + 11 + 500]);
  room.final = false; openShop(room, ['d', 'book']); a.money = 999;
  assert.equal(buy(room, a, 'book'), true); assert.deepEqual(s.buys, { book: 1 });
});

test('对局记录：整场打完存成一个文件，有每人的出手、命中率、每关收入、道具、事件；没有玩家打的字', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dm-log-'));
  const hub = new Hub(rng(9), () => [], dir);
  const c1 = fakeConn('log-token-1');
  hub.onMsg(c1, { t: 'create', name: '甲', mode: 'vs' }); const room = c1.room!;
  hub.onMsg(c1, { t: 'addBot' });
  room.forceEvents = ['', 'rain', 'dark'];
  hub.onMsg(c1, { t: 'start' });
  const now = Date.now() + 5000;
  const tick = (n = 1) => { for (let i = 0; i < n; i++) hub.tick(DT, now); };
  const [a] = room.players;
  tick(100); assert.equal(room.ph, 'play');
  hub.onMsg(c1, { t: 'fire', i: a.id }); tick(60);
  room.tl = 0.01; tick(2); assert.equal(room.ph, 'rend');
  room.tl = 0.01; tick(2); assert.equal(room.ph, 'shop');
  hub.onMsg(c1, { t: 'say', i: a.id, text: '老板你真帅，便宜点嘛' });
  hub.onMsg(c1, { t: 'emote', i: a.id, k: 0 });
  assert.equal(hub.logs.length, 0, '没打完不存');
  hub.onMsg(c1, { t: 'ready' }); tick(120); assert.equal(room.ph, 'play'); assert.equal(room.round, 2);
  room.round = 3; room.tl = 0.01; tick(2);
  assert.equal(room.final, true); assert.equal(hub.logs.length, 1);
  tick(300); assert.equal(hub.logs.length, 1, '一场只存一次');
  const files = fs.readdirSync(dir);
  assert.equal(files.length, 1); assert.match(files[0], /^\d{8}-\d{6}-\d{4}-vs\.json$/);
  const text = fs.readFileSync(path.join(dir, files[0]), 'utf8'), log = JSON.parse(text);
  assert.equal(log.mode, 'vs'); assert.equal(log.players.length, 2);
  assert.deepEqual(log.events.slice(0, 2), [{ round: 1, event: null }, { round: 2, event: 'rain' }]);
  const me = log.players.find((p: any) => p.name === '甲');
  assert.ok(me.shots >= 1); assert.equal(typeof me.hits, 'number'); assert.ok(Array.isArray(me.incomeByRound) && me.incomeByRound.length >= 2);
  assert.equal(me.hitRate, Math.round(me.hits / me.shots * 1000) / 1000);
  assert.equal(me.emotes, 1); assert.ok('toolsUsed' in me && 'bought' in me && 'award' in me && me.award);
  assert.ok(!text.includes('真帅') && !text.includes('便宜点'), '不能记玩家打的字');
  assert.ok(!/ksay|"text"/.test(text));
  fs.rmSync(dir, { recursive: true });
});

test('合作：宝箱挡在路上时，电脑不会因为"不该钩宝箱"就当它不存在，误钩上去', () => {
  const { room, ps: [a, bot] } = playing('co', 1, 5, 1);
  put(room, 0, 'chest', bot.x, 330, { hx: bot.x, hy: 330 });      // 宝箱正挡在电脑和金块之间
  put(room, 0, 'gl', bot.x, 480);
  const evs = run(room, 25);
  assert.ok(!evs.some(e => e.e === 'lock'), '电脑钩到了打不开的宝箱');
  assert.ok(room.fields[0].items.some(it => it.t === TI.chest && it.by === 0));
  void a;
});

test('颁奖：真人先挑，电脑拿剩下的（电脑瞄准了才出手，命中率总是最高，不能每次都把"最准"拿走）', () => {
  const { room, ps: [a, bot] } = playing('vs', 1, 1, 1);
  Object.assign(a.stats, { shots: 10, hits: 6 });
  Object.assign(bot.stats, { shots: 20, hits: 20, rocks: 4 });
  const names = Object.fromEntries(awardsFor(room).map(x => [x.id, x.n]));
  assert.equal(names[a.id], '最准'); assert.equal(names[bot.id], '石头王');
});
