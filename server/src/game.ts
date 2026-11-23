// 对局规则：出矿、钩子、拉货、合拉、炸药桶、宝袋、道具、过关和淘汰、电脑玩家。
// 规则和数值照原型 deep-mine.js，这里只管算，不碰网络。
import {
  W, H, Y0, MINL, AMP, SWING, EXT_V, RET_V, HAUL_V, HOOK_R, BOOM_R, ROUND_T, COUNT_T, REND_T, STRONG, HELP,
  SW, EXT, HAUL, RET, AST, TYPES, TI, SHOP, TOOL_ORDER, RULES, BAG, FUN,
  wallet, strong, ev, depthOf, tierOf, goalOf,
} from './core.ts';
import type { Room, Player, Field, Item, Conn, Mode } from './core.ts';
import { openShop } from './shop.ts';
import { newStats, isRock, coopOn, comboHit, comboNeed, ghostThrow, pickEvent, stepEvent, awardsFor } from './fun.ts';

export function newRoom(code: string, rnd: () => number = Math.random): Room {
  return {
    code, mode: 'vs', rounds: 3, host: null, conns: new Set(), players: [], nextPid: 1, nextItem: 1,
    ph: 'lobby', round: 0, tl: 0, now: 0, fields: [], ev: [], money: 0, earned: 0, target: 0,
    res: null, final: false, dirty: true, acc: 0, emptyAt: 0, shopId: 0, list: {}, floor: {}, sale: '', rnd,
    event: null, keyBy: 0, evHist: [], forceEvents: null, startedAt: 0, logged: false,
  };
}
export function layout(room: Room): void {
  const n = room.players.length;
  room.players.forEach((p, i) => { p.x = Math.round(W * (i + 1) / (n + 1)); });
}
export function newPlayer(room: Room, conn: Conn | null, name: string, bot = false): Player {
  const used = new Set(room.players.map(p => p.c)); let c = 0; while (used.has(c)) c++;
  const p: Player = {
    id: room.nextPid++, name, c, bot, conn, token: conn ? conn.token : null,
    money: 0, earned: 0, total: 0, x: 0, phase: 0, ang: 0, len: MINL, st: SW, item: 0, frozen: 0, strongR: false,
    tools: { d: 0, s: 0, f: 0, h: 0 }, buff: {}, next: {}, ready: false, botCd: 0, botErr: 0, out: false, passed: 0, f: null,
    mood: 0, moodUp: 0, flat: 0, kn: 0, kAt: 0, ksay: '', ka: 'idle', deal: {},
    combo: 0, rocksGot: 0, hold: 0, ghostAt: 0, ghostN: 0, emoAt: 0, stats: newStats(),
  };
  room.players.push(p); layout(room);
  return p;
}

