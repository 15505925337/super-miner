// 商店和还价的测试，重点是引擎的兜底：不管老板的"脑子"说什么，成交价不低于底价。
import test from 'node:test';
import assert from 'node:assert/strict';
import { SHOP, KEEPER } from '../src/core.ts';
import { endRound, tickRoom } from '../src/game.ts';
import { openShop, buy, buyClick, ruleBrain, keeperAct, keeperApply } from '../src/shop.ts';
import type { KeeperCtx, KeeperReply } from '../src/shop.ts';
import { playing, rng, run } from './helpers.ts';

const ALL = Object.keys(SHOP);
// 测试里默认把货全部上架，这样每条测试要用的那件一定在；专门测"只上架一部分"的用 randomStock
function shop(mode: 'co' | 'vs' | 'race' = 'vs', seed = 1, humans = 1, randomStock = false) {
  const g = playing(mode, humans, seed);
  endRound(g.room); g.room.final = false; openShop(g.room, randomStock ? undefined : ALL);
  return g;
}
let clock = Date.now() + 60_000;                           // 测试用的钟，从现在往后走
const tick = () => (clock += 1000);                           // 每次出价间隔 1 秒，避开防刷屏
const brain = (r: KeeperReply) => (_c: KeeperCtx) => r;

test('开店：标价在原价的 0.85 到 1.25 倍之间，特价再打 7 折，底价在标价的 0.58 到 0.78 倍之间', () => {
  for (let seed = 1; seed <= 40; seed++) {
    const { room } = shop('vs', seed);
    for (const k of Object.keys(room.list)) {
      const base = SHOP[k].price, lo = base * 0.85, hi = base * 1.25, mul = k === room.sale ? 0.7 : 1;
      assert.ok(room.list[k] >= Math.floor(lo * mul / 10) * 10 - 10 && room.list[k] <= Math.ceil(hi * mul / 10) * 10 + 10, `${k} 标价 ${room.list[k]} 出了范围`);
      assert.equal(room.list[k] % 10, 0);
      assert.ok(room.floor[k] >= room.list[k] * 0.58 - 10 && room.floor[k] <= room.list[k] * 0.78 + 10, `${k} 底价出了范围`);
      assert.ok(room.floor[k] < room.list[k]);
    }
    assert.ok(Object.keys(room.list).includes(room.sale));
  }
});

test('开店：每次只上架 4 到 5 件，炸药每次都有，其余随机；上架的都是这个玩法能卖的，特价的那件一定在架上', () => {
  const sizes = new Set<number>(), seen = new Set<string>(), combos = new Set<string>();
  for (let seed = 1; seed <= 300; seed++) {
    const mode = (['vs', 'co', 'race'] as const)[seed % 3];
    const { room, ps: [p] } = shop(mode, seed, 1, true);
    const keys = Object.keys(room.list);
    sizes.add(keys.length); combos.add(mode + ':' + keys.join(','));
    assert.ok(keys.length >= 4 && keys.length <= 5, '上架了 ' + keys.length + ' 件');
    assert.ok(keys.includes('d'), '炸药必定上架');
    for (const k of keys) { seen.add(k); assert.ok(!SHOP[k].only || SHOP[k].only!.includes(mode), k + ' 不该在 ' + mode + ' 里卖'); }
    assert.ok(keys.includes(room.sale)); assert.deepEqual(Object.keys(room.floor), keys); assert.deepEqual(Object.keys(p.deal), keys);
    const out = ALL.find(k => !keys.includes(k))!;
    p.money = 99999; assert.equal(buy(room, p, out), false, '没上架的买不了');
  }
  assert.deepEqual([...sizes].sort(), [4, 5]);
  assert.equal(seen.size, ALL.length, '每件货都有机会上架');
  assert.ok(combos.size > 50, '每次的货架不一样，实际 ' + combos.size + ' 种');
});

