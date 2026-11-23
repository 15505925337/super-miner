// 商店和老板。规则照原型：
//   引擎（keeperAct / keeperApply）管规矩：底价、耐心、每件最多还几次价、扣钱发货。结果以引擎为准。
//   脑子（ruleBrain）只管两件事：老板这句话怎么说、这一手是答应 / 还价 / 拒绝。
// 这一期只有规则版的脑子。以后接模型，只换脑子，keeperApply 的兜底不变：
// 成交价不会低于底价，还价被夹在 [底价, 当前要价] 之间，耐心一次最多涨 15、掉 30。
import { SHOP, SHOP_T, KEEPER, RULES, clamp, round10, pick, wallet } from './core.ts';
import type { Room, Player } from './core.ts';

export interface KeeperCtx {
  kind: 'greet' | 'offer' | 'chat'; mode: string; round: number; mood: number; flattered: number; sale: string;
  player: { name: string; money: number };
  item: { key: string; name: string; list: number; ask: number; floor: number; tries: number } | null;
  offer: number | null; text: string | null;
}
export interface KeeperReply { say?: string; action?: string; price?: number; mood?: number }

// 开店。每次只上架一部分货（数量在 stockMin 到 stockMax 之间随机），不是每回都什么都卖；stockAlways 里的（炸药）每次都有。
// stock：指定上架哪几件（测试用）；不传就随机挑
export function openShop(room: Room, stock?: string[]): void {
  room.shopId++;
  const all = Object.keys(SHOP).filter(k => !SHOP[k].only || SHOP[k].only!.includes(room.mode));
  let keys = all;
  if (stock) keys = all.filter(k => stock.includes(k));
  else {
    const n = Math.min(all.length, KEEPER.stockMin + Math.floor(room.rnd() * (KEEPER.stockMax - KEEPER.stockMin + 1)));
    const always: string[] = (KEEPER.stockAlways || []).filter((k: string) => all.includes(k));   // 必定上架的（炸药）
    const pool = all.filter(k => !always.includes(k)), chosen = new Set<string>(always);
    while (chosen.size < n && pool.length) chosen.add(pool.splice(Math.floor(room.rnd() * pool.length), 1)[0]);
    keys = all.filter(k => chosen.has(k));                  // 保持货架上固定的先后顺序
  }
  room.list = {}; room.floor = {};
  for (const k of keys) room.list[k] = round10(SHOP[k].price * (KEEPER.priceMin + room.rnd() * KEEPER.priceSpan));
  room.sale = pick(keys, room.rnd);
  room.list[room.sale] = round10(room.list[room.sale] * KEEPER.saleMul);                                  // 今日特价
  for (const k of keys) room.floor[k] = round10(room.list[k] * (KEEPER.floorMin + room.rnd() * KEEPER.floorSpan));   // 老板心里的底价，不告诉玩家
  room.ph = 'shop'; room.tl = SHOP_T; room.dirty = true;
  for (const p of room.players) {
    p.ready = false; p.mood = KEEPER.moodMin + Math.floor(room.rnd() * KEEPER.moodSpan);
    p.moodUp = 0; p.flat = 0; p.kn = 0; p.kAt = 0; p.ksay = ''; p.ka = 'idle';
    p.deal = {};                                             // 标价、底价大家一样，谈下来的要价各算各的
    for (const k of keys) p.deal[k] = { ask: room.list[k], tries: 0 };
    if (p.out) continue;
    if (!p.bot) keeperAct(room, p, 'greet');
    else if (room.mode !== 'co') {                           // 电脑不讲价，只在对战里花自己的钱
      if (p.money > 700 && room.rnd() < 0.6) buy(room, p, 'drink');
      if (p.money > 400 && p.tools.d < 2 && room.rnd() < 0.5) buy(room, p, 'd');
    }
  }
}

// 按这个人当前谈到的价买，成了返回 true
export function buy(room: Room, p: Player, k: string): boolean {
  const def = SHOP[k], d = p.deal && Object.prototype.hasOwnProperty.call(p.deal, k) ? p.deal[k] : null;
  if (room.ph !== 'shop' || !def || !d || p.out) return false;
  const w = wallet(room, p);
  if (!(w.money >= d.ask)) return false;
  if (def.tool) { if (p.tools[k] >= RULES.toolMax) return false; p.tools[k]++; }
  else { if (p.next[k]) return false; p.next[k] = 1; }
  w.money -= d.ask; room.dirty = true;
  p.stats.buys[k] = (p.stats.buys[k] || 0) + 1;
  return true;
}

