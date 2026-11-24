// node follow.mjs 帧目录 输出 —— 自动找钩子/被拉物件：取相邻帧差最大的区域中心，裁 300×300，连续 16 帧排成 4×4
import fs from 'node:fs';
import { loadImage, savePNG } from '../lib/png.mjs';
const [dir, out, start = '0'] = process.argv.slice(2);
const files = fs.readdirSync(dir).filter(f => /^\d+\.png$/.test(f)).sort().slice(Number(start), Number(start) + 16);
const ims = files.map(f => loadImage(dir + '/' + f)); const W = ims[0].w, H = ims[0].h, w = 300, h = 300, C = 4, R = Math.ceil(ims.length / C);
const D = new Uint8Array((C * (w + 4)) * (R * (h + 4)) * 4).fill(255), DW = C * (w + 4);
ims.forEach((im, j) => {
  // 以与上一帧差别最大的位置为中心（井内），第一帧用第二帧
  const ref = ims[j === 0 ? 1 : j - 1]; let bx = 0, by = 0, best = -1;
  for (let y = 300; y < H - 40; y += 8) for (let x = 0; x < W; x += 8) { const p = (y * W + x) * 4; const d = Math.abs(im.data[p] - ref.data[p]) + Math.abs(im.data[p + 1] - ref.data[p + 1]); if (d > best) { best = d; bx = x; by = y; } }
  const x0 = Math.max(0, Math.min(W - w, bx - w / 2)), y0 = Math.max(0, Math.min(H - h, by - h / 2)); const ox = (j % C) * (w + 4), oy = Math.floor(j / C) * (h + 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const s = ((y0 + y) * W + x0 + x) * 4, t = ((oy + y) * DW + ox + x) * 4; for (let c = 0; c < 4; c++) D[t + c] = im.data[s + c]; }
});
savePNG(out, { w: DW, h: R * (h + 4), data: D }); console.log(out, files[0], '…', files.at(-1));
