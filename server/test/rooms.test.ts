// 房间的测试：开房、进房、房主操作、同机多人、掉线保留座位和重连。
import test from 'node:test';
import assert from 'node:assert/strict';
import { EXT, SW, TI } from '../src/core.ts';
import { Hub } from '../src/rooms.ts';
import { fakeConn, rng } from './helpers.ts';
import { openShop } from '../src/shop.ts';
import type { FakeConn } from './helpers.ts';

const last = (c: FakeConn, t: string) => [...c.got].reverse().find(m => m.t === t);
function hubWith(n: number, mode = 'vs') {
  const hub = new Hub(rng(5));
  const conns = Array.from({ length: n }, (_, i) => fakeConn('tok-' + i + '-abcdef'));
  hub.onMsg(conns[0], { t: 'create', name: '房主', mode });
  const room = conns[0].room!;
  for (let i = 1; i < n; i++) hub.onMsg(conns[i], { t: 'join', code: room.code, name: '玩家' + i });
  return { hub, conns, room };
}
const steps = (hub: Hub, secs: number) => { for (let t = 0; t < secs; t += 1 / 30) hub.tick(1 / 30, 1e9); };

test('开房：得到 4 位数房间号，开房的人是房主', () => {
  const { conns: [c], room } = hubWith(1, 'co');
  assert.match(room.code, /^\d{4}$/); assert.equal(room.mode, 'co');
  const meta = last(c, 'meta');
  assert.equal(meta.host, true); assert.equal(meta.code, room.code); assert.equal(meta.players.length, 1);
  assert.equal(meta.players[0].name, '房主'); assert.deepEqual(meta.you, [meta.players[0].id]);
});

test('进房：房间号不对、满员、已经开打，都进不去并说明原因', () => {
  const { hub, conns, room } = hubWith(4);
  const x = fakeConn('tok-x-abcdefgh');
  hub.onMsg(x, { t: 'join', code: '0000', name: '路人' }); assert.equal(last(x, 'err').msg, '没有这个房间');
  hub.onMsg(x, { t: 'join', code: room.code, name: '路人' }); assert.equal(last(x, 'err').msg, '房间满了，最多 4 人');
  assert.equal(room.players.length, 4);
  const b = hubWith(1); b.hub.onMsg(b.conns[0], { t: 'start' });
  const y = fakeConn('tok-y-abcdefgh');
  b.hub.onMsg(y, { t: 'join', code: b.room.code, name: '迟到' }); assert.ok(last(y, 'err').msg.includes('已经开打了'));
  void conns;
});

test('名字：去掉多余空格，最长 10 个字，空名字给个默认的', () => {
  const { hub, conns: [c], room } = hubWith(1);
  const a = fakeConn('tok-a-abcdefgh'), b = fakeConn('tok-b-abcdefgh');
  hub.onMsg(a, { t: 'join', code: room.code, name: '  一二三四五六七八九十十一  ' });
  hub.onMsg(b, { t: 'join', code: room.code, name: '   ' });
  assert.equal(room.players[1].name, '一二三四五六七八九十'); assert.equal(room.players[2].name, '矿工3');
  void c;
});

test('房主操作：只有房主能换玩法、改局数、加电脑、开始', () => {
  const { hub, conns: [host, guest], room } = hubWith(2);
  hub.onMsg(guest, { t: 'cfg', mode: 'co' }); assert.equal(room.mode, 'vs');
  hub.onMsg(guest, { t: 'addBot' }); assert.equal(room.players.length, 2);
  hub.onMsg(guest, { t: 'start' }); assert.equal(room.ph, 'lobby');
  hub.onMsg(host, { t: 'cfg', mode: 'race', rounds: 5 }); assert.equal(room.mode, 'race'); assert.equal(room.rounds, 5);
  hub.onMsg(host, { t: 'cfg', rounds: 4 }); assert.equal(room.rounds, 5, '局数只能是 3 或 5');
  hub.onMsg(host, { t: 'cfg', mode: 'xxx' }); assert.equal(room.mode, 'race');
  hub.onMsg(host, { t: 'addBot' }); hub.onMsg(host, { t: 'addBot' }); hub.onMsg(host, { t: 'addBot' });
  assert.equal(room.players.length, 4, '最多 4 人'); assert.deepEqual(room.players.slice(2).map(p => [p.name, p.bot]), [['阿铁', true], ['小钨', true]]);
  hub.onMsg(host, { t: 'start' }); assert.equal(room.ph, 'count');
});

