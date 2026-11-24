// node flicker2.mjs 帧目录 —— 静止区域的相邻帧变化：排除"有东西在动"的块（任一相邻帧块均值变化 >15）及其周围 2 圈，只看井内
import fs from 'node:fs';
import { loadImage, savePNG } from '../lib/png.mjs';
const dir = process.argv[2]; const files = fs.readdirSync(dir).filter(f => /^\d+\.png$/.test(f)).sort();
const ims = files.map(f => loadImage(dir + '/' + f)); const W = ims[0].w, H = ims[0].h, B = 32, bw = Math.floor(W / B), bh = Math.floor(H / B);
const lum = im => { const L = new Float32Array(W * H); for (let i = 0; i < W * H; i++) L[i] = 0.299 * im.data[i * 4] + 0.587 * im.data[i * 4 + 1] + 0.114 * im.data[i * 4 + 2]; return L; };
const Ls = ims.map(lum);
const bm = L => { const m = new Float32Array(bw * bh); for (let by = 0; by < bh; by++) for (let bx = 0; bx < bw; bx++) { let s = 0; for (let y = 0; y < B; y++) for (let x = 0; x < B; x++) s += L[(by * B + y) * W + bx * B + x]; m[by * bw + bx] = s / (B * B); } return m; };
const BMs = Ls.map(bm); const mx = new Float32Array(bw * bh); const sum = new Float32Array(bw * bh);
for (let k = 1; k < BMs.length; k++) for (let i = 0; i < bw * bh; i++) { const d = Math.abs(BMs[k][i] - BMs[k - 1][i]); mx[i] = Math.max(mx[i], d); sum[i] += d; }
const moving = new Uint8Array(bw * bh); for (let i = 0; i < bw * bh; i++) if (mx[i] > 15) { const bx = i % bw, by = Math.floor(i / bw); for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) { const x = bx + dx, y = by + dy; if (x >= 0 && y >= 0 && x < bw && y < bh) moving[y * bw + x] = 1; } }
const yMin = Math.ceil(Math.round(H * 260 / 1080) / B);
const keep = []; for (let by = yMin; by < bh; by++) for (let bx = 0; bx < bw; bx++) { const i = by * bw + bx; if (!moving[i]) keep.push(i); }
const vals = keep.map(i => mx[i]).sort((a, b) => a - b); const means = keep.map(i => sum[i] / (BMs.length - 1));
const over = keep.filter(i => mx[i] > 2);
// 逐像素：静止块里的像素，相邻帧 |Δ| 的最大值（去掉每对帧里最大的 0.1% 以排除飘尘单点）
let pxMax = [], pxMean = 0, n = 0;
for (let k = 1; k < Ls.length; k++) { const ds = []; for (const i of keep) { const bx = i % bw, by = Math.floor(i / bw); for (let y = 0; y < B; y += 2) for (let x = 0; x < B; x += 2) { const p = (by * B + y) * W + bx * B + x; const d = Math.abs(Ls[k][p] - Ls[k - 1][p]); ds.push(d); pxMean += d; n++; } } ds.sort((a, b) => a - b); pxMax.push(ds[Math.floor(ds.length * 0.999)]); }
console.log(`静止块 ${keep.length}/${(bh - yMin) * bw}（${(keep.length / ((bh - yMin) * bw) * 100).toFixed(0)}%）：块均值相邻变化 最大 ${vals.at(-1)?.toFixed(2)}，平均 ${(means.reduce((a, b) => a + b, 0) / means.length).toFixed(3)}，>2 的块 ${over.length}；逐像素 99.9 分位的相邻变化 最大 ${Math.max(...pxMax).toFixed(1)}，逐像素平均 ${(pxMean / n).toFixed(3)}`);
if (over.length) console.log('  >2 的块位置（屏幕 x,y）：', over.slice(0, 12).map(i => `${(i % bw) * B},${Math.floor(i / bw) * B}:${mx[i].toFixed(1)}`).join(' '));