function saleFace(price: number, floor: number, list: number): string {
  if (price === floor) return 'sigh';
  // 成交价位于底价与标价之间靠近标价的三分之一。
  return price >= floor + (list - floor) * 2 / 3 ? 'smug' : 'happy';
}

// 玩家直接按标价（或已经谈到的价）点"购买"
export function buyClick(room: Room, p: Player, k: string): boolean {
  if (!buy(room, p, k)) return false;
  const price = p.deal[k].ask;
  p.ksay = pick(['拿好。', '好嘞，收你 ¥' + price + '。', '识货。'], room.rnd);
  p.ka = saleFace(price, room.floor[k], room.list[k]); p.kn++;
  return true;
}

export function ruleBrain(c: KeeperCtx, rnd: () => number): KeeperReply {
  if (c.kind === 'greet') {
    return { say: pick(['来啦，随便看。', '今天挖得怎么样？', '哟，又下来一层，不容易。'], rnd) + '今天' + c.sale + '特价。嫌贵就点「还价」。', action: 'none' };
  }
  if (c.kind === 'offer') {
    const it = c.item!, o = c.offer!;
    if (o >= it.ask) return { say: pick(['爽快！拿好。', '成交，下回再来。'], rnd), action: 'accept', mood: 5 };
    if (o < it.floor * KEEPER.lowballBelowFloor) return { say: pick(['¥' + o + '？你这是明抢。', '这价我进货都进不来，别闹。'], rnd), action: 'refuse', mood: -25 };
    // 过了底价也不一定马上卖：磨过两回、差得不多、或者老板心情好，才松口
    if (o >= it.floor && (it.tries >= 2 || o >= it.ask * KEEPER.quickAcceptAtAsk || rnd() * 100 < c.mood - 30)) {
      return { say: pick(['唉，行吧行吧，¥' + o + ' 拿走。', '看你顺眼，¥' + o + ' 给你了。'], rnd), action: 'accept', mood: -4 };
    }
    const price = Math.max(it.floor, round10((o + it.ask) / 2));
    return { say: pick(['¥' + o + ' 太低了，¥' + price + ' 怎么样？', '各让一步，¥' + price + '。', '最多让到 ¥' + price + '。'], rnd), action: 'counter', price, mood: o < it.floor ? -12 : -5 };
  }
  const t = c.text || '';
  if (/滚|傻|笨|黑店|奸商|骗子|坑/.test(t)) return { say: pick(['说谁呢？再这样不卖你了。', '嘿，小心我涨价。'], rnd), action: 'none', mood: -18 };
  if (/帅|美|漂亮|好看|年轻|发财|兴隆|大气|好人|辛苦|谢谢|厉害/.test(t)) {
    return c.flattered < 2 ? { say: pick(['嘴真甜，听着舒坦。', '会说话。可夸我归夸我，账得另算。'], rnd), action: 'none', mood: 12 } : { say: '行了行了，夸多了就假了。', action: 'none' };
  }
  if (/推荐|买什么|买啥|哪个好|建议|有什么用/.test(t)) {
    const m = c.player.money;
    return { say: m >= 300 ? '钱够就买大力饮料，拉得快什么都好说。' : m >= 120 ? '手头紧就备个炸药，拉到石头不耽误工夫。' : '你这点钱……石头图鉴便宜，凑合用。', action: 'none' };
  }
  if (/穷|没钱|可怜|求|拜托|便宜|贵|打折|优惠|少点/.test(t)) return { say: pick(['一分钱一分货。点一件「还价」，出个数我听听。', '嫌贵就还价嘛，光喊没用。'], rnd), action: 'none', mood: -2 };
  if (/你好|在吗|老板|掌柜|嗨/.test(t)) return { say: pick(['在呢在呢，要什么？', '说，买啥？'], rnd), action: 'none' };
  return { say: pick(['嗯？想买什么直说。', '我只管卖货，闲聊得加钱。', '挖矿的事我不懂，货我懂。'], rnd), action: 'none' };
}