test('同一台设备多人：共用一条连接，各自的钩子只有这条连接能控制', () => {
  const { hub, conns: [host, guest], room } = hubWith(2);
  hub.onMsg(host, { t: 'addLocal' });
  assert.equal(room.players.length, 3); assert.equal(last(host, 'meta').you.length, 2); assert.equal(last(guest, 'meta').you.length, 1);
  hub.onMsg(host, { t: 'start' }); steps(hub, 3.2); assert.equal(room.ph, 'play');
  const [p1, p2, p3] = room.players;
  hub.onMsg(guest, { t: 'fire', i: p1.id }); assert.equal(p1.st, SW, '别人不能替我放钩');
  hub.onMsg(host, { t: 'fire', i: p3.id }); assert.equal(p3.st, EXT, '本机第二个人的钩子能放');
  hub.onMsg(host, { t: 'fire', i: p1.id }); assert.equal(p1.st, EXT);
  hub.onMsg(guest, { t: 'fire', i: p2.id }); assert.equal(p2.st, EXT);
});

test('请人出房间：房主能请走别人，自己加的本机玩家能自己撤', () => {
  const { hub, conns: [host, guest], room } = hubWith(2);
  hub.onMsg(guest, { t: 'addLocal' });
  const [h, g, extra] = room.players;
  hub.onMsg(guest, { t: 'kick', id: h.id }); assert.equal(room.players.length, 3, '客人不能请走房主');
  hub.onMsg(guest, { t: 'kick', id: g.id }); assert.equal(room.players.length, 3, '不能撤掉自己的第一个座位');
  hub.onMsg(guest, { t: 'kick', id: extra.id }); assert.equal(room.players.length, 2, '自己加的本机玩家能撤');
  hub.onMsg(host, { t: 'kick', id: g.id });
  assert.equal(room.players.length, 1); assert.equal(guest.room, null); assert.equal(last(guest, 'left').msg, '你被房主请出了房间');
});

test('掉线：等人阶段直接离开；房主走了换人当房主；人走光房间就没了', () => {
  const { hub, conns: [host, guest], room } = hubWith(2);
  hub.leave(host);
  assert.equal(room.players.length, 1); assert.equal(last(guest, 'meta').host, true);
  hub.leave(guest); assert.equal(hub.rooms.size, 0);
});

test('掉线重连：对局中掉线座位保留，用同一个身份回来接着打', () => {
  const { hub, conns: [host, guest], room } = hubWith(2);
  hub.onMsg(host, { t: 'start' }); steps(hub, 3.2);
  const seat = room.players[1]; seat.money = 320;
  hub.leave(guest);
  assert.equal(room.players.length, 2, '座位还在'); assert.equal(seat.conn, null);
  assert.equal(last(host, 'meta').players[1].on, false, '别人看到他掉线了');
  steps(hub, 2); assert.equal(room.ph, 'play', '其他人接着打');
  const back = fakeConn('whatever-new-id');
  hub.onMsg(back, { t: 'hello', token: guest.token });
  hub.onMsg(back, { t: 'join', code: room.code, name: '换了个名字' });
  assert.equal(room.players.length, 2, '没有多出一个人'); assert.equal(seat.conn, back); assert.equal(seat.money, 320); assert.equal(seat.name, '玩家1');
  assert.deepEqual(last(back, 'meta').you, [seat.id]); assert.equal(last(host, 'meta').players[1].on, true);
  hub.onMsg(back, { t: 'fire', i: seat.id }); assert.equal(seat.st, EXT, '回来后能接着操作');
  const stranger = fakeConn('someone-else-id');
  hub.onMsg(stranger, { t: 'join', code: room.code, name: '陌生人' });
  assert.ok(last(stranger, 'err'), '别人不能顶替他的座位');
});

test('掉线重连：同一个身份开了第二个页面，旧的那条连接被断开', () => {
  const { hub, conns: [host], room } = hubWith(1);
  hub.onMsg(host, { t: 'start' });
  const again = fakeConn('zzzzzzzzzz'); hub.onMsg(again, { t: 'hello', token: host.token });
  hub.onMsg(again, { t: 'join', code: room.code });
  assert.equal(host.closed, true); assert.equal(room.players[0].conn, again); assert.equal(room.conns.size, 1);
});

test('网页离开时报一声：对局中当作掉线，座位保留，别人马上看到；不认识的身份没有影响', () => {
  const { hub, conns: [host, guest], room } = hubWith(2);
  hub.onMsg(host, { t: 'start' });
  assert.equal(hub.dropToken('nobody-knows-this'), 0);
  assert.equal(hub.dropToken(guest.token), 1);
  assert.equal(room.players.length, 2); assert.equal(room.players[1].conn, null); assert.equal(guest.closed, true);
  assert.equal(last(host, 'meta').players[1].on, false);
  const back = fakeConn('fresh-connection'); hub.onMsg(back, { t: 'hello', token: guest.token }); hub.onMsg(back, { t: 'join', code: room.code });
  assert.equal(room.players[1].conn, back); assert.equal(last(host, 'meta').players[1].on, true);
});

test('清房：对局中所有人都掉线，30 秒后房间清掉；30 秒内回来还在', () => {
  const { hub, conns: [host], room } = hubWith(1);
  hub.onMsg(host, { t: 'start' });
  hub.leave(host, 1_000_000);
  hub.tick(1 / 30, 1_000_000 + 29_000); assert.equal(hub.rooms.size, 1);
  const back = fakeConn('yyyyyyyyyy'); hub.onMsg(back, { t: 'hello', token: host.token }); hub.onMsg(back, { t: 'join', code: room.code });
  assert.equal(room.players[0].conn, back);
  hub.leave(back, 2_000_000);
  hub.tick(1 / 30, 2_000_000 + 31_000); assert.equal(hub.rooms.size, 0);
});

