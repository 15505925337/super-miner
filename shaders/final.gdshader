// 最后合成：玩法画面 + 泛光，再做调色和暗角。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D world_tex : filter_nearest, repeat_disable;
uniform sampler2D bloom_tex : filter_linear, repeat_disable;
uniform float bloom_strength = 0.0;
uniform float vignette = 0.0;                         // 暗角强度
uniform float grade = 0.0;                            // 调色强度
uniform vec3 shadow_tint = vec3(0.90, 0.96, 1.12);    // 暗部偏冷
uniform vec3 light_tint = vec3(1.08, 1.0, 0.90);      // 亮部偏暖
uniform float contrast = 1.08;
uniform float saturation = 1.10;
uniform float menu = 0.0;                             // 0 到 1：有面板打开时，把后面的游戏画面虚化、压暗
uniform float menu_blur = 6.0;                        // 虚化半径（屏幕像素）

void fragment() {
	vec3 c = texture(world_tex, UV).rgb;
	if (bloom_strength > 0.0) {
		vec3 b = texture(bloom_tex, UV).rgb * bloom_strength;
		c = c + b * (1.0 - c * 0.35);                 // 接近叠加，亮处稍微收一点，免得一片死白
	}
	if (grade > 0.0) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 g = mix(vec3(l), c, saturation);
		g = (g - 0.5) * contrast + 0.5;
		g *= mix(shadow_tint, light_tint, smoothstep(0.05, 0.75, l));
		c = mix(c, g, grade);
	}
	if (menu > 0.001) {
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 16; i++) {
			float fi = float(i);
			float r = sqrt((fi + 0.5) / 16.0) * menu_blur * menu;
			float an = fi * 2.39996323;
			acc += texture(world_tex, UV + vec2(cos(an), sin(an)) * r * SCREEN_PIXEL_SIZE).rgb;
		}
		acc /= 16.0;
		float lm = dot(acc, vec3(0.299, 0.587, 0.114));
		acc = mix(vec3(lm), acc, 0.8) * mix(1.0, 0.5, menu);
		c = mix(c, acc + (c - acc) * 0.0, menu);
	}
	if (vignette > 0.0) {
		vec2 q = (UV - 0.5) * vec2(1.0, 0.86);
		float v = smoothstep(0.78, 0.28, length(q));
		c *= mix(1.0, 0.25 + 0.75 * v, vignette);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