// 玩家对老板做了一件事：进店打招呼 / 对某件商品出价 / 说一句话
export function keeperAct(room: Room, p: Player, kind: 'greet' | 'offer' | 'chat', k?: string, offerIn?: unknown, text?: string | null,
  nowMs: number = Date.now(), brain: (c: KeeperCtx, rnd: () => number) => KeeperReply = ruleBrain): void {
  if (room.ph !== 'shop' || p.out || !p.deal) return;
  if (kind !== 'greet' && nowMs - p.kAt < KEEPER.spamMs) return;       // 别刷屏
  p.kAt = nowMs;
  const d = k && Object.prototype.hasOwnProperty.call(p.deal, k) ? p.deal[k] : null;
  const reply = (say: string, action = 'idle') => { p.ksay = say; p.ka = action; p.kn++; room.dirty = true; };
  let offer = 0;
  if (kind === 'offer') {
    offer = Math.round(Number(offerIn));
    if (!d || !(offer > 0)) return;
    if (p.mood <= 0) return reply('不讲了不讲了，就这个价，爱买不买。', 'refuse');
    if (d.tries >= KEEPER.maxTries) return reply('这件就这个价了，别磨了。', 'refuse');
    if (wallet(room, p).money < offer) return reply('你兜里都没这么多钱，还跟我讲价？', 'refuse');
    d.tries++; p.stats.haggles++;
  }
  const ctx: KeeperCtx = {
    kind, mode: room.mode, round: room.round, mood: p.mood, flattered: p.flat || 0, sale: SHOP[room.sale].n,
    player: { name: p.name, money: wallet(room, p).money },
    item: d ? { key: k!, name: SHOP[k!].n, list: room.list[k!], ask: d.ask, floor: room.floor[k!], tries: d.tries } : null,
    offer: kind === 'offer' ? offer : null, text: text || null,
  };
  keeperApply(room, p, ctx, brain(ctx, room.rnd) || {});
}

// 把脑子的回答落到账上。脑子乱出牌也不怕，规矩在这里兜住
export function keeperApply(room: Room, p: Player, ctx: KeeperCtx, r: KeeperReply): void {
  let say = String(r.say || '……').slice(0, KEEPER.sayMax);
  let dm = clamp(Math.round(Number(r.mood) || 0), KEEPER.moodStepMin, KEEPER.moodStepMax);
  if (dm > 0) {                                              // 一次逛店最多哄高 25
    dm = Math.min(dm, KEEPER.moodUpCap - p.moodUp); p.moodUp += dm;
    if (ctx.kind === 'chat') p.flat = (p.flat || 0) + 1;
  }
  p.mood = clamp(p.mood + dm, 0, 100);
  let reaction = dm <= -12 ? (ctx.kind === 'offer' ? 'surprised' : 'angry') : dm > 0 && ctx.kind !== 'greet' ? 'happy' : 'idle';
  if (ctx.kind === 'offer' && ctx.item && ctx.offer != null) {
    const k = ctx.item.key, d = p.deal[k], floor = room.floor[k];
    if (ctx.offer >= d.ask || (r.action === 'accept' && ctx.offer >= floor)) {
      d.ask = Math.min(d.ask, ctx.offer);
      if (buy(room, p, k)) reaction = saleFace(d.ask, floor, room.list[k]);
      else say = '价是谈好了，可你这会儿买不了（钱不够，或者已经有了）。';
    } else if (r.action === 'accept') {                      // 脑子想低于底价卖：不行，改成还到底价
      d.ask = Math.min(d.ask, floor); say = '这个数真不行，最低 ¥' + d.ask + '。';
      reaction = 'sigh';
    } else if (r.action === 'counter') {
      d.ask = round10(clamp(Number(r.price) || d.ask, Math.max(floor, ctx.offer), d.ask));
      if (d.ask === floor) reaction = 'sigh';
      else if (reaction !== 'surprised') reaction = 'think';
    } else if (r.action === 'refuse' && (p.mood === 0 || reaction !== 'surprised')) {
      reaction = 'refuse';
    }
  }
  p.ksay = say; p.ka = reaction; p.kn++; room.dirty = true;
}