test('状态消息：对局中带每口井的东西；分屏每人一口井；对战不带过关目标', () => {
  const race = hubWith(2, 'race'); race.hub.onMsg(race.conns[0], { t: 'start' }); steps(race.hub, 0.2);
  const s = last(race.conns[1], 's');
  assert.equal(s.ph, 'count'); assert.equal(s.F.length, 2); assert.equal(s.tg, 600); assert.equal(s.P.length, 2);
  assert.deepEqual(s.F[0], s.F[1], '两口井一模一样'); assert.deepEqual(s.P.map((p: any) => p.fi), [0, 1]);
  assert.ok(s.F[0].every((it: any[]) => it.length === 5 && it[1] >= 0 && it[1] < 12));
  const vs = hubWith(2, 'vs'); vs.hub.onMsg(vs.conns[0], { t: 'start' }); steps(vs.hub, 0.2);
  const v = last(vs.conns[0], 's');
  assert.equal(v.F.length, 1); assert.equal(v.tg, undefined); assert.equal(v.dp, 1);
  assert.ok(!v.F[0].some((it: any[]) => it[1] === TI.rub), '第一层没有红宝石');
});

test('商店里的消息：说话带数字又点着商品算出价，否则算聊天；点"准备好了"提前进下一关', () => {
  const { hub, conns: [host], room } = hubWith(1, 'vs');
  hub.onMsg(host, { t: 'start' }); steps(hub, 3.2);
  room.tl = 0.01; steps(hub, 0.1); assert.equal(room.ph, 'rend');
  steps(hub, 6.2); assert.equal(room.ph, 'shop');
  openShop(room, ['d', 'drink', 'book', 'clover']);          // 这条测试要用到这几件，指定上架
  hub.broadcast(room);
  const p = room.players[0]; p.money = 3000;
  const s = last(host, 's');
  assert.ok(s.pr && s.sale && s.P[0].ak && typeof s.P[0].ks === 'string' && s.P[0].km > 0, '商店状态带标价、特价、各人要价、老板的话和耐心');
  p.kAt = 0; hub.onMsg(host, { t: 'say', i: p.id, k: 'drink', text: '120 卖不卖' });
  assert.equal(p.deal.drink.tries, 1, '带数字又点着商品，算一次出价');
  p.kAt = 0; const n = p.kn; hub.onMsg(host, { t: 'say', i: p.id, k: '', text: '老板你好' });
  assert.equal(p.kn, n + 1); assert.equal(p.deal.drink.tries, 1);
  p.kAt = 0; hub.onMsg(host, { t: 'haggle', i: p.id, k: 'd', offer: room.list.d });
  assert.equal(p.tools.d, 2, '出到要价直接成交');
  hub.onMsg(host, { t: 'buy', i: p.id, k: 'book' }); assert.equal(p.next.book, 1);
  hub.onMsg(host, { t: 'ready' }); steps(hub, 0.1);
  assert.equal(room.ph, 'count'); assert.equal(room.round, 2); assert.equal(p.buff.book, 1);
});

test('掌柜表情：下井后只向已准备的座位送别，直到离开商店', () => {
  const { hub, conns: [host, guest], room } = hubWith(2);
  hub.onMsg(host, { t: 'addLocal' });
  const [p, other, local] = room.players;
  openShop(room, ['d']);
  hub.onMsg(host, { t: 'ready' });
  steps(hub, 0.1);
  assert.equal(room.ph, 'shop');
  assert.deepEqual(last(host, 's').P.map((q: { i: number; ka: string }) => [q.i, q.ka]),
    [[p.id, 'bye'], [other.id, 'idle'], [local.id, 'bye']]);
  p.money = 500;
  hub.onMsg(host, { t: 'buy', i: p.id, k: 'd' });
  steps(hub, 0.1);
  assert.equal(last(host, 's').P[0].ka, 'bye');
  hub.onMsg(guest, { t: 'ready' });
  steps(hub, 0.1);
  assert.equal(room.ph, 'count');
  assert.equal(last(host, 's').P[0].ka, undefined);
});

test('打完回房间：房主点"再来"，掉线的人被清掉，电脑留着', () => {
  const { hub, conns: [host, guest], room } = hubWith(2, 'vs');
  hub.onMsg(host, { t: 'addBot' }); hub.onMsg(host, { t: 'start' });
  hub.leave(guest);
  room.ph = 'over';
  hub.onMsg(host, { t: 'again' });
  assert.equal(room.ph, 'lobby'); assert.deepEqual(room.players.map(p => p.name), ['房主', '阿铁']);
  assert.equal(last(host, 'meta').players.length, 2);
});