test('开店：货全上架时，各玩法只卖自己的道具', () => {
  assert.deepEqual(Object.keys(shop('vs').room.list).sort(), ['book', 'clover', 'd', 'drink', 'f', 'polish', 's']);
  assert.deepEqual(Object.keys(shop('race').room.list).sort(), ['book', 'clover', 'd', 'drink', 'f', 'polish', 's']);
  assert.deepEqual(Object.keys(shop('co').room.list).sort(), ['book', 'clover', 'd', 'drink', 'h', 'polish']);
});

test('开店：老板先打招呼，说今天什么特价', () => {
  const { room, ps: [p] } = shop();
  assert.ok(p.ksay.includes('今天' + SHOP[room.sale].n + '特价')); assert.equal(p.kn, 1);
  assert.equal(p.ka, 'idle');
  assert.ok(p.mood >= 55 && p.mood < 80);
});

test('按标价买：扣钱发货；钱不够买不了；道具最多 5 个；增益一局只能买一份', () => {
  const { room, ps: [p] } = shop();
  p.money = 2000;
  const price = room.list.d;
  assert.equal(buyClick(room, p, 'd'), true); assert.equal(p.money, 2000 - price); assert.equal(p.tools.d, 2);
  assert.ok(['拿好。', '识货。', '好嘞，收你 ¥' + price + '。'].includes(p.ksay));
  assert.equal(p.ka, 'smug');
  p.tools.d = 5; assert.equal(buy(room, p, 'd'), false, '已经 5 个了');
  assert.equal(buy(room, p, 'drink'), true); assert.equal(p.next.drink, 1); assert.equal(buy(room, p, 'drink'), false, '增益只能买一份');
  p.money = room.list.book - 10; assert.equal(buy(room, p, 'book'), false, '钱不够');
  assert.equal(buy(room, p, 'nothing'), false); assert.equal(buy(room, p, 'h'), false, '对战不卖沙漏');
  room.ph = 'play'; p.money = 9999; assert.equal(buy(room, p, 'clover'), false, '不在商店阶段不能买');
});

test('合作模式买东西花的是全队的钱', () => {
  const { room, ps: [a, b] } = shop('co', 1, 2);
  room.money = 1000;
  assert.equal(buy(room, b, 'd'), true);
  assert.equal(room.money, 1000 - room.list.d); assert.equal(a.money, 0); assert.equal(b.money, 0);
});

test('买的增益下一关生效，再下一关失效', () => {
  const { room, ps: [p] } = shop();
  p.money = 2000; buy(room, p, 'polish'); p.ready = true;
  tickRoom(room, 1 / 30);
  assert.equal(room.ph, 'count'); assert.equal(p.buff.polish, 1); assert.deepEqual(p.next, {});
});

test('还价兜底：脑子想低于底价卖，不卖，要价改成底价', () => {
  const { room, ps: [p] } = shop();
  p.money = 5000; p.mood = 80;
  const floor = room.floor.drink, list = room.list.drink;
  keeperAct(room, p, 'offer', 'drink', floor - 30, null, tick(), brain({ say: '行，卖你', action: 'accept' }));
  assert.equal(p.next.drink, undefined, '没成交'); assert.equal(p.money, 5000);
  assert.equal(p.deal.drink.ask, floor); assert.ok(p.ksay.includes('最低 ¥' + floor));
  assert.equal(p.ka, 'sigh');
  assert.ok(floor < list);
});

test('还价兜底：脑子的还价被夹在 [底价和出价里较高的, 当前要价] 之间', () => {
  const a = shop(); a.ps[0].money = 5000; a.ps[0].mood = 80;
  keeperAct(a.room, a.ps[0], 'offer', 'drink', 100, null, tick(), brain({ say: '白送', action: 'counter', price: 1 }));
  assert.equal(a.ps[0].deal.drink.ask, a.room.floor.drink, '还价太低，抬到底价');
  assert.equal(a.ps[0].ka, 'sigh');
  const b = shop(); b.ps[0].money = 5000; b.ps[0].mood = 80;
  keeperAct(b.room, b.ps[0], 'offer', 'drink', 100, null, tick(), brain({ say: '涨价', action: 'counter', price: 99999 }));
  assert.equal(b.ps[0].deal.drink.ask, b.room.list.drink, '还价不会比当前要价高');
  const c = shop(); c.ps[0].money = 5000; c.ps[0].mood = 80;
  const o = c.room.floor.drink + 20;
  keeperAct(c.room, c.ps[0], 'offer', 'drink', o, null, tick(), brain({ say: '少点', action: 'counter', price: c.room.floor.drink }));
  assert.equal(c.ps[0].deal.drink.ask, o, '还价不会比玩家的出价还低');
});

