// 只在局部混入反光。光源范围外和缺光的影子里由原画底光保留轮廓。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D resolved_tex : filter_linear, repeat_disable;
uniform float bounce_strength;
uniform float darkness;

void fragment() {
	vec3 light = texture(resolved_tex, UV).rgb;
	vec2 border = min(UV, 1.0 - UV) * vec2(640.0, 360.0);
	float edge = smoothstep(0.0, 6.0, min(border.x, border.y));
	// 黑灯下留足彩光，常态下避免给整面井壁涂上浅色。
	float exposure = mix(0.30, 0.70, darkness);
	vec3 bounce = 1.0 - exp(-light * bounce_strength * exposure);
	float light_alpha = 0.45 * max(bounce.r, max(bounce.g, bounce.b));
	COLOR = vec4(bounce, light_alpha) * edge;
}
