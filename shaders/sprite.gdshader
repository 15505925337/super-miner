// 主光和岩浆反光只提亮轮廓内侧。超高档按物件中心采样全局光照。
shader_type canvas_item;

uniform vec4 light_col : source_color = vec4(1.0);
uniform vec4 under_col : source_color = vec4(0.0);
uniform vec2 light_axis = vec2(0.0, 1.0);
uniform vec2 under_axis = vec2(0.0, -1.0);
uniform float rim_px = 3.0;          // 轮廓采样半径（贴图像素）
uniform float rim_strength = 0.0;
uniform float light_fade = 0.0;
uniform sampler2D resolved_tex : filter_linear, repeat_disable;
uniform float bounce_strength = 0.0;
uniform vec3 gi_sample = vec3(0.0); // 井内采样坐标与受光强度。强度为 0 时跳过 GI。

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

float in_texture(vec2 uv) {
	// 原生尺寸的贴图可以裁到边，越过贴图的地方算透明。
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return inside.x * inside.y;
}

void fragment() {
	if (light_fade > 0.0) {
		vec4 base = texture(TEXTURE, UV);
		float luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
		if (base.a >= 0.95 && (luma > 0.36 || under_col.a > 0.0)) {
			vec2 radius = rim_px * TEXTURE_PIXEL_SIZE;
			float outside = 0.0;
			vec2 inward = vec2(0.0);
			for (int i = 0; i < 8; i++) {
				vec2 direction = SAMPLE_DIRS[i];
				vec2 uv = UV + direction * radius;
				float alpha = textureLod(TEXTURE, uv, 0.0).a * in_texture(uv);
				outside += 1.0 - alpha;
				inward += direction * alpha;
			}
			// 圆周越多采样落在轮廓外，越靠近边缘。朝物件内部的法线用来找受光侧。
			float coverage = smoothstep(0.0, 4.0, outside);
			inward /= max(length(inward), 0.001);
			float upper = rim_strength * smoothstep(0.0, 0.65, dot(inward, light_axis));
			float surface = smoothstep(0.36, 0.55, luma);
			vec3 light = light_col.rgb * upper * coverage * surface * light_fade;
			float lower_facing = dot(inward, under_axis);
			if (under_col.a > 0.0 && lower_facing > 0.0 && outside > 0.0) {
				// 沿轮廓法线向外探一格。探到透明区时保留原色，给最外一格留出描边。
				vec2 outline_uv = UV - inward * radius / 3.0;
				float outline_alpha = textureLod(TEXTURE, outline_uv, 0.0).a * in_texture(outline_uv);
				float inner = smoothstep(0.5, 1.0, outline_alpha);
				// 背光面也接到反光。在更暗的像素上只压低强度，让亮带经过深色块时仍连续。
				float shade = mix(0.40, 1.0, smoothstep(0.18, 0.28, luma));
				float lower = under_col.a * smoothstep(0.0, 0.65, lower_facing);
				float lower_coverage = smoothstep(0.0, 2.0, outside);
				light += under_col.rgb * lower * lower_coverage * inner * shade * light_fade;
			}
			// 用滤色提亮原色。光只抬高低于泛光起始值的通道，减少沿轮廓向外泛白。
			base.rgb += min((1.0 - base.rgb) * light, max(vec3(0.82) - base.rgb, vec3(0.0)));
		}
		COLOR = base * tint;
	}
	if (gi_sample.z > 0.0) {
		// 保留原画暗部和高光，整件物件使用同一个受光采样。
		vec3 bounce = texture(resolved_tex, gi_sample.xy).rgb;
		vec3 gain = 0.65 * (1.0 - exp(-bounce * bounce_strength * 0.85));
		float headroom = 1.0 - max(COLOR.r, max(COLOR.g, COLOR.b));
		COLOR.rgb *= 1.0 + gain * headroom * gi_sample.z;
	}
}
