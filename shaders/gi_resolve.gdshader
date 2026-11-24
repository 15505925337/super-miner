// 同一帧的彩光用九点滤波，连续影子沿横向和纵向柔化。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform sampler2D emission_tex : filter_linear, repeat_disable;
uniform sampler2D shadow_tex : filter_linear, repeat_disable;
uniform vec2 light_px;
uniform vec2 design_px;
uniform vec2 key_direction = vec2(0.0, 1.0);

vec3 light_at(vec2 uv) {
	return min(texture(light_tex, uv).rgb + texture(emission_tex, uv).rgb, vec3(1.0));
}

float shadow_at(vec2 uv, vec2 offset) {
	return texture(shadow_tex, uv + offset * design_px).r;
}

float soft_shadow(vec2 uv) {
	vec2 cross_light = vec2(-key_direction.y, key_direction.x);
	float amount = 20.0 * shadow_at(uv, vec2(0.0));
	amount += 15.0 * (shadow_at(uv, cross_light * 2.0) + shadow_at(uv, cross_light * -2.0));
	amount += 6.0 * (shadow_at(uv, cross_light * 4.0) + shadow_at(uv, cross_light * -4.0));
	amount += shadow_at(uv, cross_light * 6.0) + shadow_at(uv, cross_light * -6.0);
	float along = 0.5 * (shadow_at(uv, key_direction * 2.0) + shadow_at(uv, key_direction * -2.0));
	return mix(amount / 64.0, along, 0.12);
}

void fragment() {
	vec2 dx = vec2(light_px.x, 0.0);
	vec2 dy = vec2(0.0, light_px.y);
	vec3 light = 4.0 * light_at(UV);
	light += 2.0 * (light_at(UV + dx) + light_at(UV - dx) + light_at(UV + dy) + light_at(UV - dy));
	light += light_at(UV + dx + dy) + light_at(UV + dx - dy) + light_at(UV - dx + dy) + light_at(UV - dx - dy);
	COLOR = vec4(light / 16.0, soft_shadow(UV));
}
