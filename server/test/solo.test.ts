import test from 'node:test';
import assert from 'node:assert/strict';
import { B, COUNT_T, EXT, FUN, HAUL, REND_T, ROUND_T, RULES, TI, TOOL_ORDER, W, goalOf } from '../src/core.ts';
import { addMoney, nextRound } from '../src/game.ts';
import { Hub } from '../src/rooms.ts';
import { openShop } from '../src/shop.ts';
import { DT, fakeConn, put, rng } from './helpers.ts';
import type { Mode } from '../src/core.ts';
import type { FakeConn } from './helpers.ts';

function setup(mode: Mode = 'solo', seed = 42) {
  const hub = new Hub(rng(seed));
  const host = fakeConn('solo-host-token');
  hub.onMsg(host, { t: 'create', mode });
  const room = host.room!;
  return { hub, host, room, miner: room.players[0] };
}

const last = (conn: FakeConn) => conn.got.at(-1);
const advance = (hub: Hub, seconds: number) => {
  for (let i = 0; i < Math.ceil(seconds / DT); i++) hub.tick(DT);
};

test('单人闯关：创建后立即发第一关倒计时，井里只有一个矿工', () => {
  const { hub, host, room, miner } = setup();
  assert.equal(host.got[0].t, 'meta');
  assert.deepEqual(host.got[0].players.map((p: any) => [p.name, p.bot]), [['矿工1', false]]);
  assert.equal(last(host).ph, 'count');
  assert.equal(last(host).rd, 1);
  assert.equal(last(host).tl, COUNT_T);
  assert.equal(last(host).F.length, 1);
  assert.equal(miner.x, W / 2);
  assert.equal(B.MODE_NAMES.solo, '单人闯关');
  hub.onMsg(host, { t: 'addBot' });
  hub.onMsg(host, { t: 'addLocal' });
  assert.equal(room.players.length, 1);
  room.tl = DT;
  hub.tick(DT);
  assert.equal(last(host).ph, 'play');
  assert.equal(last(host).tl, ROUND_T);
});

test('单人闯关：单人目标、累计余额和过关进店', () => {
  const { hub, host, room, miner } = setup();
  assert.equal(last(host).tg, goalOf(1, 1));
  advance(hub, COUNT_T + DT);
  addMoney(room, miner, room.target);
  room.tl = DT;
  hub.tick(DT);
  assert.equal(last(host).ph, 'rend');
  assert.equal(last(host).res.final, false);
  advance(hub, REND_T + DT);
  assert.equal(last(host).ph, 'shop');
  assert.equal(last(host).ng, goalOf(2, 1));
  hub.onMsg(host, { t: 'ready' });
  hub.tick(DT);
  assert.equal(last(host).ph, 'count');
  assert.equal(last(host).rd, 2);
  assert.equal(last(host).tg, goalOf(2, 1));
  assert.equal(last(host).P[0].m, goalOf(1, 1));
});

test('单人闯关：商店必有炸药，可上架和购买沙漏，不卖剪刀和冰冻', () => {
  const { hub, host, room, miner } = setup();
  let hasHourglass = false;
  for (let i = 0; i < 20; i++) {
    openShop(room);
    assert.ok(room.list.d > 0);
    assert.ok(!('s' in room.list) && !('f' in room.list));
    if (!room.list.h) continue;
    hasHourglass = true;
    const cash = room.list.h;
    miner.money = cash;
    hub.onMsg(host, { t: 'buy', i: miner.id, k: 'h' });
    assert.equal(miner.money, 0);
    assert.equal(miner.tools.h, 1);
    break;
  }
  assert.equal(hasHourglass, true);
  assert.deepEqual(TOOL_ORDER.solo, ['d', 'h']);
  nextRound(room);
  advance(hub, COUNT_T + DT);
  const tl = room.tl;
  hub.onMsg(host, { t: 'tool', i: miner.id, k: 'h' });
  assert.equal(room.tl, tl + RULES.hourglassSecs);
});

test('单人闯关：挖到熔岩层也不出合作物件，随机事件照常触发', () => {
  const { hub, room } = setup();
  room.round = 6;
  room.forceEvents = ['', '', '', '', '', '', 'rain'];
  nextRound(room);
  assert.equal(room.round, 7);
  assert.ok(room.fields[0].items.length > 5);
  assert.ok(room.fields[0].items.every(it => ![TI.gx, TI.key, TI.chest].includes(it.t)));
  assert.equal(room.event?.k, 'rain');
  advance(hub, COUNT_T + FUN.events.rain.at + 2 * DT);
  assert.equal(room.event?.st, 2);
});

test('单人闯关：暂停冻结计时、钩子、矿物、甲虫和事件，继续后恢复', () => {
  const { hub, host, room, miner } = setup();
  advance(hub, COUNT_T + DT);
  room.fields[0].items = [];
  const gold = put(room, 0, 'gs', miner.x, 340);
  const beetle = put(room, 0, 'bug', 250, 460, { vx: 70, x0: 200, x1: 500 });
  miner.tools.h = 1;
  miner.phase = 0;
  miner.ang = 0;
  hub.onMsg(host, { t: 'fire', i: miner.id });
  assert.equal(miner.st, EXT);
  advance(hub, 6 * DT);
  assert.equal(miner.st, HAUL);
  room.event = { k: 'rain', st: 0, at: room.now + DT * 2, until: 0 };
  hub.onMsg(host, { t: 'pause', paused: true });
  const saved = { tl: room.tl, now: room.now, angle: miner.ang, length: miner.len, gold: [gold.x, gold.y], bug: beetle.x };
  assert.equal(last(host).paused, true);
  hub.onMsg(host, { t: 'pause', paused: true });
  hub.onMsg(host, { t: 'tool', i: miner.id, k: 'h' });
  advance(hub, 2);
  assert.deepEqual(
    { tl: room.tl, now: room.now, angle: miner.ang, length: miner.len, gold: [gold.x, gold.y], bug: beetle.x },
    saved,
  );
  assert.equal(miner.tools.h, 1);
  assert.equal(room.event.st, 0);
  hub.onMsg(host, { t: 'pause', paused: false });
  assert.equal(last(host).paused, false);
  advance(hub, 3 * DT);
  assert.ok(room.now > saved.now);
  assert.ok(room.tl < saved.tl);
  assert.ok(miner.len < saved.length);
  assert.ok(gold.y < saved.gold[1]);
  assert.ok(beetle.x > saved.bug);
  assert.equal(room.event.st, 2);
});

