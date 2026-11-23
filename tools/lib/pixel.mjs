// 像素图处理的公共函数：色板、压色、缩放、去底、描边、法线贴图。
// 图片统一表示成 { w, h, data: Uint8Array(RGBA) }。

/* ───────── 全游戏共用色板（48 色，风格说明 5.4 节） ───────── */
export const PALETTE_HEX = [
  // 冷色岩石（蓝灰，10）
  '#0b0d14', '#141824', '#1e2434', '#2b3348', '#3b4660', '#55627c', '#76839a', '#a0abbc', '#cfd6df', '#f4f1e6',
  // 土和木头（8）
  '#1c1210', '#2e1c16', '#47291d', '#683c26', '#8e5632', '#b47a45', '#d6a565', '#ecd29a',
  // 金（6）
  '#5a3410', '#8f5a14', '#c68a1a', '#f0b828', '#ffdc55', '#fff4a8',
  // 火和暖光（4）
  '#7a1f12', '#b5361a', '#e3602a', '#f8943a',
  // 红（红宝石、红队，4）
  '#5c0f24', '#a0183a', '#dc3250', '#ff7a8a',
  // 青蓝（晶石、蓝队，5）
  '#0e2a4a', '#17508a', '#2a86c8', '#58c4e8', '#b4f0f8',
  // 绿（绿队，4）
  '#123a2a', '#1f6a3c', '#46a84e', '#9adc6a',
  // 紫和粉（晶洞、紫队，5）
  '#2a1646', '#522a80', '#8a4cc0', '#c48af0', '#f0a8d8',
  // 肤色（2）
  '#c9805a', '#f0c090',
];
export const RAMP = {
  rock: ['#0b0d14', '#141824', '#1e2434', '#2b3348', '#3b4660', '#55627c', '#76839a', '#a0abbc', '#cfd6df'],
  wood: ['#1c1210', '#2e1c16', '#47291d', '#683c26', '#8e5632', '#b47a45', '#d6a565', '#ecd29a'],
  gold: ['#5a3410', '#8f5a14', '#c68a1a', '#f0b828', '#ffdc55', '#fff4a8'],
  gem: ['#0e2a4a', '#17508a', '#2a86c8', '#58c4e8', '#b4f0f8', '#f4f1e6'],
  red: ['#5c0f24', '#a0183a', '#dc3250', '#ff7a8a'],
};

export const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const lin = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
export function oklab(r, g, b) {
  r = lin(r); g = lin(g); b = lin(b);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s];
}
const PAL = PALETTE_HEX.map(h => { const c = hex(h); return { rgb: c, lab: oklab(...c) }; });
const cache = new Map();
// 找色板里最接近的颜色，返回下标。按 OKLab 距离，亮度权重略高，免得暗部串色
export function nearestIndex(r, g, b) {
  const key = (r << 16) | (g << 8) | b;
  let i = cache.get(key);
  if (i !== undefined) return i;
  const [L, A, B] = oklab(r, g, b);
  let best = 0, bd = Infinity;
  for (let k = 0; k < PAL.length; k++) {
    const p = PAL[k].lab, d = 1.4 * (L - p[0]) ** 2 + (A - p[1]) ** 2 + (B - p[2]) ** 2;
    if (d < bd) { bd = d; best = k; }
  }
  cache.set(key, best);
  return best;
}
export const paletteRGB = i => PAL[i].rgb;

