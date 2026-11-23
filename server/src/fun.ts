// 第三期（联机乐趣）的规则：分屏互相干扰、淘汰后捣乱、合作里拉不动的东西和钥匙宝箱、快捷喊话、随机事件、颁奖、对局记录。
// 数字都在 shared/balance.json 的 FUN 里。这里只管算，不碰网络和文件。
import { W, H, TYPES, TI, FUN, ev } from './core.ts';
import type { Room, Player, Field, Item, Stats } from './core.ts';

export const newStats = (): Stats => ({ shots: 0, hits: 0, miss: 0, rocks: 0, tnt: 0, assists: 0, best: 0, bags: 0, thrown: 0, emotes: 0, tools: {}, buys: {}, haggles: 0, rounds: [] });
export const isRock = (k: string) => k === 'rs' || k === 'rl';
// 合作里"必须配合"的规则只在够人数时生效（一个人打合作就是单人闯关）
export const coopOn = (room: Room) => room.mode === 'co' && room.players.length >= FUN.coop.minPlayers;

// 在一口井里找一块空地放一个新东西。ymin/ymax 是允许的深度范围；找不到返回 null
export function dropItem(room: Room, f: Field, k: string, ymin = 265, ymax = H - 60): Item | null {
  const T = TYPES[TI[k]], rnd = room.rnd;
  for (let tries = 0; tries < 60; tries++) {
    const x = T.r + 30 + Math.floor(rnd() * (W - 2 * T.r - 60)), y = ymin + Math.floor(rnd() * Math.max(1, ymax - ymin));
    if (y + T.r > H - 96 && Math.abs(x - W / 2) < 115 + T.r) continue;           // 井底正中间留给道具栏
    if (!f.items.every(o => Math.hypot(o.x - x, o.y - y) > o.r + T.r + 10)) continue;
    const it: Item = { id: room.nextItem++, t: TI[k], x, y, r: T.r, v: T.v, w: T.w, by: 0, vx: 0, x0: 0, x1: 0, hx: x, hy: y };
    f.items.push(it);
    return it;
  }
  return null;
}

/* ───────── 分屏：互相干扰 ───────── */
// 现在该往谁井里丢：还活着的对手里钱最多的那个（自己领先时就是第二名）
export function attackTarget(room: Room, by: Player): Player | null {
  let best: Player | null = null;
  for (const q of room.players) {
    if (q === by || q.out || !q.f) continue;
    if (!best || q.money > best.money) best = q;
  }
  return best;
}
// 往领先的对手井里丢一块碎石。ghost = 是淘汰的人在捣乱。丢成了返回 true
export function throwRock(room: Room, by: Player, ghost: boolean): boolean {
  if (room.mode !== 'race' || room.ph !== 'play') return false;
  const to = attackTarget(room, by);
  if (!to || to.rocksGot >= FUN.race.rockCap) return false;                       // 每人每关挨的石头有上限，不会被砸得没法玩
  const it = dropItem(room, to.f!, 'rs', 265, 520);
  if (!it) return false;
  to.rocksGot++; by.stats.thrown++;
  ev(room, { e: 'atk', by: by.id, to: to.id, f: to.f!.i, x: it.x, y: it.y, g: ghost ? 1 : 0 });
  return true;
}
// 这个人现在连续钩中几次能丢石头：领先的人要多钩一次
export function comboNeed(room: Room, p: Player): number {
  const leading = room.players.every(q => q === p || q.out || q.money <= p.money);
  return leading ? FUN.race.comboLead : FUN.race.comboBehind;
}
// 连续钩中：钩上来一件值钱的东西算一次，钩空、钩到石头、炸了炸药桶就断。
// 满了次数（领先的人要 3 次，落后的人 2 次）就丢一块石头，然后从头数
export function comboHit(room: Room, p: Player, k: string): void {
  if (room.mode !== 'race') return;
  if (isRock(k)) { p.combo = 0; return; }
  p.combo++;
  if (p.combo >= comboNeed(room, p)) { p.combo = 0; throwRock(room, p, false); }
}
// 淘汰的人捣乱：有冷却，每关有次数上限
export function ghostThrow(room: Room, p: Player): boolean {
  if (room.mode !== 'race' || room.ph !== 'play' || !p.out) return false;
  if (room.now < p.ghostAt || p.ghostN >= FUN.race.ghostCap) return false;
  if (!throwRock(room, p, true)) return false;
  p.ghostAt = room.now + FUN.race.ghostCd; p.ghostN++;
  return true;
}

