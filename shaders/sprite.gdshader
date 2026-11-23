// 在物件的受光轮廓上加细描边，熔岩层再加一道来自下方的反光。
shader_type canvas_item;

uniform vec4 light_col : source_color = vec4(1.0);
uniform vec4 under_col : source_color = vec4(0.0);
uniform vec2 light_axis = vec2(0.0, 1.0);
uniform vec2 under_axis = vec2(0.0, -1.0);
uniform float rim_px = 3.0;          // 描边宽度（贴图像素）
uniform float rim_strength = 0.0;
uniform float light_fade = 0.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	if (light_fade > 0.0) {
		vec4 base = texture(TEXTURE, UV);
		if (base.a < 0.95) {
			vec2 width = rim_px * TEXTURE_PIXEL_SIZE;
			// 顺着入射方向能碰到物件、反向是空的，才是受光的外沿。
			vec2 offset = width * light_axis;
			float upper = rim_strength * smoothstep(0.2, 0.7, texture(TEXTURE, UV + offset).a - texture(TEXTURE, UV - offset).a);
			float lower = 0.0;
			if (under_col.a > 0.0) {
				offset = width * under_axis;
				lower = under_col.a * smoothstep(0.2, 0.7, texture(TEXTURE, UV + offset).a - texture(TEXTURE, UV - offset).a);
			}
			float edge_alpha = max(upper, lower) * light_fade;
			if (edge_alpha > 0.0) {
				vec3 edge_rgb = mix(light_col.rgb, under_col.rgb, lower / (upper + lower));
				float alpha = base.a + edge_alpha * (1.0 - base.a);
				COLOR = vec4(mix(edge_rgb, base.rgb, base.a / alpha), alpha) * tint;
			}
		}
	}
}
