// 泛光第二步：逐级放大并叠回上一级，得到一圈柔和、范围大的光晕。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_linear, repeat_disable;       // 更小的那一级
uniform sampler2D add_tex : filter_linear, repeat_disable;   // 同尺寸的缩小结果
uniform vec2 src_px = vec2(0.001);
uniform float wide = 1.7;      // 大范围光晕的比重

void fragment() {
	vec2 h = src_px * 0.5;
	vec3 s = texture(src, UV + vec2(-h.x * 2.0, 0.0)).rgb;
	s += texture(src, UV + vec2(-h.x, h.y)).rgb * 2.0;
	s += texture(src, UV + vec2(0.0, h.y * 2.0)).rgb;
	s += texture(src, UV + vec2(h.x, h.y)).rgb * 2.0;
	s += texture(src, UV + vec2(h.x * 2.0, 0.0)).rgb;
	s += texture(src, UV + vec2(h.x, -h.y)).rgb * 2.0;
	s += texture(src, UV + vec2(0.0, -h.y * 2.0)).rgb;
	s += texture(src, UV + vec2(-h.x, -h.y)).rgb * 2.0;
	COLOR = vec4(s / 12.0 * wide + texture(add_tex, UV).rgb, 1.0);
}
