// 最后合成玩法画面、泛光和菜单打开时的背景虚化。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D world_tex : filter_nearest, repeat_disable;
uniform sampler2D bloom_tex : filter_linear, repeat_disable;
uniform float bloom_strength = 0.0;
uniform float menu = 0.0;                             // 0 到 1：有面板打开时，把后面的游戏画面虚化、压暗
uniform float menu_blur = 6.0;                        // 虚化半径（屏幕像素）

void fragment() {
	vec3 c = texture(world_tex, UV).rgb;
	if (bloom_strength > 0.0) {
		vec3 b = texture(bloom_tex, UV).rgb * bloom_strength;
		c = c + b * (1.0 - c * 0.35);                 // 接近叠加，亮处稍微收一点，免得一片死白
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
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
