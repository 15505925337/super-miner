// 同一帧的照明和彩光用九点滤波。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform sampler2D emission_tex : filter_linear, repeat_disable;
uniform vec2 light_px;

vec3 light_at(vec2 uv) {
	return min(texture(light_tex, uv).rgb + texture(emission_tex, uv).rgb, vec3(1.0));
}

void fragment() {
	vec2 dx = vec2(light_px.x, 0.0);
	vec2 dy = vec2(0.0, light_px.y);
	vec3 light = 4.0 * light_at(UV);
	light += 2.0 * (light_at(UV + dx) + light_at(UV - dx) + light_at(UV + dy) + light_at(UV - dy));
	light += light_at(UV + dx + dy) + light_at(UV + dx - dy) + light_at(UV - dx + dy) + light_at(UV - dx - dy);
	COLOR = vec4(light / 16.0, 1.0);
}
