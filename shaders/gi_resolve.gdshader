// 用同一帧的 3×3 空间滤波压低软影周围的采样纹路。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_px;
uniform vec2 key_direction = vec2(0.0, 1.0);
uniform float wall_shadow_strength = 1.0;
uniform float daylight = 1.0;

#include "res://shaders/gi_trace.gdshaderinc"

float wall_shadow(vec2 origin) {
	float origin_coverage = sample_field(origin).b;
	vec2 cast = mix(vec2(0.0, 1.0), key_direction, 0.4);
	float blocked = 0.0;
	for (int i = 0; i < RAY_COUNT; i++) {
		float spread = (float(i) - 2.0) * 0.22;
		vec2 ray = -normalize(cast + vec2(spread, 0.0));
		float edge_x = ray.x < 0.0 ? origin.x - 0.5 : design_size.x - 0.5 - origin.x;
		float reach = min(SHADOW_FADE_END, min(edge_x / max(abs(ray.x), 0.001), (origin.y - 0.5) / -ray.y));
		blocked += 1.0 - trace_visibility(origin, origin + ray * reach, origin_coverage, 0.0);
	}
	return clamp(blocked * wall_shadow_strength / float(RAY_COUNT), 0.0, 1.0);
}

void fragment() {
	vec2 dx = vec2(light_px.x, 0.0);
	vec2 dy = vec2(0.0, light_px.y);
	vec3 light = 4.0 * texture(light_tex, UV).rgb;
	light += 2.0 * (texture(light_tex, UV + dx).rgb + texture(light_tex, UV - dx).rgb
			+ texture(light_tex, UV + dy).rgb + texture(light_tex, UV - dy).rgb);
	light += texture(light_tex, UV + dx + dy).rgb + texture(light_tex, UV + dx - dy).rgb
			+ texture(light_tex, UV - dx + dy).rgb + texture(light_tex, UV - dx - dy).rgb;
	float shadow = 0.0;
	if (daylight > 0.0 && wall_shadow_strength > 0.0) {
		shadow = wall_shadow(UV * design_size);
	}
	COLOR = vec4(light / 16.0, shadow);
}
