// node flicker4.mjs 帧目录 —— 井内每个 32×32 块：相邻帧块均值变化的中位数（持续闪烁会抬高中位数），统计分布
import fs from 'node:fs';
import { loadImage } from '../lib/png.mjs';
const dir = process.argv[2]; const files = fs.readdirSync(dir).filter(f => /^\d+\.png$/.test(f)).sort();
const ims = files.map(f => loadImage(dir + '/' + f)); const W = ims[0].w, H = ims[0].h, B = 32, bw = W / B | 0, bh = H / B | 0;
const BM = ims.map(im => { const m = new Float32Array(bw * bh); for (let by = 0; by < bh; by++) for (let bx = 0; bx < bw; bx++) { let s = 0; for (let y = 0; y < B; y += 2) for (let x = 0; x < B; x += 2) { const p = ((by * B + y) * W + bx * B + x) * 4; s += 0.299 * im.data[p] + 0.587 * im.data[p + 1] + 0.114 * im.data[p + 2]; } m[by * bw + bx] = s / 256; } return m; });
const yMin = Math.ceil(260 / B); const med = [], mean = [];
for (let by = yMin; by < bh; by++) for (let bx = 0; bx < bw; bx++) { const i = by * bw + bx; const d = []; for (let k = 1; k < BM.length; k++) d.push(Math.abs(BM[k][i] - BM[k - 1][i])); d.sort((a, b) => a - b); med.push([d[d.length >> 1], bx * B, by * B]); mean.push(d.reduce((a, b) => a + b, 0) / d.length); }
med.sort((a, b) => a[0] - b[0]); const vals = med.map(m => m[0]);
console.log(`块数 ${vals.length}：中位相邻变化 最大 ${vals.at(-1).toFixed(2)}，99% ${vals[Math.floor(vals.length * 0.99)].toFixed(2)}，>1 的块 ${vals.filter(v => v > 1).length}；全部块的平均相邻变化 ${(mean.reduce((a, b) => a + b, 0) / mean.length).toFixed(3)}；最高的块`, med.slice(-3).map(m => `${m[1]},${m[2]}:${m[0].toFixed(2)}`).join(' '));