/* ───────── 对局流程 ───────── */
export function startGame(room: Room, nowMs: number = Date.now()): void {
  room.round = 0; room.money = 0; room.final = false;
  room.evHist = []; room.startedAt = nowMs; room.logged = false;
  for (const p of room.players) {
    p.money = 0; p.total = 0; p.buff = {}; p.next = {}; p.out = false; p.passed = 0;
    p.tools = { ...RULES.startTools };                       // 开局每人送 1 个炸药
    p.stats = newStats();
  }
  nextRound(room);
}
export function nextRound(room: Room): void {
  room.round++; room.earned = 0; room.now = 0; room.keyBy = 0;
  pickEvent(room);                                           // 这一关有没有随机事件，倒计时的时候就告诉大家
  const race = room.mode === 'race', n = room.players.length;
  // 一口井就是一个 field。分屏按单人规模出一张图，每人拿一份一模一样的；其它玩法所有人共用一张
  const proto = genItems(room, race ? 1 : n);
  room.fields = race
    ? room.players.map((p, i) => ({ i, items: p.out ? [] : proto.map(it => ({ ...it })), booms: [] }))
    : [{ i: 0, items: proto, booms: [] }];
  room.players.forEach((p, i) => {
    p.f = room.fields[race ? i : 0]; p.x = race ? W / 2 : Math.round(W * (i + 1) / (n + 1));
    p.earned = 0; p.buff = p.next; p.next = {}; p.strongR = false; p.ready = false;
    p.phase = race ? 0.6 : i * 1.3 + room.rnd();             // 分屏大家起摆角度也一样
    p.ang = AMP * Math.sin(p.phase); p.len = MINL; p.st = SW; p.item = 0; p.frozen = 0;
    p.botCd = 0.4 + room.rnd();
    p.combo = 0; p.rocksGot = 0; p.hold = 0; p.ghostAt = FUN.race.ghostFirst; p.ghostN = 0;
  });
  room.target = race ? goalOf(room.round, 1) : room.mode === 'co' ? goalOf(room.round, n) : 0;
  room.ph = 'count'; room.tl = COUNT_T; room.dirty = true;
}
// 每种东西出几个：基础数量随深度涨，再按所在的层加料
export function itemCounts(L: number, n: number, rnd: () => number): Record<string, number> {
  const tier = tierOf(L), ri = (a: number, b: number) => a + Math.floor(rnd() * (b - a + 1));
  return {
    gx: tier >= 3 ? 1 + (n >= 3 ? 1 : 0) : 0,
    gl: Math.min(7, 1 + (n >> 1) + (L >> 1)), rl: 1 + (n >> 1) + Math.floor(L / 3) + (tier === 1 ? 1 : 0),
    gm: 1 + n + Math.min(L, 3), fos: 1 + Math.floor(n / 3) + (L > 3 ? 1 : 0) + (tier === 1 ? 1 : 0),
    bag: 2 + (n >> 1), tnt: Math.min(5, 1 + (L >> 1) + (tier === 3 ? 1 : 0)), gs: 3 + n + ri(0, 1), rs: 2 + n + (tier === 1 ? 1 : 0),
    gem: Math.min(6, (L >= 2 ? 1 + (n >> 1) : ri(0, 1)) + Math.floor(L / 4) + (tier === 2 ? 2 : 0)),
    rub: tier >= 2 ? 1 + (n >> 1) : 0,
    bug: (L >= 2 ? 1 + (n >= 3 ? 1 : 0) : 0) + (tier === 2 ? 1 : 0),
  };
}
export const YMIN: Record<string, number> = { gx: 470, gl: 430, gem: 400, rub: 450, chest: 430 };    // 值钱的埋得深
export function genItems(room: Room, n: number): Item[] {
  const L = depthOf(room), rnd = room.rnd;
  const ri = (a: number, b: number) => a + Math.floor(rnd() * (b - a + 1));
  const cnt = itemCounts(L, n, rnd);
  if (coopOn(room)) {                                        // 合作（两人以上）：每关有一块一个人拉不动的巨型金块、一把钥匙和一个宝箱；大金块少一块
    cnt.gx = Math.max(cnt.gx, FUN.coop.giant); cnt.gl = Math.max(0, cnt.gl - FUN.coop.lessBigGold); cnt.chest = 1; cnt.key = 1;
  }
  const items: Item[] = [];
  for (const k of ['gx', 'chest', 'gl', 'rl', 'gm', 'fos', 'bag', 'tnt', 'gs', 'rs', 'gem', 'rub', 'bug', 'key']) {   // 先放大的
    const t = TI[k], T = TYPES[t], ymin = YMIN[k] || 265;
    for (let i = 0; i < (cnt[k] || 0); i++) {
      for (let tries = 0; tries < 120; tries++) {
        const x = ri(T.r + 30, W - T.r - 30), y = ri(ymin, H - T.r - 22);
        // 井底正中间留给屏幕上的道具按钮，不放东西（会跑的晶甲虫整行都不放）
        if (y + T.r > H - 96 && (k === 'bug' || Math.abs(x - W / 2) < 115 + T.r)) continue;
        if (!items.every(o => Math.hypot(o.x - x, o.y - y) > o.r + T.r + 14)) continue;
        const it: Item = { id: room.nextItem++, t, x, y, r: T.r, v: T.v, w: T.w, by: 0, vx: 0, x0: 0, x1: 0, hx: x, hy: y };
        if (k === 'bag') { it.w = BAG.weightMin + rnd() * BAG.weightSpan; it.roll = rnd(); it.roll2 = rnd(); }   // 开出什么先定好，分屏每人一样
        if (k === 'bug') { it.vx = (rnd() < 0.5 ? -1 : 1) * ri(55, 95); it.x0 = Math.max(40, x - 170); it.x1 = Math.min(W - 40, x + 170); }
        items.push(it); break;
      }
    }
  }
  return items;
}
export function endRound(room: Room): void {
  for (const p of room.players) { p.st = SW; p.len = MINL; p.item = 0; p.frozen = 0; p.hold = 0; p.stats.rounds.push(p.earned); }
  for (const f of room.fields) for (const it of f.items) it.by = 0;
  if (room.event) room.event.st = 2;
  const mode = room.mode, failedNow = new Set<Player>();
  let co: { target: number; have: number; pass: boolean } | null = null;
  if (mode === 'co') { const pass = room.money >= room.target; co = { target: room.target, have: room.money, pass }; room.final = !pass; }
  else if (mode === 'vs') room.final = room.round >= room.rounds;
  else {                                                     // 分屏：没赚够目标的淘汰，剩一个人（单人则是自己失败）就结束
    for (const p of room.players) {
      if (p.out) continue;
      if (p.money >= room.target) p.passed = room.round; else { p.out = true; failedNow.add(p); }
    }
    const left = room.players.filter(p => !p.out).length;
    room.final = room.players.length > 1 ? left <= 1 : left === 0;
  }
  room.res = {
    round: room.round, final: room.final, mode, target: room.target, co,
    rows: room.players.map(p => ({ id: p.id, e: p.earned, m: p.money, tt: p.total, ps: p.passed, out: p.out ? 1 : 0, now: failedNow.has(p) ? 1 : 0 })),
  };
  if (room.final) (room.res as Record<string, unknown>).awards = awardsFor(room);       // 整场打完：颁奖
  room.ph = 'rend'; room.tl = REND_T; room.dirty = true;
}
export function toLobby(room: Room): void {
  room.players = room.players.filter(p => p.bot || p.conn);
  layout(room); room.ph = 'lobby'; room.round = 0; room.fields = []; room.res = null; room.dirty = true;
}