/* ───────── 基本操作 ───────── */
export const newImg = (w, h) => ({ w, h, data: new Uint8Array(w * h * 4) });
export function setPx(img, x, y, c, a = 255) {
  if (x < 0 || y < 0 || x >= img.w || y >= img.h) return;
  const o = (y * img.w + x) * 4, rgb = typeof c === 'string' ? hex(c) : c;
  img.data[o] = rgb[0]; img.data[o + 1] = rgb[1]; img.data[o + 2] = rgb[2]; img.data[o + 3] = a;
}
export const alphaAt = (img, x, y) => (x < 0 || y < 0 || x >= img.w || y >= img.h) ? 0 : img.data[(y * img.w + x) * 4 + 3];
export function crop(img, x0, y0, w, h) {
  const out = newImg(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const sx = x + x0, sy = y + y0;
    if (sx < 0 || sy < 0 || sx >= img.w || sy >= img.h) continue;
    out.data.set(img.data.subarray((sy * img.w + sx) * 4, (sy * img.w + sx) * 4 + 4), (y * w + x) * 4);
  }
  return out;
}
export function blit(dst, src, dx, dy) {
  for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
    const o = (y * src.w + x) * 4;
    if (src.data[o + 3] < 128) continue;
    setPx(dst, dx + x, dy + y, [src.data[o], src.data[o + 1], src.data[o + 2]], 255);
  }
}
export function upscale(img, k) {
  const out = newImg(img.w * k, img.h * k);
  for (let y = 0; y < out.h; y++) for (let x = 0; x < out.w; x++)
    out.data.set(img.data.subarray((((y / k) | 0) * img.w + ((x / k) | 0)) * 4, (((y / k) | 0) * img.w + ((x / k) | 0)) * 4 + 4), (y * out.w + x) * 4);
  return out;
}
export function bbox(img, thr = 128) {
  let x0 = img.w, y0 = img.h, x1 = -1, y1 = -1;
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) if (img.data[(y * img.w + x) * 4 + 3] >= thr) {
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  return x1 < 0 ? null : { x0, y0, x1, y1, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

// 整数倍缩小（比如 512 → 256）。颜色按不透明度加权平均，边缘保持柔和，不压色板
export function shrink(img, k) {
  if (k <= 1) return img;
  const w = Math.floor(img.w / k), h = Math.floor(img.h / k), out = newImg(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let r = 0, g = 0, b = 0, a = 0;
    for (let j = 0; j < k; j++) for (let i = 0; i < k; i++) {
      const o = ((y * k + j) * img.w + x * k + i) * 4, al = img.data[o + 3];
      r += img.data[o] * al; g += img.data[o + 1] * al; b += img.data[o + 2] * al; a += al;
    }
    const d = (y * w + x) * 4;
    if (a > 0) { out.data[d] = Math.round(r / a); out.data[d + 1] = Math.round(g / a); out.data[d + 2] = Math.round(b / a); }
    out.data[d + 3] = Math.round(a / (k * k));
  }
  return out;
}

/* ───────── 去底：图片没有透明通道时，从四边往里把背景色抠掉 ───────── */
export function removeBackground(img, tol = 34) {
  const { w, h, data } = img;
  let transparent = 0;
  for (let i = 3; i < data.length; i += 4) if (data[i] < 128) transparent++;
  if (transparent > w * h * 0.01) return { img, how: '原图自带透明底' };
  // 四边的颜色聚成最多两类（纯色底是一类，假的棋盘格透明底是两类）
  const border = [];
  for (let x = 0; x < w; x++) { border.push(x, w * (h - 1) + x); }
  for (let y = 0; y < h; y++) { border.push(y * w, y * w + w - 1); }
  const cols = border.map(i => [data[i * 4], data[i * 4 + 1], data[i * 4 + 2]]);
  let c1 = cols[0], c2 = cols.reduce((far, c) => dist(c, c1) > dist(far, c1) ? c : far, cols[0]);
  for (let it = 0; it < 6; it++) {
    const s1 = [0, 0, 0, 0], s2 = [0, 0, 0, 0];
    for (const c of cols) { const s = dist(c, c1) <= dist(c, c2) ? s1 : s2; s[0] += c[0]; s[1] += c[1]; s[2] += c[2]; s[3]++; }
    if (s1[3]) c1 = [s1[0] / s1[3], s1[1] / s1[3], s1[2] / s1[3]];
    if (s2[3]) c2 = [s2[0] / s2[3], s2[1] / s2[3], s2[2] / s2[3]];
  }
  const isBg = i => { const c = [data[i * 4], data[i * 4 + 1], data[i * 4 + 2]]; return dist(c, c1) < tol || dist(c, c2) < tol; };
  const bad = cols.filter(c => dist(c, c1) >= tol && dist(c, c2) >= tol).length;
  if (bad > cols.length * 0.25) return { img, how: '四边颜色太杂，认不出背景，没有去底' };
  const out = { w, h, data: new Uint8Array(data) }, seen = new Uint8Array(w * h), stack = [];
  for (const i of border) if (!seen[i] && isBg(i)) { seen[i] = 1; stack.push(i); }
  while (stack.length) {
    const i = stack.pop(); out.data[i * 4 + 3] = 0;
    const x = i % w, y = (i / w) | 0;
    for (const [nx, ny] of [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]) {
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      const j = ny * w + nx;
      if (!seen[j] && isBg(j)) { seen[j] = 1; stack.push(j); }
    }
  }
  return { img: out, how: dist(c1, c2) > tol ? '按棋盘格底去底' : '按纯色底去底' };
}
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);

/* ───────── 缩到目标像素尺寸并压到色板 ─────────
   把原图的 sw×sh 区域（左上角 sx,sy）映射到 tw×th 个格子。
   mode='mode'：每个格子取出现最多的色板色（像素感强，适合物件）
   mode='avg' ：每个格子取平均色再压色，可选抖动（适合大背景） */
export function pixelate(img, sx, sy, sw, sh, tw, th, { mode = 'mode', dither = 0, keepAlpha = true } = {}) {
  const out = newImg(tw, th), fx = sw / tw, fy = sh / th;
  const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  for (let ty = 0; ty < th; ty++) for (let tx = 0; tx < tw; tx++) {
    const x0 = Math.floor(sx + tx * fx), x1 = Math.max(x0 + 1, Math.floor(sx + (tx + 1) * fx));
    const y0 = Math.floor(sy + ty * fy), y1 = Math.max(y0 + 1, Math.floor(sy + (ty + 1) * fy));
    let n = 0, opaque = 0, r = 0, g = 0, b = 0;
    const votes = new Map();
    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
      n++;
      if (x < 0 || y < 0 || x >= img.w || y >= img.h) continue;
      const o = (y * img.w + x) * 4, a = img.data[o + 3];
      if (keepAlpha && a < 128) continue;
      opaque++; r += img.data[o]; g += img.data[o + 1]; b += img.data[o + 2];
      if (mode === 'mode') { const k = nearestIndex(img.data[o], img.data[o + 1], img.data[o + 2]); votes.set(k, (votes.get(k) || 0) + 1); }
    }
    if (opaque * 2 < n || !opaque) continue;                 // 不到一半有东西，这格留空：像素要么有要么没有
    r /= opaque; g /= opaque; b /= opaque;
    let idx;
    if (mode === 'mode') {
      let best = -1, bc = -1;
      for (const [k, c] of votes) if (c > bc) { bc = c; best = k; }
      idx = bc >= opaque * 0.34 ? best : nearestIndex(Math.round(r), Math.round(g), Math.round(b));   // 没有明显的多数色就退回平均色
    } else {
      const d = dither ? (BAYER[(ty & 3) * 4 + (tx & 3)] / 16 - 0.47) * dither : 0;
      const cl = v => Math.max(0, Math.min(255, Math.round(v + d)));
      idx = nearestIndex(cl(r), cl(g), cl(b));
    }
    setPx(out, tx, ty, paletteRGB(idx));
  }
  return out;
}

