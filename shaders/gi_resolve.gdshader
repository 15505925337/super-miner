// 同一帧的彩光用九点滤波，物件影子按命中距离横向柔化。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform sampler2D emission_tex : filter_linear, repeat_disable;
uniform sampler2D shadow_tex : filter_linear, repeat_disable;
uniform vec2 light_px;
uniform vec2 design_px;
uniform vec2 key_direction = vec2(0.0, 1.0);
uniform float wall_shadow_strength = 1.0;

vec3 light_at(vec2 uv) {
	return min(texture(light_tex, uv).rgb + texture(emission_tex, uv).rgb, vec3(1.0));
}

vec2 shadow_at(vec2 uv, vec2 offset) {
	return texture(shadow_tex, uv + offset * design_px).rg;
}

float soft_shadow(vec2 uv) {
	vec2 across = vec2(-key_direction.y, key_direction.x);
	// 侧边像素也能从邻近的命中估计半影半径。
	vec2 nearby = shadow_at(uv, vec2(0.0));
	for (int i = 1; i <= 3; i++) {
		vec2 offset = across * (4.0 * float(i));
		nearby += shadow_at(uv, offset) + shadow_at(uv, -offset);
	}
	if (nearby.r < 0.001) {
		return 0.0;
	}
	float depth = clamp(nearby.g / nearby.r, 0.0, 1.0);
	vec2 step_px = across * (mix(3.0, 12.0, depth) / 3.0);
	vec2 filtered = 20.0 * shadow_at(uv, vec2(0.0));
	filtered += 15.0 * (shadow_at(uv, step_px) + shadow_at(uv, -step_px));
	filtered += 6.0 * (shadow_at(uv, step_px * 2.0) + shadow_at(uv, step_px * -2.0));
	filtered += shadow_at(uv, step_px * 3.0) + shadow_at(uv, step_px * -3.0);
	// 远处半影更宽，同时提高遮挡阈值让实影向中心收窄。
	float silhouette = smoothstep(mix(0.10, 0.45, depth), mix(0.65, 0.95, depth), filtered.r / 64.0);
	float fade = 1.0 - smoothstep(0.0, 1.0, filtered.g / max(filtered.r, 0.001));
	return clamp(silhouette * fade * fade * wall_shadow_strength, 0.0, 1.0);
}

void fragment() {
	vec2 dx = vec2(light_px.x, 0.0);
	vec2 dy = vec2(0.0, light_px.y);
	vec3 light = 4.0 * light_at(UV);
	light += 2.0 * (light_at(UV + dx) + light_at(UV - dx) + light_at(UV + dy) + light_at(UV - dy));
	light += light_at(UV + dx + dy) + light_at(UV + dx - dy) + light_at(UV - dx + dy) + light_at(UV - dx - dy);
	COLOR = vec4(light / 16.0, soft_shadow(UV));
}
