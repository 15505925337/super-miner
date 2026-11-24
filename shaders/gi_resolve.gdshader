// 用同一帧的 3×3 空间滤波压低软影周围的采样纹路。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_px;

void fragment() {
	vec2 dx = vec2(light_px.x, 0.0);
	vec2 dy = vec2(0.0, light_px.y);
	vec3 light = 4.0 * texture(light_tex, UV).rgb;
	light += 2.0 * (texture(light_tex, UV + dx).rgb + texture(light_tex, UV - dx).rgb
			+ texture(light_tex, UV + dy).rgb + texture(light_tex, UV - dy).rgb);
	light += texture(light_tex, UV + dx + dy).rgb + texture(light_tex, UV + dx - dy).rgb
			+ texture(light_tex, UV - dx + dy).rgb + texture(light_tex, UV - dx - dy).rgb;
	COLOR = vec4(light / 16.0, 1.0);
}