// 把已经是目标尺寸的图直接压到色板（占位图用）
export function quantize(img) {
  const out = newImg(img.w, img.h);
  for (let i = 0; i < img.w * img.h; i++) {
    if (img.data[i * 4 + 3] < 128) continue;
    const c = paletteRGB(nearestIndex(img.data[i * 4], img.data[i * 4 + 1], img.data[i * 4 + 2]));
    out.data[i * 4] = c[0]; out.data[i * 4 + 1] = c[1]; out.data[i * 4 + 2] = c[2]; out.data[i * 4 + 3] = 255;
  }
  return out;
}

// 给物件补一圈深色轮廓：贴着透明的那一圈像素，如果不够暗，就换成同色系更深的颜色（不用纯黑）
export function darkenOutline(img, factor = 0.5) {
  const out = { w: img.w, h: img.h, data: new Uint8Array(img.data) };
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) {
    if (alphaAt(img, x, y) < 128) continue;
    if (alphaAt(img, x - 1, y) >= 128 && alphaAt(img, x + 1, y) >= 128 && alphaAt(img, x, y - 1) >= 128 && alphaAt(img, x, y + 1) >= 128) continue;
    const o = (y * img.w + x) * 4, r = img.data[o], g = img.data[o + 1], b = img.data[o + 2];
    if (0.299 * r + 0.587 * g + 0.114 * b < 70) continue;
    const c = paletteRGB(nearestIndex(Math.round(r * factor), Math.round(g * factor), Math.round(b * factor)));
    out.data[o] = c[0]; out.data[o + 1] = c[1]; out.data[o + 2] = c[2];
  }
  return out;
}

/* ───────── 法线贴图 ─────────
   高度 = 轮廓往里鼓起来的"包"（按离边缘的距离）+ 亮度细节；再按高度的坡度算法线。
   opaque=true 用于整张不透明的背景，只按亮度算凹凸。
   编码按 Godot 的约定：R 朝右为亮，G 朝上为亮，B 朝外。 */
