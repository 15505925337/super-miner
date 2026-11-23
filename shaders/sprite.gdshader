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
	// 这是画在原图后面的描边层，主体内不出色。
	if (texture(TEXTURE, UV).a >= 0.95) {
		discard;
	}
	vec2 width = rim_px * TEXTURE_PIXEL_SIZE;
	// 顺着入射方向能碰到物件、反向是空的，才是受光的外沿。
	vec2 offset = width * light_axis;
	float upper = rim_strength * smoothstep(0.2, 0.7, texture(TEXTURE, UV + offset).a - texture(TEXTURE, UV - offset).a);
	float lower = 0.0;
	if (under_col.a > 0.0) {
		offset = width * under_axis;
		lower = under_col.a * smoothstep(0.2, 0.7, texture(TEXTURE, UV + offset).a - texture(TEXTURE, UV - offset).a);
	}
	if (upper + lower <= 0.0) {
		discard;
	}
	vec3 edge_rgb = mix(light_col.rgb, under_col.rgb, lower / (upper + lower));
	COLOR = vec4(edge_rgb, max(upper, lower) * light_fade) * tint;
}
