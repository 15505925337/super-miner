#!/usr/bin/env node
// 给四层的井壁程序生成"质地"：正式背景图在井里那一大块几乎是纯平的渐变色（实测八到九成的地方没有细节），
// 灯光照上去没有东西可照。这里为每一层生成三张图，叠在背景图上用：
//   relief_N.png    明暗细节（裂缝发暗、凸起发亮），乘到底图上
//   relief_N_n.png  凹凸（法线贴图），让灯照出起伏
//   relief_N_e.png  自己发光的部分（晶洞层的矿脉、熔岩层的裂缝），叠加
// 只影响地面线以下。固定种子，每次生成结果一样。用法：node tools/gen_relief.mjs
import { newImg, setPx, fbm, vnoise } from './lib/pixel.mjs';
import { emitPlain } from './lib/emit.mjs';

const W = 960, H = 540, SURF = 120;                 // 960×540 是设计画面的 1.5 倍；地面线在 22% 处
const hash = (a, b, s) => { let n = Math.imul(a, 374761393) + Math.imul(b, 668265263) + Math.imul(s, 362437); n = Math.imul(n ^ (n >>> 13), 1274126177); return ((n ^ (n >>> 16)) >>> 0) / 4294967296; };

// 不规则的块（石块、晶面、玄武岩板）：返回离最近的块心多远、离块的边界多远、这是哪一块
function cells(x, y, size, squash, seed) {
  const gx = x / size, gy = y / (size * squash), ix = Math.floor(gx), iy = Math.floor(gy);
  let d1 = 1e9, d2 = 1e9, id = 0, cx = 0, cy = 0;
  for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
    const px = ix + i + 0.15 + 0.7 * hash(ix + i, iy + j, seed), py = iy + j + 0.15 + 0.7 * hash(ix + i, iy + j, seed + 1);
    const d = Math.hypot((gx - px) * size, (gy - py) * size * squash);
    if (d < d1) { d2 = d1; d1 = d; id = (ix + i) * 7919 + (iy + j) * 104729; cx = px * size; cy = py * size * squash; }
    else if (d < d2) d2 = d;
  }
  return { d1, edge: (d2 - d1) * 0.5, id, cx, cy };
}

// 弯弯曲曲的线（矿脉、岩浆脉）：取噪声的等高线，half 大约是线的半宽（像素）
const vein = (x, y, f, seed, half) => Math.max(0, 1 - Math.abs(fbm(x * f, y * f, seed) - 0.47) / (half * f * 1.5));
const sm = (a, b, v) => { const t = Math.max(0, Math.min(1, (v - a) / (b - a))); return t * t * (3 - 2 * t); };

// 每层的岩块：多大、扁还是长、扭曲多少、每块朝向差多少、块之间明暗差多少、裂缝多宽多深、多少裂缝看得见、表面多粗糙
const ROCK = [null,
  { size: 118, squash: 0.62, warp: 36, tilt: 0.3, tone: 0.1, crackW: 1.5, crackD: 0.2, show: 0.5, rough: 0.1 },      // 岩石层：扁平的大岩块叠着
  { size: 100, squash: 1.5, warp: 14, tilt: 0.75, tone: 0.08, crackW: 1.1, crackD: 0.05, show: 0.3, rough: 0.04 },   // 晶洞层：竖长的晶面，面与面朝向差得多
  { size: 132, squash: 0.8, warp: 30, tilt: 0.28, tone: 0.1, crackW: 2.0, crackD: 0.24, show: 0.6, rough: 0.1 },     // 熔岩层：大块玄武岩
];

