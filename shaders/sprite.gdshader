// 只在物件原图的轮廓内提亮，熔岩层的岩浆反光也走同一道遮罩。
shader_type canvas_item;

uniform vec4 light_col : source_color = vec4(1.0);
uniform vec4 under_col : source_color = vec4(0.0);
uniform vec2 light_axis = vec2(0.0, 1.0);
uniform vec2 under_axis = vec2(0.0, -1.0);
uniform float rim_px = 3.0;          // 轮廓采样半径（贴图像素）
uniform float rim_strength = 0.0;
uniform float light_fade = 0.0;

const float DIAGONAL = 0.707107;
const vec2 SAMPLE_DIRS[8] = {
	vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
	vec2(DIAGONAL, DIAGONAL), vec2(-DIAGONAL, DIAGONAL),
	vec2(DIAGONAL, -DIAGONAL), vec2(-DIAGONAL, -DIAGONAL)
};

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	if (base.a >= 0.95 && luma > 0.36) {
		vec2 radius = rim_px * TEXTURE_PIXEL_SIZE;
		float outside = 0.0;
		vec2 inward = vec2(0.0);
		for (int i = 0; i < 8; i++) {
			vec2 direction = SAMPLE_DIRS[i];
			vec2 uv = UV + direction * radius;
			// 原生尺寸的贴图可以裁到边，越过贴图的地方也算透明。
			vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
			float alpha = textureLod(TEXTURE, uv, 0.0).a * inside.x * inside.y;
			outside += 1.0 - alpha;
			inward += direction * alpha;
		}
		// 圆周越多采样落在轮廓外，越靠近边缘。朝物件内部的法线用来找受光侧。
		float coverage = smoothstep(0.0, 4.0, outside);
		inward /= max(length(inward), 0.001);
		float upper = rim_strength * smoothstep(0.0, 0.65, dot(inward, light_axis));
		float lower = under_col.a * smoothstep(0.0, 0.65, dot(inward, under_axis));
		float surface = smoothstep(0.36, 0.55, luma);
		vec3 light = (light_col.rgb * upper + under_col.rgb * lower) * coverage * surface * light_fade;
		// 用滤色提亮原色。光只抬高低于泛光起始值的通道，减少沿轮廓向外泛白。
		base.rgb += min((1.0 - base.rgb) * light, max(vec3(0.82) - base.rgb, vec3(0.0)));
	}
	COLOR = base * tint;
}
