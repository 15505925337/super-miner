// 按受光和遮挡调整井壁底色。井壁之前的画面用当前视口的屏幕拷贝。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D backdrop_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D resolved_tex : filter_linear, repeat_disable;
uniform float bounce_strength;
uniform float daylight_strength;
uniform float darkness;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

vec3 daylight_color(vec3 base, vec4 lighting) {
	float received = dot(lighting.rgb, LUMA);
	float shade = lighting.a;
	// 底光随原画明度变化，暗纹压实，亮纹保留。软影同时减掉底光和受光增益。
	float ambient = 0.92 - 0.40 * (1.0 - smoothstep(0.06, 0.30, dot(base, LUMA)));
	float lift = 11.9 * daylight_strength * pow(received, 1.37) * (1.0 - 0.80 * shade);
	float exposure = clamp(ambient + lift - 0.40 * shade, 0.48, 2.75);
	vec3 tinted = base * (1.0 + 0.20 * daylight_strength * (lighting.rgb - received));
	float peak = max(tinted.r, max(tinted.g, tinted.b));
	float room = max(0.001, 1.0 - peak);
	// 三通道共用高光压缩，亮处保留冷暖关系。
	float gain = exposure;
	if (exposure > 1.0) {
		gain = 1.0 + room * (1.0 - exp(-peak * (exposure - 1.0) / room)) / max(peak, 0.001);
	}
	return tinted * gain;
}

void fragment() {
	vec3 base = texture(backdrop_tex, SCREEN_UV).rgb;
	vec4 light = texture(resolved_tex, UV);
	vec2 border = min(UV, 1.0 - UV) * vec2(640.0, 360.0);
	float edge = smoothstep(0.0, 6.0, min(border.x, border.y));
	vec3 color = base;
	if (darkness < 1.0) {
		color = clamp(daylight_color(base, light), 0.0, 1.0);
	}
	if (darkness > 0.0) {
		// 完全黑灯时使用原先的彩光混合，避免暗处的底光再被压一遍。
		vec3 bounce = 1.0 - exp(-light.rgb * bounce_strength * mix(0.30, 0.70, darkness));
		float light_alpha = 0.45 * max(bounce.r, max(bounce.g, bounce.b));
		vec3 black_color = base * (1.0 - light_alpha) + bounce;
		color = mix(color, black_color, darkness);
	}
	COLOR = vec4(mix(base, color, edge), 1.0);
}
