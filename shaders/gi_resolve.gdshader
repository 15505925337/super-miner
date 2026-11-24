// 对彩光做轻微的空间滤波，稳定低分辨率软影边缘。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_px;

void fragment() {
	vec2 dx = vec2(light_px.x, 0.0);
	vec2 dy = vec2(0.0, light_px.y);
	vec3 light = 0.50 * texture(light_tex, UV).rgb;
	light += 0.125 * (texture(light_tex, UV + dx).rgb + texture(light_tex, UV - dx).rgb
			+ texture(light_tex, UV + dy).rgb + texture(light_tex, UV - dy).rgb);
	COLOR = vec4(light, 1.0);
}
