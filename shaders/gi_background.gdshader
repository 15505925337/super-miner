// 按受光和遮挡调整井壁底色。井壁之前的画面用当前视口的屏幕拷贝。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D backdrop_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D resolved_tex : filter_linear, repeat_disable;
uniform sampler2D emission_tex : filter_linear, repeat_disable;
uniform float bounce_strength;
uniform float daylight_strength;
uniform float darkness;
uniform float ground_y = 0.0;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

vec3 daylight_color(vec3 base, vec4 lighting) {
	float received = dot(lighting.rgb, LUMA);
	float original_luma = dot(base, LUMA);
	// 底光随原画明度变化，暗纹压实，亮纹保留。软影同时减掉底光和受光增益。
	float ambient = 0.92 - 0.40 * (1.0 - smoothstep(0.06, 0.30, original_luma));
	float lift = 6.3 * daylight_strength * pow(received, 1.37);
	float exposure = clamp(ambient + lift, 0.48, 2.75);
	vec3 tinted = base * (1.0 + 0.20 * daylight_strength * (lighting.rgb - received));
	float peak = max(tinted.r, max(tinted.g, tinted.b));
	float room = max(0.001, 1.0 - peak);
	// 三通道共用高光压缩，亮处保留冷暖关系。
	float gain = exposure;
	if (exposure > 1.0) {
		gain = 1.0 + room * (1.0 - exp(-peak * (exposure - 1.0) / room)) / max(peak, 0.001);
	}
	vec3 lit = clamp(tinted * gain, 0.0, 1.0);
	float shadow_luma = max(original_luma * 0.65, original_luma - 32.0 / 255.0);
	float distant_luma = max(shadow_luma, original_luma - 4.0 / 255.0);
	float lit_luma = dot(lit, LUMA);
	if (lit_luma < distant_luma) {
		// 向原画回补底光，使淡出端不会接出一段暗柱。
		lit = mix(lit, base, (distant_luma - lit_luma) / (original_luma - lit_luma));
		lit_luma = distant_luma;
	}
	// 近影收向原画亮度的下限，出影时回到受光的井壁。
	float shaded_luma = mix(lit_luma, shadow_luma, lighting.a);
	return lit * (shaded_luma / max(lit_luma, 0.000001));
}

vec3 emission_color(vec3 color, vec3 emission) {
	float emitted_luma = dot(emission, LUMA);
	if (emitted_luma <= 0.001) {
		return color;
	}
	float peak = max(emission.r, max(emission.g, emission.b));
	float weight = 0.88 * (1.0 - exp(-3.4 * daylight_strength * peak));
	float luminance = dot(color, LUMA);
	// 把发光源的色相投到同明度的墙面上，避免用彩光再抬一次井内亮度。
	vec3 chroma = luminance * (emission / emitted_luma - 1.0);
	float headroom = (1.0 - luminance) / max(max(chroma.r, max(chroma.g, chroma.b)), 0.001);
	vec3 target = vec3(luminance) + chroma * min(1.0, headroom);
	return mix(color, target, weight);
}

void fragment() {
	vec3 base = texture(backdrop_tex, SCREEN_UV).rgb;
	vec4 light = texture(resolved_tex, UV);
	vec2 border = min(UV, 1.0 - UV) * vec2(640.0, 360.0);
	float edge = smoothstep(0.0, 6.0, min(border.x, border.y));
	if (ground_y > 0.0) {
		edge *= smoothstep(ground_y, ground_y + 4.0, UV.y * 360.0);
	}
	vec3 color = base;
	if (darkness < 1.0) {
		vec3 emission = texture(emission_tex, UV).rgb;
		color = emission_color(daylight_color(base, light), emission);
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
