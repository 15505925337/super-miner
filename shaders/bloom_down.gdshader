// 泛光第一步：逐级缩小。第一级顺便只留下亮的部分（阈值），之后每级缩一半。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 src_px = vec2(0.001);   // 来源贴图一个像素的大小
uniform float spread = 1.0;          // 采样间距（来源像素数）
uniform bool prefilter = false;
uniform float threshold = 0.7;
uniform float knee = 0.2;

vec3 pick(vec2 uv) {
	vec3 c = texture(src, uv).rgb;
	if (prefilter) {
		float br = max(c.r, max(c.g, c.b));
		float soft = clamp(br - threshold + knee, 0.0, 2.0 * knee);
		soft = soft * soft / (4.0 * knee + 0.0001);
		c *= max(soft, br - threshold) / max(br, 0.0001);
	}
	return c;
}

void fragment() {
	vec2 h = src_px * spread;
	vec3 s = pick(UV) * 4.0;
	s += pick(UV + vec2(-h.x, -h.y));
	s += pick(UV + vec2(h.x, -h.y));
	s += pick(UV + vec2(-h.x, h.y));
	s += pick(UV + vec2(h.x, h.y));
	COLOR = vec4(s / 8.0, 1.0);
}
