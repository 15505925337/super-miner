// 加法叠上物件的自发光和金块扫光，沿用主体的采样，光效止于物件边缘。
shader_type canvas_item;
render_mode unshaded, blend_add;

#include "res://shaders/sharp_sampling.gdshaderinc"

uniform vec2 sweep_axis = vec2(0.5);
uniform vec3 sweep = vec3(0.0); // 高光带的位置、强度和宽度倍率
uniform vec4 light_col : source_color = vec4(1.0);

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	COLOR = textureGrad(TEXTURE, sharp_uv(UV, TEXTURE_PIXEL_SIZE, dx, dy), dx, dy) * tint;
	if (sweep.y > 0.0) {
		float diagonal = dot(UV - vec2(0.5), sweep_axis) + 0.5;
		float distance = abs(diagonal - sweep.x) / sweep.z;
		float highlight = 1.0 - smoothstep(0.012, 0.095, distance);
		COLOR.rgb += light_col.rgb * (highlight * sweep.y);
	}
}