test('单人闯关：可以暂停下井倒计时，商店忽略暂停', () => {
  const { hub, host, room, miner } = setup();
  const startAngle = miner.ang;
  hub.onMsg(host, { t: 'pause' });
  advance(hub, COUNT_T + 1);
  assert.equal(room.ph, 'count');
  assert.equal(room.tl, COUNT_T);
  assert.equal(miner.ang, startAngle);
  hub.onMsg(host, { t: 'pause' });
  hub.tick(DT);
  assert.ok(room.tl < COUNT_T);
  openShop(room);
  const shopTime = room.tl;
  hub.onMsg(host, { t: 'pause' });
  hub.tick(DT);
  assert.ok(room.tl < shopTime);
});

test('三种联机玩法均忽略暂停消息，倒计时照常推进', () => {
  for (const mode of ['co', 'vs', 'race'] as const) {
    const { hub, host, room } = setup(mode);
    hub.onMsg(host, { t: 'start' });
    hub.onMsg(host, { t: 'pause', paused: true });
    hub.tick(DT);
    assert.equal(room.ph, 'count');
    assert.equal(room.paused, false);
    assert.equal('paused' in last(host), false);
    assert.ok(room.tl < COUNT_T);
  }
});

test('单人闯关：别人凭房号进不来，联机房不能切成单人闯关', () => {
  const { hub, room } = setup();
  const guest = fakeConn('another-player');
  hub.onMsg(guest, { t: 'join', code: room.code, name: '访客' });
  assert.equal(guest.room, null);
  assert.match(last(guest).msg, /单人闯关.*不能加入/);
  assert.equal(room.players.length, 1);
  const { hub: multi, host, room: lobby } = setup('vs');
  multi.onMsg(host, { t: 'cfg', mode: 'solo' });
  assert.equal(lobby.mode, 'vs');
});

test('单人闯关：断线冻结，原令牌回认后仍暂停，手动继续才走时', () => {
  const { hub, host, room, miner } = setup();
  advance(hub, COUNT_T + DT);
  addMoney(room, miner, 150);
  const tl = room.tl;
  hub.leave(host);
  assert.equal(room.paused, true);
  advance(hub, 1);
  assert.equal(room.tl, tl);
  const back = fakeConn(host.token);
  hub.onMsg(back, { t: 'join', code: room.code });
  assert.deepEqual(back.got[0].you, [miner.id]);
  assert.equal(last(back).paused, true);
  assert.equal(last(back).P[0].m, 150);
  advance(hub, 1);
  assert.equal(room.tl, tl);
  hub.onMsg(back, { t: 'pause', paused: false });
  hub.tick(DT);
  assert.ok(room.tl < tl);
});

test('单人闯关：到时金额不足，结算后结束并保留本局总收入', () => {
  const { hub, host, room, miner } = setup();
  advance(hub, COUNT_T + DT);
  addMoney(room, miner, room.target - 10);
  room.tl = DT;
  hub.tick(DT);
  assert.equal(last(host).ph, 'rend');
  advance(hub, REND_T + DT);
  assert.equal(last(host).ph, 'over');
  assert.equal(last(host).res.final, true);
  assert.equal(last(host).res.round, 1);
  assert.equal(last(host).res.rows[0].tt, room.target - 10);
});

test('单人闯关：再来一局立即发第一关倒计时，清空旧局状态', () => {
  const { hub, host, room, miner } = setup();
  advance(hub, COUNT_T + DT);
  addMoney(room, miner, 100);
  miner.tools.h = 2;
  room.tl = DT;
  advance(hub, REND_T + 2 * DT);
  assert.equal(last(host).ph, 'over');
  const before = host.got.length;
  hub.onMsg(host, { t: 'again' });
  assert.equal(host.got.length, before + 1);
  assert.equal(last(host).ph, 'count');
  assert.equal(last(host).rd, 1);
  assert.equal(last(host).P[0].m, 0);
  assert.deepEqual(last(host).P[0].tl, RULES.startTools);
  assert.equal(last(host).paused, false);
  assert.equal(room.res, null);
  assert.equal(miner.total, 0);
  hub.onMsg(host, { t: 'again' });
  assert.equal(host.got.length, before + 1);
});

test('单人闯关：主动回首页立即释放房间，可以重新开始', () => {
  const { hub, host, room } = setup();
  hub.onMsg(host, { t: 'pause' });
  hub.onMsg(host, { t: 'leave' });
  assert.equal(last(host).t, 'left');
  assert.equal(host.room, null);
  assert.equal(hub.rooms.has(room.code), false);
  hub.onMsg(host, { t: 'create', mode: 'solo' });
  assert.equal(last(host).ph, 'count');
  assert.equal(last(host).paused, false);
});
