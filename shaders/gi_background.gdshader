// 画在井壁和支架之后、玩法物件下方。预乘混合同时减去阴影、加上反光。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D resolved_tex : filter_linear, repeat_disable;
uniform float bounce_strength;
uniform float shadow_strength;

void fragment() {
	vec4 light = texture(resolved_tex, UV);
	// 超宽窗的镜像延展区没有玩法物件，靠设计区域边缘淡出。
	vec2 border = min(UV, 1.0 - UV) * vec2(640.0, 360.0);
	float edge = smoothstep(0.0, 6.0, min(border.x, border.y));
	float shade = min(light.a * shadow_strength, 0.32);
	vec3 bounce = min(light.rgb * bounce_strength * 0.45, vec3(0.16));
	COLOR = vec4(bounce * (1.0 - shade), shade) * edge;
}
