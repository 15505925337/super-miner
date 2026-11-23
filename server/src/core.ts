// 常量、类型和小工具。数值全部来自 shared/balance.json（和 Godot 客户端共用一份）。
import { readFileSync } from 'node:fs';

export const B = JSON.parse(readFileSync(new URL('../../shared/balance.json', import.meta.url), 'utf8'));

export const W: number = B.W, H: number = B.H, Y0: number = B.Y0;
export const MINL: number = B.MINL, AMP: number = B.AMP, SWING: number = B.SWING;
export const EXT_V: number = B.EXT_V, RET_V: number = B.RET_V, HAUL_V: number = B.HAUL_V;
export const HOOK_R: number = B.HOOK_R, BOOM_R: number = B.BOOM_R;
// 调试用：环境变量 DM_ROUND_T 可以临时缩短每关的秒数（联调时不用每关等 60 秒）。正式运行不要设
export const ROUND_T: number = Number(process.env.DM_ROUND_T) || B.ROUND_T;
export const COUNT_T: number = B.COUNT_T, REND_T: number = Number(process.env.DM_REND_T) || B.REND_T, SHOP_T: number = B.SHOP_T, MAXP: number = B.MAXP;
export const STRONG: number = B.STRONG, HELP: number = B.HELP;
export const RULES = B.RULES, BAG = B.BAG, KEEPER = B.KEEPER, FUN = B.FUN;

// 钩子状态：摆动 / 放出 / 拉货 / 空收 / 帮别人拉
export const SW = 0, EXT = 1, HAUL = 2, RET = 3, AST = 4;

export interface ItemType { k: string; n: string; r: number; v: number; w: number }
export interface ShopDef { n: string; price: number; tool?: number; only?: string[]; d: string }
export type Mode = 'co' | 'vs' | 'race' | 'solo';
export type Phase = 'lobby' | 'count' | 'play' | 'rend' | 'shop' | 'over';

export const TYPES: ItemType[] = B.TYPES;
export const TI: Record<string, number> = {};
TYPES.forEach((t, i) => { TI[t.k] = i; });
export const SHOP: Record<string, ShopDef> = B.SHOP;
export const MODES: Mode[] = B.MODES;
export const TOOL_ORDER: Record<Mode, string[]> = B.TOOL_ORDER;
export const LAYERS: string[] = B.LAYERS;
export const BOT_NAMES: string[] = B.BOT_NAMES;

export interface Item {
  id: number; t: number; x: number; y: number; r: number; v: number; w: number;
  by: number;                       // 正在拉它的玩家 id，0 表示没人拉
  vx: number; x0: number; x1: number;   // 会跑的晶甲虫：速度和来回的范围
  roll?: number; roll2?: number;    // 宝袋开出什么，生成时就定好（分屏每人一样）
  hx?: number; hy?: number;         // 原来的位置（宝箱没钥匙打不开时掉回这里）
}
export interface Field { i: number; items: Item[]; booms: { id: number; at: number }[] }
export interface Deal { ask: number; tries: number }
// 每个人这一场的数据：颁奖和对局记录用
export interface Stats {
  shots: number; hits: number; miss: number; rocks: number; tnt: number; assists: number; best: number; bags: number;
  thrown: number; emotes: number; tools: Record<string, number>; buys: Record<string, number>; haggles: number; rounds: number[];
}
// 这一关的随机事件。st：0 还没发生，1 正在发生（只有黑灯会持续），2 已经结束
export interface RoundEvent { k: string; st: number; at: number; until: number }

// 一条连接。真连接在 ws.ts 里，测试里用假的
export interface Conn { token: string; room: Room | null; send(o: unknown): void; close(): void }

export interface Player {
  id: number; name: string; c: number; bot: boolean; conn: Conn | null; token: string | null;
  money: number; earned: number; total: number;
  x: number; phase: number; ang: number; len: number; st: number; item: number; frozen: number; strongR: boolean;
  tools: Record<string, number>; buff: Record<string, number>; next: Record<string, number>;
  ready: boolean; botCd: number; botErr: number; out: boolean; passed: number; f: Field | null;
  // 商店里：老板对这个人的耐心、说的话、谈到的价
  mood: number; moodUp: number; flat: number; kn: number; kAt: number; ksay: string; ka: string; deal: Record<string, Deal>;
  // 第三期：连续钩中几次、这一关挨了几块石头、拉不动的东西吊了多久、淘汰后捣乱的冷却和次数、上次喊话的时刻、这一场的数据
  combo: number; rocksGot: number; hold: number; ghostAt: number; ghostN: number; emoAt: number; stats: Stats;
}
export interface Room {
  code: string; mode: Mode; rounds: number; host: string | null; conns: Set<Conn>; players: Player[];
  nextPid: number; nextItem: number; ph: Phase; round: number; tl: number; now: number;
  fields: Field[]; ev: Record<string, unknown>[]; money: number; earned: number; target: number;
  res: unknown; final: boolean; paused: boolean; dirty: boolean; acc: number; emptyAt: number;
  shopId: number; list: Record<string, number>; floor: Record<string, number>; sale: string;
  rnd: () => number;                // 随机数来源，测试里换成固定的
  event: RoundEvent | null;         // 这一关的随机事件
  keyBy: number;                    // 合作：钥匙在谁手里（玩家 id，0 是还没人钩到）。宝箱得由另一个人拉上来才打得开
  evHist: string[];                 // 每一关触发了什么事件（没有就是空字符串）
  forceEvents: string[] | null;     // 调试用：指定每一关的事件
  startedAt: number; logged: boolean;
}

export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
export const round10 = (v: number) => Math.round(v / 10) * 10;
export const pick = <T>(a: T[], rnd: () => number): T => a[Math.floor(rnd() * a.length)];
export const wallet = (room: Room, p: Player): { money: number } => room.mode === 'co' ? room : p;   // 合作模式钱是全队共用的
export const strong = (p: Player) => !!(p.buff.drink || p.strongR);
export const ev = (room: Room, o: Record<string, unknown>) => { room.ev.push(o); };

// 越打越深：每两关换一层。同屏对战局数少，一局下两层
export const depthOf = (room: Room) => room.mode === 'vs' ? room.round * 2 - 1 : room.round;
export const tierOf = (d: number) => Math.min(LAYERS.length - 1, Math.max(0, (d - 1) >> 1));
// 过关看的是"手里的钱"有没有到累计目标。每关新增的量 = (base + perPlayer×人数) × (1 + growth×(关数-1))，这里是它的累加
export const goalOf = (level: number, n: number) =>
  Math.round((B.GOAL.base + B.GOAL.perPlayer * n) * (level + B.GOAL.growth * level * (level - 1) / 2) / 10) * 10;