/* ───────── 钩子与物理 ───────── */
export function syncPhase(p: Player): void {                 // 让摆动相位对上当前角度，收钩后接着摆不跳
  const s = Math.asin(Math.max(-1, Math.min(1, p.ang / AMP)));
  p.phase = Math.cos(p.phase) >= 0 ? s : Math.PI - s;
}
export function fire(room: Room, p: Player, a?: unknown): void {
  if (room.ph === 'play' && p.out) { ghostThrow(room, p); return; }      // 分屏里淘汰的人：放钩键变成往别人井里丢石头
  if (room.ph !== 'play' || p.out || p.st !== SW || p.frozen > room.now) return;
  // 客户端画面比服务端慢几十毫秒，以玩家按下时看到的角度为准（差太多就不认）
  if (typeof a === 'number' && Math.abs(a - p.ang) < RULES.fireAngleTolerance && Math.abs(a) <= AMP + 0.01) { p.ang = a; syncPhase(p); }
  p.st = EXT; p.stats.shots++; ev(room, { e: 'fire', p: p.id });
}
const removeItem = (f: Field, it: Item) => { f.items = f.items.filter(o => o !== it); };
export function addMoney(room: Room, p: Player, v: number): void { wallet(room, p).money += v; p.earned += v; p.total += v; room.earned += v; }

