// 把一张处理好的像素图写进 Godot 项目：图本身、法线贴图（_n）、两份导入配置、一份带法线的贴图资源（.tres）。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { savePNG } from './png.mjs';
import { makeNormal } from './pixel.mjs';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const ART = path.join(ROOT, 'art');

// 无损、不生成多级缩小图。像素画不能被压缩算法弄糊。
const importText = (name, isNormal, opt = {}) => `[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://art/${name}.png"

[params]

compress/mode=${opt.lossy ? 1 : 0}
compress/high_quality=false
compress/lossy_quality=${opt.lossy || 0.7}
compress/hdr_compression=1
compress/normal_map=${isNormal ? 2 : 0}
compress/channel_pack=0
mipmaps/generate=${opt.mipmaps ? 'true' : 'false'}
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=${isNormal ? 'false' : 'true'}
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
`;

const tresText = (name, filter) => `[gd_resource type="CanvasTexture" load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://art/${name}.png" id="1"]
[ext_resource type="Texture2D" path="res://art/${name}_n.png" id="2"]

[resource]
diffuse_texture = ExtResource("1")
normal_texture = ExtResource("2")
texture_filter = ${filter}
`;

// 导入配置只在没有时才写：Godot 导入后会往里面补内容，覆盖掉会触发重新导入
function writeIfMissing(file, text) { if (!fs.existsSync(file)) fs.writeFileSync(file, text); }

// opt.hd：高清图（平滑缩放，带多级缩小图）；不传就是像素图（最近邻）
// opt.normal === false：不要法线贴图（背景、头像、图标），只写图和导入配置
// opt.lossy：有损压缩的质量（0 到 1），大背景用，省包体
export function emitAsset(name, img, normalOpts = {}, opt = {}) {
  fs.mkdirSync(ART, { recursive: true });
  savePNG(path.join(ART, name + '.png'), img);
  const imp = { mipmaps: !!opt.hd, lossy: opt.lossy };
  writeText(path.join(ART, name + '.png.import'), importText(name, false, imp), opt.hd);
  if (opt.normal === false) return;
  savePNG(path.join(ART, name + '_n.png'), makeNormal(img, normalOpts));
  writeText(path.join(ART, name + '_n.png.import'), importText(name + '_n', true, imp), opt.hd);
  fs.writeFileSync(path.join(ART, name + '.tres'), tresText(name, opt.hd ? 4 : 1));   // 4 = 平滑并用多级缩小图，1 = 最近邻
}
// 导入配置：像素图只在没有时写（Godot 导入后会往里补内容）；高清图的参数不同，参数行对不上就重写
function writeText(file, text, force) {
  if (!fs.existsSync(file)) return fs.writeFileSync(file, text);
  if (!force) return;
  const want = l => /^(compress\/mode|compress\/lossy_quality|mipmaps\/generate)=/.test(l);
  const a = fs.readFileSync(file, 'utf8').split('\n').filter(want).join('|'), b = text.split('\n').filter(want).join('|');
  if (a !== b) fs.writeFileSync(file, text);
}

// 只写一张图和它的导入配置（平滑采样、不要多级缩小图）。程序生成的岩层纹理、凹凸、发光层用
export function emitPlain(name, img, isNormal = false) {
  fs.mkdirSync(ART, { recursive: true });
  savePNG(path.join(ART, name + '.png'), img);
  writeText(path.join(ART, name + '.png.import'), importText(name, isNormal, {}), true);
}