test('还价兜底：耐心一次最多涨 15、掉 30，一次逛店最多哄高 25', () => {
  const { room, ps: [p] } = shop(); p.mood = 50;
  keeperAct(room, p, 'chat', '', null, '老板真帅', tick(), brain({ say: '嘿嘿', mood: 999 }));
  assert.equal(p.mood, 65);
  keeperAct(room, p, 'chat', '', null, '老板真帅', tick(), brain({ say: '嘿嘿', mood: 999 }));
  assert.equal(p.mood, 75, '第二次只能再涨 10，总共 25');
  keeperAct(room, p, 'chat', '', null, '老板真帅', tick(), brain({ say: '嘿嘿', mood: 999 }));
  assert.equal(p.mood, 75);
  keeperAct(room, p, 'chat', '', null, '黑店', tick(), brain({ say: '哼', mood: -999 }));
  assert.equal(p.mood, 45); assert.equal(p.ka, 'angry');
});

test('还价规矩：每件最多还 4 次；耐心掉光就不讲了；出价比兜里的钱多不理', () => {
  const { room, ps: [p] } = shop(); p.money = 5000; p.mood = 100;
  const never = brain({ say: '不行', action: 'refuse', mood: 0 });
  for (let i = 0; i < 4; i++) keeperAct(room, p, 'offer', 'drink', 50, null, tick(), never);
  assert.equal(p.deal.drink.tries, 4);
  keeperAct(room, p, 'offer', 'drink', 50, null, tick(), brain({ say: '卖', action: 'accept' }));
  assert.equal(p.ksay, '这件就这个价了，别磨了。'); assert.equal(p.deal.drink.tries, 4);
  assert.equal(p.ka, 'refuse');
  p.money = 30; keeperAct(room, p, 'offer', 'd', 100, null, tick(), never);
  assert.equal(p.ksay, '你兜里都没这么多钱，还跟我讲价？'); assert.equal(p.deal.d.tries, 0, '不算一次还价');
  assert.equal(p.ka, 'refuse');
  p.money = 5000; p.mood = 0; keeperAct(room, p, 'offer', 'd', 100, null, tick(), never);
  assert.equal(p.ksay, '不讲了不讲了，就这个价，爱买不买。'); assert.equal(p.ka, 'refuse'); assert.equal(p.deal.d.tries, 0);
});

test('还价规矩：出价到了要价就成交，按要价和出价里较低的收钱', () => {
  const { room, ps: [p] } = shop(); p.money = 5000;
  const ask = room.list.d;
  keeperAct(room, p, 'offer', 'd', ask + 500, null, tick());
  assert.equal(p.tools.d, 2); assert.equal(p.money, 5000 - ask); assert.equal(p.ka, 'smug');
});

test('掌柜表情：正常还中间价时思考，出价太低大掉耐心时吃惊', () => {
  const { room, ps: [p] } = shop();
  p.money = 5000; p.mood = 60;
  room.floor.drink = 180; room.list.drink = p.deal.drink.ask = 260;
  const offer = (price: number) => keeperAct(room, p, 'offer', 'drink', price, null, tick(), c => ruleBrain(c, () => 0.99));
  offer(190);
  assert.equal(p.deal.drink.ask, 230);
  assert.equal(p.ka, 'think');
  offer(150);
  assert.equal(p.deal.drink.ask, 190);
  assert.equal(p.mood, 43);
  assert.equal(p.ka, 'surprised');
  offer(50);
  assert.equal(p.deal.drink.ask, 190);
  assert.equal(p.ka, 'surprised');
  offer(50);
  assert.equal(p.mood, 0);
  assert.equal(p.ka, 'refuse');
});