export function explode(room: Room, f: Field, it: Item, playerId?: number): void {
  removeItem(f, it);
  ev(room, { e: 'boom', f: f.i, x: it.x, y: it.y, r: BOOM_R,
    ...(playerId === undefined ? {} : { p: playerId, src: 'tnt' }) });
  for (const o of f.items.slice()) {
    if (Math.hypot(o.x - it.x, o.y - it.y) > BOOM_R + o.r * 0.5) continue;
    if (o.t === TI.tnt) { if (!f.booms.some(b => b.id === o.id)) f.booms.push({ id: o.id, at: room.now + RULES.chainBoomDelay }); }   // 连环炸，稍等一下再响
    else removeItem(f, o);                                   // 正被拉着的货也会被炸没，钩子下一帧自己空收
  }
}
export function openBag(room: Room, p: Player, it: Item): { v: number; s?: string } {
  const r = it.roll ?? 0, r2 = it.roll2 ?? 0, tools = TOOL_ORDER[room.mode];
  const rnd = (a: number, b: number) => Math.round((a + r2 * (b - a)) / 10) * 10;
  const giveTool = () => { const k = tools[Math.floor(r2 * tools.length)]; p.tools[k] = Math.min(RULES.toolMax, p.tools[k] + 1); return SHOP[k].n + ' ×1'; };
  if (p.buff.clover) return r < BAG.clover.moneyChance ? { v: rnd(BAG.clover.moneyMin, BAG.clover.moneyMax) } : { v: BAG.clover.elseMoney, s: giveTool() };
  if (r < BAG.moneyBelow) return { v: rnd(BAG.moneyMin, BAG.moneyMax) };
  if (r < BAG.toolBelow) return { v: 0, s: giveTool() };
  if (r < BAG.strongBelow) { p.strongR = true; return { v: 0, s: '大力！' }; }
  return { v: BAG.emptyMoney, s: '空袋子' };
}
export function collect(room: Room, p: Player, it: Item): void {
  const k = TYPES[it.t].k;
  const helpers = room.players.filter(q => q.st === AST && q.item === it.id && q.f === p.f);
  if (k === 'chest' && coopOn(room) && !(room.keyBy && (room.keyBy !== p.id || helpers.length))) {
    // 宝箱打不开（还没人钩到钥匙，或者拿钥匙的人自己来拉）：掉回原来的地方
    ev(room, { e: 'lock', p: p.id, f: p.f!.i, x: p.x, y: Y0 + 60, s: room.keyBy ? '得换个人来拉' : '锁着，先钩钥匙' });
    it.by = 0; it.x = it.hx ?? it.x; it.y = it.hy ?? it.y;
    for (const q of helpers) { q.st = RET; q.item = 0; }
    p.st = SW; p.len = MINL; p.item = 0; p.botCd = 0.7 + room.rnd() * 1.1;
    return;
  }
  removeItem(p.f!, it);
  let v = it.v, label = '';
  if (k === 'chest') { label = '开箱！'; room.keyBy = 0; }
  if (k === 'key' && coopOn(room)) { label = '钥匙'; room.keyBy = p.id; }
  if (k === 'bag') { const b = openBag(room, p, it); v = b.v; label = b.s || '宝袋'; }
  if ((k === 'gem' || k === 'rub' || k === 'bug') && p.buff.polish) v = Math.round(v * RULES.polishMul);
  if ((k === 'rs' || k === 'rl') && p.buff.book) v *= RULES.bookMul;
  for (const q of helpers) { q.st = RET; q.item = 0; q.stats.assists++; }
  if (helpers.length && room.mode === 'vs') {                // 对战合拉：主拉 70%，帮拉的分 30%
    const share = Math.round(v * RULES.vsAssistShare / helpers.length);
    for (const q of helpers) { addMoney(room, q, share); ev(room, { e: 'get', p: q.id, v: share, s: '帮拉', k }); }
    v = Math.round(v * (1 - RULES.vsAssistShare));
  } else if (helpers.length) { v = Math.round(v * RULES.coAssistBonus); label = label || '合拉'; }   // 合作合拉：多拿 10%
  addMoney(room, p, v);
  if (isRock(k)) p.stats.rocks++;
  if (k === 'bag') p.stats.bags++;
  p.stats.best = Math.max(p.stats.best, v);
  ev(room, { e: 'get', p: p.id, v, s: label, k });
  comboHit(room, p, k);
  p.st = SW; p.len = MINL; p.item = 0; p.botCd = 0.7 + room.rnd() * 1.1;
}
export function useTool(room: Room, p: Player, k: string): void {
  if (room.ph !== 'play' || p.frozen > room.now || !(p.tools[k] > 0)) return;
  if (!TOOL_ORDER[room.mode].includes(k)) return;
  if (k === 'd') {                                           // 炸药：炸掉正在拉的东西，马上收钩
    if (p.st !== HAUL) return;
    const it = p.f!.items.find(o => o.id === p.item); if (!it) return;
    removeItem(p.f!, it); p.st = RET; p.item = 0;
    ev(room, { e: 'boom', f: p.f!.i, x: it.x, y: it.y, r: RULES.dynamiteBoomR, p: p.id, src: 'd' });
  } else if (k === 's') {                                    // 剪刀：谁在拉最值钱的货就剪谁，货掉在原地
    let target: Player | null = null, best = -1;
    for (const q of room.players) {
      if (q === p || q.out || q.st !== HAUL) continue;
      const it = q.f!.items.find(o => o.id === q.item);
      if (it && it.v > best) { best = it.v; target = q; }
    }
    if (!target) return;                                     // 没人在拉货，不消耗
    const it = target.f!.items.find(o => o.id === target!.item)!;
    it.by = 0; target.st = RET; target.item = 0;
    ev(room, { e: 'cut', f: target.f!.i, x: it.x, y: it.y - it.r - 14, by: p.name });
  } else if (k === 'f') {                                    // 冰冻：所有对手的钩子冻住
    for (const q of room.players) if (q !== p && !q.out) q.frozen = room.now + RULES.freezeSecs;
    ev(room, { e: 'frz', by: p.name });
  } else if (k === 'h') {                                    // 沙漏：本关加时间
    room.tl += RULES.hourglassSecs;
    ev(room, { e: 'time', by: p.name });
  }
  p.tools[k]--;
  p.stats.tools[k] = (p.stats.tools[k] || 0) + 1;
}
export function stepPlayer(room: Room, p: Player, dt: number): void {
  if (p.out || p.frozen > room.now) return;
  const f = p.f!;
  if (p.st === SW) { p.phase += SWING * dt; p.ang = AMP * Math.sin(p.phase); return; }
  if (p.st === EXT) {
    for (let s = 0; s < 2; s++) {                            // 一帧走两小步，免得钩尖穿过小东西
      p.len += EXT_V * dt / 2;
      const tx = p.x + Math.sin(p.ang) * p.len, ty = Y0 + Math.cos(p.ang) * p.len;
      if (tx < 6 || tx > W - 6 || ty > H - 6) { p.st = RET; p.stats.miss++; p.combo = 0; ev(room, { e: 'miss', p: p.id }); return; }
      const it = f.items.find(o => Math.hypot(o.x - tx, o.y - ty) < o.r + HOOK_R);
      if (!it) continue;
      p.stats.hits++;
      if (it.t === TI.tnt) { explode(room, f, it, p.id); p.st = RET; p.stats.tnt++; p.combo = 0; return; }
      const dx = it.x - p.x, dy = it.y - Y0;
      p.ang = Math.atan2(dx, dy); p.len = Math.max(MINL, Math.hypot(dx, dy) - it.r * RULES.itemGrabDepth); p.item = it.id;
      if (it.by) { p.st = AST; ev(room, { e: 'ast', f: f.i, x: it.x, y: it.y }); }      // 钩到别人正在拉的货 → 合拉
      else { it.by = p.id; p.st = HAUL; syncPhase(p); ev(room, { e: 'grab', p: p.id, f: f.i, x: it.x, y: it.y, k: TYPES[it.t].k }); }
      return;
    }
    return;
  }
  if (p.st === HAUL) {
    const it = f.items.find(o => o.id === p.item);
    if (!it) { p.st = RET; p.item = 0; p.hold = 0; return; }
    let helpers = 0;
    for (const q of room.players) if (q.st === AST && q.f === f && q.item === it.id && !(q.frozen > room.now)) helpers++;
    if (coopOn(room) && it.t === TI.gx && !helpers) {       // 合作里的巨型金块：一个人拉不动，吊着等人来帮；等太久就松手
      if (!p.hold) ev(room, { e: 'heavy', p: p.id, f: f.i, x: it.x, y: it.y });
      p.hold += dt;
      if (p.hold >= FUN.coop.giantWait) { it.by = 0; p.st = RET; p.item = 0; p.hold = 0; }
      return;
    }
    p.hold = 0;
    p.len -= HAUL_V / it.w * (strong(p) ? STRONG : 1) * (1 + HELP * helpers) * dt;
    const d = Math.max(MINL, p.len) + it.r * RULES.itemGrabDepth;
    it.x = p.x + Math.sin(p.ang) * d; it.y = Y0 + Math.cos(p.ang) * d;
    if (p.len <= MINL) collect(room, p, it);
    return;
  }
  if (p.st === RET) {
    p.len -= RET_V * dt;
    p.ang += (AMP * Math.sin(p.phase) - p.ang) * Math.min(1, dt * 8);
    if (p.len <= MINL) { p.len = MINL; p.st = SW; p.botCd = 0.7 + room.rnd() * 1.1; }
    return;
  }
  if (p.st === AST) {
    const it = f.items.find(o => o.id === p.item);
    if (!it || !room.players.some(q => q.st === HAUL && q.f === f && q.item === p.item)) { p.st = RET; p.item = 0; return; }
    const dx = it.x - p.x, dy = it.y - Y0;
    p.ang = Math.atan2(dx, dy); p.len = Math.max(MINL, Math.hypot(dx, dy) - it.r * RULES.itemGrabDepth);
  }
}
export function botThink(room: Room, p: Player, dt: number): void {
  if (p.out) {                                               // 淘汰了的电脑也会捣乱
    if (room.mode === 'race' && room.ph === 'play' && room.rnd() < 0.03) ghostThrow(room, p);
    return;
  }
  const items = p.f!.items, coop = coopOn(room);
  // 合作：有人吊着巨型金块拉不动，就去帮他
  const needHelp = (it: Item) => coop && it.t === TI.gx && !!it.by && !room.players.some(q => q.st === AST && q.item === it.id);
  if (p.st === HAUL && p.tools.d > 0 && room.tl > 5) {
    const it = items.find(o => o.id === p.item);
    if (it && it.t === TI.rl) useTool(room, p, 'd');
    return;
  }
  if (p.st !== SW || p.frozen > room.now) return;
  p.botCd -= dt; if (p.botCd > 0) return;
  // 沿当前角度射一条线，看钩子最先碰到什么。电脑"以为"的角度带一点偏差，每次出手后重新随机，所以小东西经常钩空
  const seen = p.ang + (p.botErr || 0), sx = Math.sin(seen), cx = Math.cos(seen);
  let first: Item | null = null, ft = 1e9, aimed = false, avoid = false;
  for (const it of items) {
    if (it.by && !needHelp(it)) continue;
    // 这两样电脑不该去钩，但它们会挡路：照样算进"钩子最先碰到什么"，碰到的是它们就不出手
    const no = coop && ((!it.by && it.t === TI.gx)                                      // 巨型金块电脑不先动手，只帮忙
      || (it.t === TI.chest && !(room.keyBy && room.keyBy !== p.id)));                   // 宝箱等别人拿到钥匙再拉
    const dx = it.x - p.x, dy = it.y - Y0, along = dx * sx + dy * cx, perp = Math.abs(dx * cx - dy * sx), rr = it.r + HOOK_R;
    if (along < MINL || perp >= rr) continue;
    const t = along - Math.sqrt(rr * rr - perp * perp);
    if (t < ft) { ft = t; first = it; aimed = perp < it.r * 0.6; avoid = no; }
  }
  if (!first || !aimed || avoid) return;
  const k = TYPES[first.t].k;
  if (k === 'tnt') return;
  const junk = k === 'rs' || k === 'rl';
  if (junk && items.some(o => !o.by && o.t !== TI.tnt && o.t !== TI.rs && o.t !== TI.rl)) return;
  const haulTime = ft / (HAUL_V / first.w * (strong(p) ? STRONG : 1));
  if (first.by) { fire(room, p); p.botErr = (room.rnd() - 0.5) * 0.16; return; }   // 去帮忙：对准了就出手
  if (haulTime > room.tl + 0.5) return;                      // 来不及拉上来就不出手
  if (room.rnd() < 0.15) { fire(room, p); p.botErr = (room.rnd() - 0.5) * 0.16; }
}
export function sim(room: Room, dt: number): void {
  for (const f of room.fields) {
    for (let i = f.booms.length - 1; i >= 0; i--) {
      if (f.booms[i].at > room.now) continue;
      const b = f.booms.splice(i, 1)[0], it = f.items.find(o => o.id === b.id);
      if (it) explode(room, f, it);
    }
    for (const it of f.items) {
      if (!it.vx || it.by) continue;
      it.x += it.vx * dt;
      if (it.x < it.x0 || it.x > it.x1) { it.vx = -it.vx; it.x = Math.max(it.x0, Math.min(it.x1, it.x)); }
    }
  }
  for (const p of room.players) { if (p.bot) botThink(room, p, dt); stepPlayer(room, p, dt); }
}
// 房间往前走一小步（服务端每 33 毫秒调一次）
export function tickRoom(room: Room, dt: number): void {
  room.acc++;
  if (room.ph === 'count') {
    room.tl -= dt;
    for (const p of room.players) { p.phase += SWING * dt; p.ang = AMP * Math.sin(p.phase); }
    if (room.tl <= 0) { room.ph = 'play'; room.tl = ROUND_T; ev(room, { e: 'go' }); }
  } else if (room.ph === 'play') {
    room.now += dt; room.tl -= dt;
    stepEvent(room);
    sim(room, dt);
    const cleared = room.fields.every(f => f.items.every(it => it.t === TI.tnt)) && room.players.every(p => p.st === SW);
    if (room.tl <= 0 || cleared) endRound(room);
  } else if (room.ph === 'rend') {
    room.tl -= dt;
    if (room.tl <= 0) { if (room.final) { room.ph = 'over'; room.dirty = true; } else openShop(room); }
  } else if (room.ph === 'shop') {
    room.tl -= dt;
    if (room.tl <= 0 || room.players.every(p => p.ready || p.bot || !p.conn || p.out)) nextRound(room);
  }
}

