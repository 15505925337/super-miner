// 在原先的柔光中心叠一颗细十字，尖端渐隐。
shader_type canvas_item;
render_mode unshaded, blend_add;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	vec2 rays = (1.0 - smoothstep(vec2(0.02), vec2(0.14), p.yx))
		* (1.0 - smoothstep(vec2(0.08), vec2(1.0, 0.8), p));
	COLOR = vec4(tint.rgb, max(COLOR.a * 0.6, max(rays.x, rays.y) * tint.a));
}