test('掌柜表情：底价成交叹气，普通成交高兴，高价成交得意', () => {
  for (const [price, face] of [[180, 'sigh'], [210, 'happy'], [240, 'smug']] as const) {
    for (const direct of [true, false]) {
      const { room, ps: [p] } = shop();
      p.money = 5000;
      room.floor.drink = 180; room.list.drink = p.deal.drink.ask = 270;
      if (direct) {
        p.deal.drink.ask = price;
        assert.equal(buyClick(room, p, 'drink'), true);
      } else {
        keeperAct(room, p, 'offer', 'drink', price, null, tick(), brain({ say: '拿好。', action: 'accept' }));
      }
      assert.equal(p.money, 5000 - price);
      assert.equal(p.next.drink, 1);
      assert.equal(p.ka, face);
    }
  }
});

test('掌柜表情：普通招呼平静，夸奖高兴，骂人生气', () => {
  const { room, ps: [p] } = shop();
  assert.equal(p.ka, 'idle');
  keeperAct(room, p, 'chat', '', null, '老板真帅', tick());
  assert.equal(p.ka, 'happy');
  keeperAct(room, p, 'chat', '', null, '你这黑店', tick());
  assert.equal(p.ka, 'angry');
});

test('还价规矩：谈成了但买不了（已经有了），告诉玩家', () => {
  const { room, ps: [p] } = shop(); p.money = 5000; p.next.drink = 1;
  keeperAct(room, p, 'offer', 'drink', room.list.drink, null, tick());
  assert.ok(p.ksay.startsWith('价是谈好了')); assert.equal(p.money, 5000);
});

test('防刷屏：350 毫秒内连着说话只理第一句', () => {
  const { room, ps: [p] } = shop(); const n = p.kn;
  const t0 = tick();
  keeperAct(room, p, 'chat', '', null, '你好', t0);
  keeperAct(room, p, 'chat', '', null, '你好', t0 + 200);
  assert.equal(p.kn, n + 1);
  keeperAct(room, p, 'chat', '', null, '你好', t0 + 400);
  assert.equal(p.kn, n + 2);
});

test('规则版的脑子：出价到要价就卖；低得离谱直接拒绝并且很不高兴', () => {
  const item = { key: 'drink', name: '大力饮料', list: 260, ask: 260, floor: 180, tries: 1 };
  const ctx = (offer: number, extra: Partial<KeeperCtx> = {}): KeeperCtx => ({ kind: 'offer', mode: 'vs', round: 1, mood: 60, flattered: 0, sale: '炸药', player: { name: '甲', money: 999 }, item, offer, text: null, ...extra });
  assert.equal(ruleBrain(ctx(260), rng(1)).action, 'accept');
  const low = ruleBrain(ctx(100), rng(1));                   // 100 < 180 × 0.6
  assert.equal(low.action, 'refuse'); assert.equal(low.mood, -25);
});

test('规则版的脑子：过了底价也不一定卖，磨过两回或者差得不多才松口，否则还个中间价', () => {
  const mk = (tries: number) => ({ key: 'drink', name: '大力饮料', list: 260, ask: 260, floor: 180, tries });
  const ctx = (offer: number, tries: number, mood: number): KeeperCtx => ({ kind: 'offer', mode: 'vs', round: 1, mood, flattered: 0, sale: '炸药', player: { name: '甲', money: 999 }, item: mk(tries), offer, text: null });
  const never = () => 0.999;                                  // 随机数取最大，排除"老板心情好"那条
  assert.equal(ruleBrain(ctx(190, 2, 30), never).action, 'accept', '磨过两回，过底价就卖');
  assert.equal(ruleBrain(ctx(230, 1, 30), never).action, 'accept', '230 ≥ 260 × 0.88，差得不多');
  const c = ruleBrain(ctx(190, 1, 30), never);
  assert.equal(c.action, 'counter'); assert.equal(c.price, 230); assert.equal(c.mood, -5);     // (190 + 260) / 2 = 225 → 取整到 10
  const d = ruleBrain(ctx(150, 1, 30), never);
  assert.equal(d.action, 'counter'); assert.equal(d.price, 210); assert.equal(d.mood, -12, '低于底价，更不高兴');
  const e = ruleBrain({ ...ctx(120, 1, 30), item: { ...mk(1), ask: 200 } }, never);
  assert.equal(e.price, 180, '还价不低于底价');
  assert.equal(ruleBrain(ctx(190, 1, 100), () => 0.5).action, 'accept', '心情好（耐心 100）有机会直接卖');
});