export function makeNormal(img, { bulge = 1, detail = 0.5, strength = 1.6, opaque = false, smooth = 0 } = {}) {
  const { w, h, data } = img, N = w * h;
  const mask = new Uint8Array(N), luma = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    mask[i] = opaque || data[i * 4 + 3] >= 128 ? 1 : 0;
    luma[i] = (0.299 * data[i * 4] + 0.587 * data[i * 4 + 1] + 0.114 * data[i * 4 + 2]) / 255;
  }
  for (let pass = 0; pass < smooth; pass++) {          // 额外的平滑（大背景用）
    const src = Float32Array.from(luma);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      let s = 0, n = 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        s += src[yy * w + xx]; n++;
      }
      luma[y * w + x] = s / n;
    }
  }
  const H = new Float32Array(N);
  if (!opaque) {
    // 两遍扫描的近似距离变换：每个不透明像素到最近透明像素（或图片边界外）的距离
    const d = new Float32Array(N).fill(1e9), at = (x, y) => (x < 0 || y < 0 || x >= w || y >= h) ? 0 : (mask[y * w + x] ? d[y * w + x] : 0);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x; if (!mask[i]) { d[i] = 0; continue; }
      d[i] = Math.min(d[i], at(x - 1, y) + 1, at(x, y - 1) + 1, at(x - 1, y - 1) + 1.414, at(x + 1, y - 1) + 1.414);
    }
    let maxd = 0;
    for (let y = h - 1; y >= 0; y--) for (let x = w - 1; x >= 0; x--) {
      const i = y * w + x; if (!mask[i]) continue;
      d[i] = Math.min(d[i], at(x + 1, y) + 1, at(x, y + 1) + 1, at(x + 1, y + 1) + 1.414, at(x - 1, y + 1) + 1.414);
      if (d[i] > maxd) maxd = d[i];
    }
    const R = Math.max(2, maxd);
    for (let i = 0; i < N; i++) {
      if (!mask[i]) { H[i] = -0.6; continue; }
      const t = Math.min(1, (d[i] - 0.5) / R), dome = Math.sqrt(Math.max(0, 1 - (1 - t) * (1 - t)));
      H[i] = bulge * dome * R * 0.75;
    }
  }
  // 亮度细节：先做一次 3×3 平滑，免得每个像素一个方向
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x; if (!mask[i]) continue;
    let s = 0, n = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const xx = x + dx, yy = y + dy;
      if (xx < 0 || yy < 0 || xx >= w || yy >= h || !mask[yy * w + xx]) continue;
      const wgt = dx === 0 && dy === 0 ? 2 : 1; s += luma[yy * w + xx] * wgt; n += wgt;
    }
    H[i] += detail * (s / n) * 3.0;
  }
  const out = newImg(w, h), hat = (x, y) => H[Math.max(0, Math.min(h - 1, y)) * w + Math.max(0, Math.min(w - 1, x))];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const o = (y * w + x) * 4;
    if (!mask[y * w + x]) { out.data[o] = 128; out.data[o + 1] = 128; out.data[o + 2] = 255; out.data[o + 3] = 255; continue; }
    const gx = (hat(x + 1, y - 1) + 2 * hat(x + 1, y) + hat(x + 1, y + 1) - hat(x - 1, y - 1) - 2 * hat(x - 1, y) - hat(x - 1, y + 1)) / 8;
    const gy = (hat(x - 1, y + 1) + 2 * hat(x, y + 1) + hat(x + 1, y + 1) - hat(x - 1, y - 1) - 2 * hat(x, y - 1) - hat(x + 1, y - 1)) / 8;
    let nx = -gx * strength, ny = -gy * strength, nz = 1;
    const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l;
    out.data[o] = Math.round((nx * 0.5 + 0.5) * 255);
    out.data[o + 1] = Math.round((-ny * 0.5 + 0.5) * 255);     // 屏幕上 y 朝下，法线贴图里朝上为亮
    out.data[o + 2] = Math.round((nz * 0.5 + 0.5) * 255);
    out.data[o + 3] = 255;
  }
  return out;
}

/* ───────── 随机数和噪声（占位图用，固定种子，每次生成结果一样） ───────── */
export function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const h2 = (x, y, s) => { let n = Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(s, 2147483647); n = Math.imul(n ^ (n >>> 13), 1274126177); return ((n ^ (n >>> 16)) >>> 0) / 4294967296; };
export function vnoise(x, y, s = 0) {
  const xi = Math.floor(x), yi = Math.floor(y), fx = x - xi, fy = y - yi, u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
  const a = h2(xi, yi, s), b = h2(xi + 1, yi, s), c = h2(xi, yi + 1, s), d = h2(xi + 1, yi + 1, s);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
export function fbm(x, y, s = 0, oct = 4) {
  let v = 0, amp = 0.5, f = 1;
  for (let i = 0; i < oct; i++) { v += amp * vnoise(x * f, y * f, s + i * 17); amp *= 0.5; f *= 2; }
  return v;
}