/* ───────── 快捷喊话 ───────── */
export function emote(room: Room, p: Player, k: unknown, nowMs: number = Date.now()): boolean {
  const i = typeof k === 'number' ? k : -1;                 // 只认数字编号
  if (!Number.isInteger(i) || i < 0 || i >= FUN.emotes.length) return false;
  if (room.ph === 'lobby' || nowMs - p.emoAt < FUN.emoteCd * 1000) return false;   // 限频率
  p.emoAt = nowMs; p.stats.emotes++;
  ev(room, { e: 'emo', p: p.id, k: i });
  room.dirty = true;
  return true;
}

/* ───────── 随机事件 ───────── */
export const EVENT_KEYS = ['rain', 'cave', 'dark'];
// 每关开始时定这一关有没有事件、是哪个。每关最多一个，倒计时阶段就告诉大家
export function pickEvent(room: Room): void {
  const E = FUN.events;
  let k = '';
  if (room.forceEvents) k = room.forceEvents[room.round - 1] || '';
  else if (room.round >= E.firstRound && room.rnd() < E.chance) k = EVENT_KEYS[Math.floor(room.rnd() * EVENT_KEYS.length)];
  room.event = EVENT_KEYS.includes(k) ? { k, st: 0, at: E[k].at, until: 0 } : null;
  room.evHist.push(room.event ? k : '');
}
export function stepEvent(room: Room): void {
  const e = room.event; if (!e) return;
  const E = FUN.events;
  if (e.st === 0 && room.now >= e.at) {
    if (e.k === 'rain' || e.k === 'cave') {
      const list: string[] = e.k === 'rain' ? [...Array(E.rain.gs).fill('gs'), ...Array(E.rain.gm).fill('gm')] : [...Array(E.cave.rs).fill('rs'), ...Array(E.cave.rl).fill('rl')];
      // 分屏每口井掉的东西、位置尽量一样（那个位置已经有东西的才另找地方），免得有人运气好
      const spots: { k: string; x: number; y: number }[] = [];
      let first = true;
      for (const f of room.fields) {
        if (room.mode === 'race' && room.players[f.i] && room.players[f.i].out) continue;   // 淘汰的人井里不用掉
        if (first) { for (const k of list) { const it = dropItem(room, f, k); if (it) spots.push({ k, x: it.x, y: it.y }); } first = false; continue; }
        for (const s of spots) {
          const T = TYPES[TI[s.k]];
          if (f.items.every(o => Math.hypot(o.x - s.x, o.y - s.y) > o.r + T.r + 10)) f.items.push({ id: room.nextItem++, t: TI[s.k], x: s.x, y: s.y, r: T.r, v: T.v, w: T.w, by: 0, vx: 0, x0: 0, x1: 0, hx: s.x, hy: s.y });
          else dropItem(room, f, s.k);
        }
      }
      e.st = 2;
      ev(room, { e: 'event', k: e.k, on: 1 });
    } else {
      e.st = 1; e.until = room.now + E.dark.secs;
      ev(room, { e: 'event', k: e.k, on: 1 });
    }
  } else if (e.st === 1 && room.now >= e.until) {
    e.st = 2;
    ev(room, { e: 'event', k: e.k, on: 0 });
  }
}

