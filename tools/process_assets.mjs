#!/usr/bin/env node
// 素材处理：把 raw/ 里的图变成游戏能用的。
//   物件（矿物、钩爪、矿工）：缩到合适的大小，生成法线贴图（_n），写进 art/，连同 Godot 的导入配置和贴图资源。
//   头像、图标、标题：只缩小。
//   背景：原样用，导入时有损压缩。
// 用法：node tools/process_assets.mjs              处理 raw/ 里所有认识的图
//       node tools/process_assets.mjs gold_s lamp  只处理指定的几张
// 文件名（不含扩展名）要和 素材清单.md 里的一致，规格在 tools/lib/spec.mjs。
import fs from 'node:fs';
import path from 'node:path';
import { loadImage } from './lib/png.mjs';
import { shrink, bbox } from './lib/pixel.mjs';
import { emitAsset, ROOT } from './lib/emit.mjs';
import { SPEC } from './lib/spec.mjs';

const SRC = path.join(ROOT, 'raw');
const only = process.argv.slice(2).filter(a => !a.startsWith('--'));
const files = fs.readdirSync(SRC).filter(f => /\.(png|jpe?g|webp)$/i.test(f));
const seen = new Set(), unknown = [];
let ok = 0, bad = 0;
for (const f of files) {
  const name = path.basename(f, path.extname(f)).toLowerCase(), spec = SPEC[name];
  if (!spec) { unknown.push(f); continue; }
  seen.add(name);
  if (only.length && !only.includes(name)) continue;
  try {
    const src = loadImage(path.join(SRC, f));
    const notes = [`原图 ${src.w}×${src.h}`];
    if (spec.kind === 'bg') {
      if (Math.abs(src.w / src.h - 16 / 9) > 0.02) notes.push('⚠ 不是 16:9，游戏里会被拉伸');
      emitAsset(name, src, {}, { normal: false, lossy: spec.lossy });
    } else {
      const img = shrink(src, spec.shrink), bb = bbox(img);
      if (!bb) throw new Error('整张图都是透明的');
      notes.push(`进游戏 ${img.w}×${img.h}，主体 ${bb.w}×${bb.h}`);
      if (bb.x0 < 2 || bb.y0 < 2 || bb.x1 > img.w - 3) notes.push('⚠ 主体贴着图的边，描边光会被切掉');
      emitAsset(name, img, spec.normal, { hd: true, normal: spec.kind === 'hd' ? undefined : false });
    }
    ok++; console.log(`✔ ${name}：${notes.join('；')}`);
  } catch (e) { bad++; console.log(`✘ ${name}：${e.message}`); }
}
const missing = Object.keys(SPEC).filter(n => !seen.has(n) && !SPEC[n].optional), todo = Object.keys(SPEC).filter(n => !seen.has(n) && SPEC[n].optional);
console.log(`处理了 ${ok} 张，失败 ${bad} 张。`);
if (missing.length) console.log('清单里有、raw/ 里没有：' + missing.join('、'));
if (todo.length) console.log('还没出的图（没有也能跑）：' + todo.join('、'));
if (unknown.length) console.log('raw/ 里有、清单里没有（没处理）：' + unknown.join('、'));