test('规则版的脑子：骂人掉耐心，夸两次以内涨耐心，问推荐按兜里的钱回答', () => {
  const ctx = (text: string, extra: Partial<KeeperCtx> = {}): KeeperCtx => ({ kind: 'chat', mode: 'vs', round: 1, mood: 60, flattered: 0, sale: '炸药', player: { name: '甲', money: 500 }, item: null, offer: null, text, ...extra });
  assert.equal(ruleBrain(ctx('你这黑店'), rng(1)).mood, -18);
  assert.equal(ruleBrain(ctx('老板真帅'), rng(1)).mood, 12);
  assert.equal(ruleBrain(ctx('老板真帅', { flattered: 2 }), rng(1)).mood, undefined);
  assert.ok(ruleBrain(ctx('推荐点啥'), rng(1)).say!.includes('大力饮料'));
  assert.ok(ruleBrain(ctx('推荐点啥', { player: { name: '甲', money: 150 } }), rng(1)).say!.includes('炸药'));
  assert.ok(ruleBrain(ctx('推荐点啥', { player: { name: '甲', money: 50 } }), rng(1)).say!.includes('石头图鉴'));
});

test('走完整的还价：用规则版的脑子反复出价，成交价永远不低于底价', () => {
  let deals = 0;
  for (let seed = 1; seed <= 200; seed++) {
    const { room, ps: [p] } = shop('vs', seed); p.money = 5000;
    const r = rng(seed + 999);
    for (const k of Object.keys(room.list)) {
      const before = p.money, hadTool = { ...p.tools }, hadNext = { ...p.next };
      for (let i = 0; i < 6; i++) keeperAct(room, p, 'offer', k, Math.round(room.list[k] * (0.3 + r() * 0.8)), null, tick());
      const paid = before - p.money, bought = SHOP[k].tool ? p.tools[k] - hadTool[k] : (p.next[k] || 0) - (hadNext[k] || 0);
      if (bought) { deals++; assert.ok(paid >= room.floor[k] * bought, `${k} 以 ${paid} 成交，低于底价 ${room.floor[k]}`); assert.ok(paid <= room.list[k] * bought); }
      else assert.equal(paid, 0, '没成交不该扣钱');
      assert.ok(p.deal[k].ask >= room.floor[k] && p.deal[k].ask <= room.list[k]);
      assert.ok(p.deal[k].tries <= KEEPER.maxTries);
    }
    assert.ok(p.mood >= 0 && p.mood <= 100);
  }
  assert.ok(deals > 100, '应该有相当一部分谈成了，实际 ' + deals);
});

test('电脑玩家逛店：对战里有钱会买，合作里不花全队的钱', () => {
  let spent = 0;
  for (let seed = 1; seed <= 40; seed++) {
    const vs = playing('vs', 1, seed, 1); vs.ps[1].money = 5000; endRound(vs.room); openShop(vs.room);
    assert.ok(vs.ps[1].money <= 5000 && vs.ps[1].money >= 0);
    if (vs.ps[1].money < 5000) spent++;
    for (const k of Object.keys(vs.ps[1].next)) assert.ok(k in vs.room.list, '电脑买的东西必须是架上有的');
  }
  assert.ok(spent > 5, '40 次里电脑至少有几次买了东西，实际 ' + spent);
  const co = playing('co', 1, 3, 1); co.room.money = 5000; endRound(co.room); co.room.final = false; openShop(co.room);
  assert.equal(co.room.money, 5000);
  void run;
});

void keeperApply;
