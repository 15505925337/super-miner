// node flicker3.mjs 帧目录 —— 找"来回跳"的块：块均值相邻变化 |d|>2 且正负号反转 ≥4 次（井内）
import fs from 'node:fs';
import { loadImage } from '../lib/png.mjs';
const dir = process.argv[2]; const files = fs.readdirSync(dir).filter(f => /^\d+\.png$/.test(f)).sort();
const ims = files.map(f => loadImage(dir + '/' + f)); const W = ims[0].w, H = ims[0].h, B = 32, bw = Math.floor(W / B), bh = Math.floor(H / B);
const BMs = ims.map(im => { const m = new Float32Array(bw * bh); for (let by = 0; by < bh; by++) for (let bx = 0; bx < bw; bx++) { let s = 0; for (let y = 0; y < B; y += 2) for (let x = 0; x < B; x += 2) { const p = ((by * B + y) * W + bx * B + x) * 4; s += 0.299 * im.data[p] + 0.587 * im.data[p + 1] + 0.114 * im.data[p + 2]; } m[by * bw + bx] = s / (B * B / 4); } return m; });
const yMin = Math.ceil(Math.round(H * 260 / 1080) / B); const sus = [];
for (let by = yMin; by < bh; by++) for (let bx = 0; bx < bw; bx++) { const i = by * bw + bx; let flips = 0, last = 0, big = 0;
  for (let k = 1; k < BMs.length; k++) { const d = BMs[k][i] - BMs[k - 1][i]; if (Math.abs(d) > 2) { big++; const sg = Math.sign(d); if (last && sg !== last) flips++; last = sg; } }
  if (flips >= 4) sus.push(`${bx * B},${by * B}(反转${flips}/大变化${big})`); }
console.log(`来回跳的块 ${sus.length} 个`, sus.slice(0, 15).join(' '));
