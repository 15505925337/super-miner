// 解算低分辨率反光和短软影。只从轮廓附近取样，不把阴影延伸到井的另一侧。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 design_px;
uniform vec2 light_dir = vec2(0.0, 1.0);
uniform float light_fade = 1.0;

float mask_at(vec2 uv, vec2 offset) {
	vec2 at = uv + offset * design_px;
	if (any(lessThan(at, vec2(0.0))) || any(greaterThan(at, vec2(1.0)))) {
		return 0.0;
	}
	return texture(mask_tex, at).r;
}

void fragment() {
	vec2 side = vec2(-light_dir.y, light_dir.x);
	float shadow = 0.36 * mask_at(UV, -light_dir * 2.5);
	shadow += 0.15 * (mask_at(UV, -light_dir * 5.5 + side * 1.8) + mask_at(UV, -light_dir * 5.5 - side * 1.8));
	shadow += 0.10 * (mask_at(UV, -light_dir * 9.5 + side * 3.0) + mask_at(UV, -light_dir * 9.5 - side * 3.0));
	shadow += 0.07 * (mask_at(UV, -light_dir * 13.0 + side * 4.0) + mask_at(UV, -light_dir * 13.0 - side * 4.0));
	float contact = mask_at(UV, vec2( 3.0, 0.0)) + mask_at(UV, vec2(-3.0, 0.0));
	contact += mask_at(UV, vec2(0.0,  3.0)) + mask_at(UV, vec2(0.0, -3.0));
	contact += 0.5 * (mask_at(UV, vec2( 4.0,  4.0)) + mask_at(UV, vec2(-4.0,  4.0))
			+ mask_at(UV, vec2( 4.0, -4.0)) + mask_at(UV, vec2(-4.0, -4.0)));
	float shade = (0.26 * shadow + 0.16 * contact / 6.0) * light_fade;

	// 把入射光向邻域扩散一次，模拟井壁的近处漫反射。
	vec2 dx = vec2(6.0, 0.0) * design_px;
	vec2 dy = vec2(0.0, 6.0) * design_px;
	vec3 bounce = 0.56 * texture(light_tex, UV).rgb;
	bounce += 0.11 * (texture(light_tex, UV + dx).rgb + texture(light_tex, UV - dx).rgb
			+ texture(light_tex, UV + dy).rgb + texture(light_tex, UV - dy).rgb);
	COLOR = vec4(bounce * light_fade * light_fade, shade);
}
