#!/usr/bin/env node
// 临时占位图：第三期合作玩法加了"钥匙"和"宝箱"两样东西，正式图还没有。
// raw/ 里已经有同名的正式图就什么都不做（正式图由 process_assets.mjs 处理）；没有才画一张简单的顶上。
// 用法：node tools/gen_placeholder.mjs
import fs from 'node:fs';
import path from 'node:path';
import { newImg, setPx, alphaAt, upscale } from './lib/pixel.mjs';
import { emitAsset, ROOT } from './lib/emit.mjs';
import { SPEC } from './lib/spec.mjs';

const G = 128, INK = [58, 34, 20];
const rect = (x0, y0, x1, y1) => (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
const ring = (cx, cy, r1, r0 = 0) => (x, y) => { const d = Math.hypot(x - cx, y - cy); return d <= r1 && d >= r0; };
const round = (x0, y0, x1, y1, r) => (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1 &&
  !((x < x0 + r && y < y0 + r && Math.hypot(x - x0 - r, y - y0 - r) > r) || (x > x1 - r && y < y0 + r && Math.hypot(x - x1 + r, y - y0 - r) > r));
const WOOD = [150, 92, 44], WOOD2 = [178, 114, 56], GOLD = [236, 186, 70], GOLD2 = [252, 222, 120], DARK = [40, 24, 14];
const SHAPES = {
  chest: [
    [round(20, 34, 108, 58, 12), WOOD2], [rect(22, 58, 106, 104), WOOD],
    [rect(34, 36, 42, 104), GOLD], [rect(86, 36, 94, 104), GOLD], [rect(20, 55, 108, 60), GOLD],
    [rect(57, 50, 71, 70), GOLD2], [ring(64, 58, 2.6), DARK], [rect(63, 59, 65, 66), DARK],
  ],
  key: [
    [ring(64, 34, 20, 9), GOLD], [rect(59, 52, 69, 108), GOLD], [rect(69, 84, 84, 92), GOLD], [rect(69, 98, 80, 106), GOLD],
    [rect(59, 52, 61, 108), GOLD2], [ring(64, 34, 20, 17), GOLD2],
  ],
};
for (const name of Object.keys(SHAPES)) {
  if (['.png', '.jpg', '.jpeg', '.webp'].some(e => fs.existsSync(path.join(ROOT, 'raw', name + e)))) { console.log(`${name}：raw/ 里已经有正式图，不画占位图`); continue; }
  const img = newImg(G, G);
  for (let y = 0; y < G; y++) for (let x = 0; x < G; x++) {
    let c = null;
    for (const [inside, color] of SHAPES[name]) if (inside(x, y)) c = color;
    if (c) { const k = 1.12 - 0.3 * y / G; setPx(img, x, y, c.map(v => Math.min(255, Math.round(v * k)))); }
  }
  const out = newImg(G, G); out.data.set(img.data);
  for (let y = 0; y < G; y++) for (let x = 0; x < G; x++) {            // 外面描一圈深色的边
    if (alphaAt(img, x, y) >= 128) continue;
    let near = false;
    for (let j = -2; j <= 2 && !near; j++) for (let i = -2; i <= 2; i++) if (alphaAt(img, x + i, y + j) >= 128) { near = true; break; }
    if (near) setPx(out, x, y, INK);
  }
  emitAsset(name, upscale(out, 2), SPEC[name].normal, { hd: true });
  console.log(`${name}：画了一张占位图（正式图放进 raw/${name}.png 后重跑 process_assets.mjs 即可替换）`);
}
