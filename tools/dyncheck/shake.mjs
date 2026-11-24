// node shake.mjs 帧目录 —— 相邻帧整屏平移（震屏）检测：用左侧墙面找让差最小的平移量
import fs from 'node:fs';
import { loadImage } from '../lib/png.mjs';
const dir = process.argv[2]; const files = fs.readdirSync(dir).filter(f => /^\d+\.png$/.test(f)).sort();
const ims = files.map(f => loadImage(dir + '/' + f)); const W = ims[0].w, H = ims[0].h; const y0 = Math.round(H * 0.37), y1 = Math.round(H * 0.92); let moved = 0; const out = [];
for (let k = 1; k < ims.length; k++) { let best = [0, 0, 1e18];
  for (let dy = -6; dy <= 6; dy++) for (let dx = -6; dx <= 6; dx++) { let s = 0; for (let y = y0; y < y1; y += 4) for (let x = 20; x < 300; x += 4) { const p = (y * W + x) * 4, q = ((y + dy) * W + x + dx) * 4; s += Math.abs(ims[k].data[p] - ims[k - 1].data[q]); } if (s < best[2]) best = [dx, dy, s]; }
  if (best[0] || best[1]) { moved++; out.push(`${k}:${best[0]},${best[1]}`); } }
console.log(`震屏：${moved}/${ims.length - 1} 对相邻帧有整屏平移` + (moved ? '（这段的墙面数字只作参考）' : ''), out.slice(0, 10).join(' '));
