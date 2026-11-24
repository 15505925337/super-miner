// 每张素材怎么处理。文件名（不含扩展名）就是键；素材清单.md 里的文件名以这里为准。
// 井下物件和钩爪以矿工的像素大小为准：1920×1080 全屏下一格约 2 个屏幕像素。
// 素材按原样或缩小后进游戏，不压色板。物件和钩爪在色块交界处抗锯齿，背景是手绘高清图。
//   kind: hd   会受灯光影响的物件：缩小 shrink 倍，配法线贴图
//         img  不受灯光影响的图：头像、图标、标题，只缩小
//         bg   整屏背景：原样用，有损压缩省包体
//   draw: 这张图在游戏里画多大（原型的 1280×720 坐标），只是备查，实际尺寸在 scripts/ 里按原型的画法算
const N = { bulge: 1, detail: 0.35, strength: 1.7, smooth: 3 };
// 任务 12 的 28 张物件图和 10 张钩爪图按原生尺寸入库，取代任务 10 的细版。
// 物件边长以服务端碰撞半径 × 1.875 为目标，钩爪固定 45 格。法线用亮度凹凸，压低小尺寸轮廓的坡度。
const pixelNormal = { ...N, bulge: 0, strength: 1.0 };
const item = { kind: 'hd', shrink: 1, normal: pixelNormal, draw: '边长 = 碰撞半径 × 2.5 的正方形' };
const miner = { kind: 'hd', shrink: 2, normal: { ...N, bulge: 0.6 }, draw: '128×128，木台底边落在台沿上' };
const claw = { ...item, draw: '60×60（含透明边），判定点在爪口中央，绳子接到绳环' };
const keeper = { kind: 'img', shrink: 1, draw: '商店里的半身像' };
const fx = { kind: 'img', shrink: 2, draw: '无光照的反馈图' };
const icon = { kind: 'img', shrink: 2, draw: '道具栏和商店里的小图标' };
const bg = { kind: 'bg', lossy: 0.9, draw: '1280×720 铺满，地面线在距顶 160 处' };

export const SPEC = {
  gold_s: item, gold_m: item, gold_l: item, gold_xl: item, rock_s: item, rock_l: item,
  gem: item, ruby: item, bag: item, tnt: item, beetle: item, beetle_2: item, fossil: item,
  key: item, chest: item, chest_open: { ...item, draw: '开箱弹图，1080p 下宽 100 个屏幕像素' },
  miner_1: miner, miner_2: miner, miner_3: miner, miner_4: miner,
  miner_1_pull: miner, miner_2_pull: miner, miner_3_pull: miner, miner_4_pull: miner,
  miner_1_happy: miner, miner_2_happy: miner, miner_3_happy: miner, miner_4_happy: miner,
  keeper_idle: keeper, keeper_neutral: keeper, keeper_happy: keeper, keeper_angry: keeper, keeper_happy_move: keeper, keeper_angry_move: keeper,
  icon_d: icon, icon_s: icon, icon_f: icon, icon_h: icon, icon_drink: icon, icon_clover: icon, icon_polish: icon, icon_book: icon,
  logo: { kind: 'img', shrink: 1, draw: '首页标题' },
  bg_1: bg, bg_2: bg, bg_3: bg, bg_4: bg,
  shop_bg: { ...bg, draw: '商店整屏背景' },
  home_bg: { ...bg, draw: '首页整屏背景' },
};
for (const size of ['s', 'm', 'l', 'xl']) {
  for (const n of [1, 2, 3]) SPEC[`gold_${size}_${n}`] = SPEC[`gold_${size}`];
}
for (const n of [1, 2, 3, 4, 5]) {
  for (const pose of ['open', 'closed']) SPEC[`claw_${n}_${pose}`] = claw;
}
for (const n of [1, 2, 3, 4]) {
  for (const pose of ['idle2', 'crank1', 'crank2', 'crank3', 'crank4', 'pull2', 'happy2', 'sad', 'hit', 'throw']) {
    SPEC[`miner_${n}_${pose}`] = miner;
  }
  for (const [part, draw] of Object.entries({ far: '远景后墙', frame: '支架层', fg: '前景剪影' })) {
    SPEC[`bg_${n}_${part}`] = { ...bg, draw };
  }
}
for (const face of ['think', 'surprised', 'sigh', 'smug', 'refuse', 'bye', 'neutral_blink', 'neutral_talk']) {
  SPEC[`keeper_${face}`] = keeper;
}
for (const [name, count] of Object.entries({ boom: 6, spark: 4, dust: 4 })) {
  for (let i = 1; i <= count; i++) SPEC[`${name}_${i}`] = fx;
}
SPEC.ice = fx;