/* ───────── 颁奖 ───────── */
// 每个奖：名字、怎么比（数越大越该拿）、至少要到多少才发、拿奖时怎么说
const AWARDS: { k: string; n: string; score: (p: Player) => number; min: number; say: (p: Player) => string }[] = [
  { k: 'sharp', n: '最准', score: p => p.stats.shots >= 5 ? p.stats.hits / p.stats.shots : 0, min: 0.01, say: p => `放钩 ${p.stats.shots} 次，钩中 ${p.stats.hits} 次` },
  { k: 'boom', n: '炸药桶爱好者', score: p => p.stats.tnt, min: 1, say: p => `钩炸了 ${p.stats.tnt} 个炸药桶` },
  { k: 'rock', n: '石头王', score: p => p.stats.rocks, min: 2, say: p => `拉上来 ${p.stats.rocks} 块石头` },
  { k: 'help', n: '好帮手', score: p => p.stats.assists, min: 1, say: p => `帮别人拉了 ${p.stats.assists} 次` },
  { k: 'prank', n: '捣蛋鬼', score: p => p.stats.thrown, min: 1, say: p => `往别人井里丢了 ${p.stats.thrown} 块石头` },
  { k: 'big', n: '一钩暴富', score: p => p.stats.best, min: 300, say: p => `最值钱的一钩 ¥${p.stats.best}` },
  { k: 'unlucky', n: '最倒霉', score: p => p.stats.miss, min: 3, say: p => `钩空了 ${p.stats.miss} 次` },
  { k: 'talk', n: '话最多', score: p => p.stats.emotes, min: 2, say: p => `喊了 ${p.stats.emotes} 次话` },
];
// 每人最多一个奖，尽量人人有：按上面的顺序，每个奖发给还没拿奖的人里数最大的那个；最后还没奖的拿"重在参与"。
// 真人先挑，剩下的奖再给电脑（电脑只在瞄准了才出手，不然"最准"永远是它的）
export function awardsFor(room: Room): { id: number; k: string; n: string; say: string }[] {
  const out: { id: number; k: string; n: string; say: string }[] = [], got = new Set<Player>(), given = new Set<string>();
  for (const bots of [false, true]) for (const a of AWARDS) {
    if (given.has(a.k)) continue;
    let best: Player | null = null, bs = 0;
    for (const p of room.players) { if (got.has(p) || p.bot !== bots) continue; const s = a.score(p); if (s >= a.min && s > bs) { bs = s; best = p; } }
    if (best) { got.add(best); given.add(a.k); out.push({ id: best.id, k: a.k, n: a.n, say: a.say(best) }); }
  }
  for (const p of room.players) if (!got.has(p)) out.push({ id: p.id, k: 'join', n: '重在参与', say: `放钩 ${p.stats.shots} 次` });
  return out;
}

/* ───────── 对局记录 ───────── */
// 一场打完后存下来的数据，用来以后调数值。不记玩家对掌柜说的原话，只记出了几次价
export function matchLog(room: Room, endedAt: number): Record<string, unknown> {
  const res = room.res as { rows?: { id: number; m: number; tt: number; ps: number; out: number }[]; awards?: { id: number; n: string }[]; co?: unknown } | null;
  return {
    code: room.code, mode: room.mode, roundsPlayed: room.round, roundsSet: room.mode === 'vs' ? room.rounds : null,
    startedAt: new Date(room.startedAt).toISOString(), endedAt: new Date(endedAt).toISOString(), seconds: Math.round((endedAt - room.startedAt) / 1000),
    events: room.evHist.map((k, i) => ({ round: i + 1, event: k || null })),
    teamMoney: room.mode === 'co' ? room.money : null, co: res?.co ?? null,
    players: room.players.map(p => {
      const row = res?.rows?.find(r => r.id === p.id), s = p.stats;
      return {
        seat: p.id, name: p.name, bot: p.bot, money: row?.m ?? p.money, earnedTotal: p.total, passed: p.passed, out: p.out,
        shots: s.shots, hits: s.hits, hitRate: s.shots ? Math.round(s.hits / s.shots * 1000) / 1000 : null, misses: s.miss,
        incomeByRound: s.rounds, rocks: s.rocks, tntBlown: s.tnt, assists: s.assists, bestHaul: s.best, bags: s.bags,
        rocksThrown: s.thrown, toolsUsed: s.tools, bought: s.buys, haggles: s.haggles, emotes: s.emotes,
        award: res?.awards?.find(a => a.id === p.id)?.n ?? null,
      };
    }),
  };
}
