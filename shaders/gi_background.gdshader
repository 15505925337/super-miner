// 手绘井壁接收彩光。缺光处略暗，原画仍提供瞄准所需的底光。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D resolved_tex : filter_linear, repeat_disable;
uniform float bounce_strength;
uniform float shadow_strength;
uniform float ambient_fade = 1.0;

void fragment() {
	vec3 light = texture(resolved_tex, UV).rgb;
	vec2 border = min(UV, 1.0 - UV) * vec2(640.0, 360.0);
	float edge = smoothstep(0.0, 6.0, min(border.x, border.y));
	float received = dot(light, vec3(0.30, 0.45, 0.25));
	float shade = (1.0 - exp(-0.18 * shadow_strength)) * exp(-3.0 * received) * ambient_fade;
	vec3 bounce = 1.0 - exp(-light * bounce_strength * 0.57);
	float light_alpha = 0.45 * max(bounce.r, max(bounce.g, bounce.b));
	COLOR = vec4(bounce, shade + (1.0 - shade) * light_alpha) * edge;
}
