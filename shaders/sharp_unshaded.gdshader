// 钩爪和开箱弹图沿用井内物件的锐利采样，颜色由各自的显示逻辑控制。
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/sharp_sampling.gdshaderinc"

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	COLOR = textureGrad(TEXTURE, sharp_uv(UV, TEXTURE_PIXEL_SIZE, dx, dy), dx, dy) * tint;
}
