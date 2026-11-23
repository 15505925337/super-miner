// 测试用的小工具：固定种子的随机数、假连接、摆好一局的房间。
import { TYPES, TI, COUNT_T, MINL, SW } from '../src/core.ts';
import type { Room, Player, Item, Conn, Mode } from '../src/core.ts';
import { newRoom, newPlayer, startGame, tickRoom } from '../src/game.ts';

export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
export interface FakeConn extends Conn { got: any[]; closed: boolean }
export function fakeConn(token: string): FakeConn {
  return { token, room: null, got: [], closed: false, send(o) { this.got.push(JSON.parse(JSON.stringify(o))); }, close() { this.closed = true; } };
}
export const DT = 1 / 30;
// 往前跑若干秒，返回期间产生的所有事件
export function run(room: Room, secs: number, until?: () => boolean): any[] {
  const evs: any[] = [];
  for (let t = 0; t < secs; t += DT) {
    tickRoom(room, DT);
    evs.push(...room.ev); room.ev = [];
    if (until && until()) break;
  }
  return evs;
}
// 开一局并跳过倒计时，停在"正在挖"的状态；井里先清空，由测试自己摆东西
export function playing(mode: Mode, humans: number, seed = 1, bots = 0): { room: Room; ps: Player[]; conns: FakeConn[] } {
  const room = newRoom('1000', rng(seed)); room.mode = mode;
  const conns: FakeConn[] = [];
  for (let i = 0; i < humans; i++) { const c = fakeConn('token-' + i + '-xxxx'); conns.push(c); newPlayer(room, c, 'P' + (i + 1)); c.room = room; room.conns.add(c); }
  for (let i = 0; i < bots; i++) newPlayer(room, null, 'B' + (i + 1), true);
  startGame(room);
  run(room, COUNT_T + 0.2, () => room.ph === 'play');
  for (const f of room.fields) f.items = [];
  for (const p of room.players) { p.ang = 0; p.phase = 0; p.st = SW; p.len = MINL; }
  return { room, ps: room.players, conns };
}
export function put(room: Room, fi: number, k: string, x: number, y: number, extra: Partial<Item> = {}): Item {
  const T = TYPES[TI[k]];
  const it: Item = { id: room.nextItem++, t: TI[k], x, y, r: T.r, v: T.v, w: T.w, by: 0, vx: 0, x0: 0, x1: 0, ...extra };
  room.fields[fi].items.push(it);
  return it;
}
// 让某个玩家的钩子对准一个点
export function aim(p: Player, x: number, y: number, y0: number): void {
  p.ang = Math.atan2(x - p.x, y - y0); p.phase = Math.asin(Math.max(-1, Math.min(1, p.ang / 1.26)));
}