// 发给客户端的对局状态（每帧一份）。字段名照原型，尽量短
export function snapshot(room: Room): Record<string, any> {
  const co = room.mode === 'co', live = room.ph === 'count' || room.ph === 'play';
  const P = room.players.map(p => {
    const q: Record<string, any> = {
      i: p.id, a: +p.ang.toFixed(3), l: +p.len.toFixed(1), s: p.st, it: p.item, m: co ? room.money : p.money, e: p.earned,
      fz: p.frozen > room.now ? 1 : 0, sg: strong(p) ? 1 : 0, tl: p.tools, nx: p.next, r: p.ready ? 1 : 0,
      x: p.x, fi: p.f ? p.f.i : 0, out: p.out ? 1 : 0, ps: p.passed || 0,
    };
    if (room.mode === 'race') {                              // 分屏：连续钩中几次 / 还差几次丢石头；淘汰的人还要等几秒、还能丢几块
      q.cb = p.combo; q.cn = comboNeed(room, p);
      if (p.out) { q.gc = Math.max(0, +(p.ghostAt - room.now).toFixed(1)); q.gn = FUN.race.ghostCap - p.ghostN; }
    }
    if (p.hold > 0) q.hv = +(FUN.coop.giantWait - p.hold).toFixed(1);   // 吊着巨型金块，再过几秒就松手
    if (room.ph === 'shop') {                                // 商店：每个人各自谈到的价、老板对他说的话和耐心
      const ak: Record<string, number> = {};
      for (const k in p.deal) ak[k] = p.deal[k].ask;
      q.ak = ak; q.ks = p.ksay; q.kn = p.kn; q.km = p.mood; q.ka = p.ready ? 'bye' : p.ka;
    }
    return q;
  });
  const o: Record<string, any> = { t: 's', ph: room.ph, tl: +room.tl.toFixed(2), rd: room.round, dp: room.round ? depthOf(room) : 1, E: room.ev, P };
  // F：每口井里的东西。同屏玩法只有一口，分屏每人一口
  if (live) o.F = room.fields.map(f => f.items.map(it => [it.id, it.t, Math.round(it.x * 10) / 10, Math.round(it.y * 10) / 10, it.by]));
  if (room.mode !== 'vs') o.tg = room.target;
  if (co) { o.te = room.money; o.ky = room.keyBy; }
  if (live && room.event) {                                  // 这一关的事件：[哪个, 0 还没来 / 1 正在发生 / 2 过去了, 还有几秒]
    const e = room.event;
    o.ev = [e.k, e.st, e.st === 0 ? +(e.at - room.now).toFixed(1) : e.st === 1 ? +(e.until - room.now).toFixed(1) : 0];
  }
  if (room.ph === 'shop') {
    o.pr = room.list; o.sale = room.sale;
    if (room.mode !== 'vs') o.ng = goalOf(room.round + 1, room.mode === 'race' ? 1 : room.players.length);
  }
  if (room.ph === 'rend' || room.ph === 'over') o.res = room.res;
  return o;
}
export type { Mode };
