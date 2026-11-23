// PNG 读写，只用 Node 自带模块。图片统一表示成 { w, h, data: Uint8Array(RGBA) }。
import zlib from 'node:zlib';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td) >>> 0);
  return Buffer.concat([len, td, crc]);
}

export function encodePNG(img) {
  const { w, h, data } = img;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    Buffer.from(data.buffer, data.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  }
  return Buffer.concat([SIG, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

export function decodePNG(buf) {
  if (buf.subarray(0, 8).compare(SIG) !== 0) throw new Error('不是 PNG');
  let p = 8, w = 0, h = 0, depth = 0, ctype = 0, interlace = 0, plte = null, trns = null;
  const idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p), type = buf.toString('ascii', p + 4, p + 8), d = buf.subarray(p + 8, p + 8 + len);
    p += 12 + len;
    if (type === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); depth = d[8]; ctype = d[9]; interlace = d[12]; }
    else if (type === 'PLTE') plte = d;
    else if (type === 'tRNS') trns = d;
    else if (type === 'IDAT') idat.push(d);
    else if (type === 'IEND') break;
  }
  if (interlace) throw new Error('隔行扫描的 PNG');
  const ch = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ctype];
  if (!ch) throw new Error('不认识的 PNG 颜色类型 ' + ctype);
  const bpp = Math.max(1, (ch * depth) >> 3), rowBytes = Math.ceil(w * ch * depth / 8);
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const px = Buffer.alloc(rowBytes * h);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (rowBytes + 1)], src = y * (rowBytes + 1) + 1, dst = y * rowBytes;
    for (let x = 0; x < rowBytes; x++) {
      const a = x >= bpp ? px[dst + x - bpp] : 0, b = y > 0 ? px[dst - rowBytes + x] : 0, c = x >= bpp && y > 0 ? px[dst - rowBytes + x - bpp] : 0;
      let v = raw[src + x];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const q = a + b - c, pa = Math.abs(q - a), pb = Math.abs(q - b), pc = Math.abs(q - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      px[dst + x] = v & 255;
    }
  }
  const out = new Uint8Array(w * h * 4);
  const sample = (row, i) => {              // 取第 i 个通道值，归一到 0..255
    if (depth === 8) return px[row + i];
    if (depth === 16) return px[row + i * 2];
    const bit = i * depth, byte = px[row + (bit >> 3)], v = (byte >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
    return ctype === 3 ? v : Math.round(v * 255 / ((1 << depth) - 1));
  };
  for (let y = 0; y < h; y++) {
    const row = y * rowBytes;
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 4;
      if (ctype === 6) { out[o] = sample(row, x * 4); out[o + 1] = sample(row, x * 4 + 1); out[o + 2] = sample(row, x * 4 + 2); out[o + 3] = sample(row, x * 4 + 3); }
      else if (ctype === 2) {
        const r = sample(row, x * 3), g = sample(row, x * 3 + 1), b = sample(row, x * 3 + 2);
        out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = 255;
        if (trns && depth === 8 && trns.length >= 6 && r === trns[1] && g === trns[3] && b === trns[5]) out[o + 3] = 0;
      } else if (ctype === 0) { const v = sample(row, x); out[o] = out[o + 1] = out[o + 2] = v; out[o + 3] = 255; }
      else if (ctype === 4) { const v = sample(row, x * 2); out[o] = out[o + 1] = out[o + 2] = v; out[o + 3] = sample(row, x * 2 + 1); }
      else { const i = sample(row, x); out[o] = plte[i * 3]; out[o + 1] = plte[i * 3 + 1]; out[o + 2] = plte[i * 3 + 2]; out[o + 3] = trns && i < trns.length ? trns[i] : 255; }
    }
  }
  return { w, h, data: out };
}

export function savePNG(file, img) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, encodePNG(img));
}

// 读任意常见格式。不是标准 PNG 的（jpg、webp、隔行 PNG 等）先用 macOS 自带的 sips 转成 PNG。
export function loadImage(file) {
  const buf = fs.readFileSync(file);
  try { return decodePNG(buf); } catch (e) {
    const tmp = path.join(os.tmpdir(), 'dm_' + process.pid + '_' + Date.now() + '.png');
    try {
      execFileSync('sips', ['-s', 'format', 'png', file, '--out', tmp], { stdio: 'ignore' });
      return decodePNG(fs.readFileSync(tmp));
    } catch (e2) { throw new Error('读不了图片 ' + file + '：' + e.message + ' / ' + e2.message); }
    finally { try { fs.unlinkSync(tmp); } catch {} }
  }
}