function gen(tier) {
  const Hm = new Float32Array(W * H).fill(0.5), E = new Float32Array(W * H * 3);
  for (let y = SURF; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x, depth = (y - SURF) / (H - SURF);
    let h = 0.5 + 0.12 * (fbm(x * 0.004, y * 0.004, 5 + tier) - 0.47);          // 大片的深浅变化
    if (tier === 0) {
      // 浅土层：一层一层的土，稀稀拉拉嵌着小石子
      const s = y + 52 * (fbm(x * 0.005, y * 0.01, 11) - 0.47);
      h += 0.07 * Math.sin(s * 0.07) + 0.04 * Math.sin(s * 0.19 + 1.3);
      h += 0.26 * (fbm(x * 0.02, y * 0.035, 12) - 0.47) + 0.1 * (fbm(x * 0.09, y * 0.09, 16) - 0.47);
      const c = cells(x, y, 40, 1, 13);
      if (hash(c.id, 0, 14) > 0.88) h += 0.16 * Math.min(1, 2.2 * Math.max(0, 1 - c.d1 / (2 + 3.5 * hash(c.id, 1, 14))));   // 小石子：小而实，不是一圈虚的
    } else {
      const P = ROCK[tier];
      const wx = x + P.warp * 2 * (fbm(x * 0.007, y * 0.007, 20 + tier) - 0.47), wy = y + P.warp * 2 * (fbm(x * 0.007 + 9, y * 0.007, 21 + tier) - 0.47);
      const c = cells(wx, wy, P.size, P.squash, 30 + tier);
      const tx = hash(c.id, 2, 40) - 0.5, ty = hash(c.id, 3, 40) - 0.5;
      h += P.tone * 2 * (hash(c.id, 4, 40) - 0.5) + P.tilt * ((wx - c.cx) * tx + (wy - c.cy) * ty) / P.size;   // 每一块深浅、朝向略有不同
      h += P.rough * 2 * (fbm(x * 0.05, y * 0.05, 50 + tier) - 0.47) + P.rough * (fbm(x * 0.14, y * 0.14, 51 + tier) - 0.47);
      h -= 0.05 * (1 - Math.min(1, c.edge / 9));                                                           // 块的边缘略微磨圆
      const show = sm(1 - P.show - 0.08, 1 - P.show + 0.08, fbm(x * 0.011, y * 0.011, 55 + tier) * 1.06);  // 裂缝断断续续，不是一张网
      h -= P.crackD * (1 - Math.min(1, c.edge / P.crackW)) * show;
      if (tier === 3) {
        // 熔岩层：几条弯曲的岩浆脉，越深越亮越宽；靠近井底的裂缝也透出红光
        const d2 = depth * depth;
        const lava = Math.pow(vein(x, y, 0.0055, 60, 1.6 + 2.6 * depth), 2.6) * sm(0.36, 0.52, fbm(x * 0.006 + 5, y * 0.006, 61)) * (0.12 + 1.15 * d2);
        const seam = Math.max(0, 1 - c.edge / 3) * show * sm(0.5, 1.0, depth) * 0.75;
        const glow = Math.min(1.2, lava + seam);
        h -= 0.2 * Math.min(1, lava * 2);
        E[i * 3] = glow; E[i * 3 + 1] = glow * (0.3 + 0.32 * glow); E[i * 3 + 2] = glow * 0.06;
      } else if (tier === 2) {
        // 晶洞层：两种颜色的弯曲矿脉，各占一些地方；另外零星嵌着小晶片
        // 矿脉要淡、要断：只在少数地方露出一小段，不能连成一道道闪电
        const cy = 0.5 * Math.pow(vein(x, y, 0.006, 62, 0.9), 2.2) * sm(0.52, 0.6, fbm(x * 0.009, y * 0.009, 63));
        const pk = 0.5 * Math.pow(vein(x, y, 0.006, 68, 0.9), 2.2) * sm(0.54, 0.62, fbm(x * 0.009 + 7, y * 0.009, 69));
        const g = cells(x, y, 26, 1, 64), chip = hash(g.id, 0, 65) > 0.9 ? Math.max(0, 1 - g.d1 / (1.4 + 1.6 * hash(g.id, 1, 65))) : 0;
        E[i * 3] = 0.2 * cy + 0.85 * pk + 0.5 * chip; E[i * 3 + 1] = 0.8 * cy + 0.35 * pk + 0.8 * chip; E[i * 3 + 2] = 0.9 * cy + 0.9 * pk + chip;
      } else {
        // 岩石层：极少量闪光的矿点
        const g = cells(x, y, 40, 1, 65), chip = hash(g.id, 0, 66) > 0.94 ? Math.max(0, 1 - g.d1 / 1.7) : 0;
        E[i * 3] = chip * 0.9; E[i * 3 + 1] = chip * 0.8; E[i * 3 + 2] = chip * 0.55;
      }
    }
    const f = Math.min(1, (y - SURF) / 26);                  // 地面线附近渐渐过渡到没有纹理
    Hm[i] = 0.5 + (h - 0.5) * f;
    E[i * 3] *= f; E[i * 3 + 1] *= f; E[i * 3 + 2] *= f;
  }
  const at = (x, y) => Hm[Math.max(0, Math.min(H - 1, y)) * W + Math.max(0, Math.min(W - 1, x))];
  const detail = newImg(W, H), normal = newImg(W, H), emis = newImg(W, H);
  const k = [7, 9, 9, 9][tier];                            // 凹凸的强度
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const h = at(x, y);
    const gx = (at(x + 1, y - 1) + 2 * at(x + 1, y) + at(x + 1, y + 1) - at(x - 1, y - 1) - 2 * at(x - 1, y) - at(x - 1, y + 1)) / 8;
    const gy = (at(x - 1, y + 1) + 2 * at(x, y + 1) + at(x + 1, y + 1) - at(x - 1, y - 1) - 2 * at(x, y - 1) - at(x + 1, y - 1)) / 8;
    let nx = -gx * k, ny = -gy * k, nz = 1; const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l;
    setPx(normal, x, y, [Math.round((nx * 0.5 + 0.5) * 255), Math.round((-ny * 0.5 + 0.5) * 255), Math.round((nz * 0.5 + 0.5) * 255)]);
    // 明暗细节：以 0.5 为"不变"，凹的地方暗、凸的地方亮，再带一点颗粒
    const grain = y >= SURF ? (vnoise(x * 0.7, y * 0.7, 70 + tier) - 0.5) * 0.06 : 0;
    const d = Math.max(0, Math.min(1, 0.5 + (h - 0.5) * 1.3 + grain));
    const v = Math.round(d * 255); setPx(detail, x, y, [v, v, v]);
    const i = y * W + x;
    setPx(emis, x, y, [Math.round(Math.min(1, E[i * 3]) * 255), Math.round(Math.min(1, E[i * 3 + 1]) * 255), Math.round(Math.min(1, E[i * 3 + 2]) * 255)]);
  }
  emitPlain('relief_' + tier, detail);
  emitPlain('relief_' + tier + '_n', normal, true);
  emitPlain('relief_' + tier + '_e', emis);
}
for (const t of [0, 1, 2, 3]) { gen(t); console.log('生成第 ' + t + ' 层的井壁质地'); }
