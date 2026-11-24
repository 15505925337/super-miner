// RG 保存精度为 1/8 像素的轮廓距离，B 保存内外标记。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D seeds : filter_nearest, repeat_disable;
uniform sampler2D mask_tex : filter_nearest, repeat_disable;
uniform ivec2 design_size;

void fragment() {
	ivec2 cell = ivec2(UV * vec2(design_size));
	vec4 packed_seed = texelFetch(seeds, cell, 0);
	vec2 seed = vec2(dot(packed_seed.rg, vec2(255.0, 65280.0)) - 1.0,
			dot(packed_seed.ba, vec2(255.0, 65280.0)));
	float distance_px = seed.x < -0.5 ? 1024.0 : length(seed - vec2(cell));
	float units = floor(distance_px * 8.0 + 0.5);
	float hi = floor(units / 256.0);
	float solid = step(0.20, texelFetch(mask_tex, cell, 0).r);
	COLOR = vec4((units - hi * 256.0) / 255.0, hi / 255.0, solid, 1.0);
}
