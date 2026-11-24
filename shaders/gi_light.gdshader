// 在发光源覆盖范围内累加彩色光，只沿接收点附近短距离采样遮挡。
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2 design_size;
uniform vec4 energy;
uniform float radius;
uniform float source_skip;
uniform float line_half_width;
uniform vec2 center;
uniform float opacity = 1.0;

void fragment() {
	vec2 to_light = center - SCREEN_UV * design_size;
	// 岩浆是一条横向光源，取离接收点最近的位置。
	to_light.x -= clamp(to_light.x, -line_half_width, line_half_width);
	float distance_to_light = length(to_light);
	float radial = distance_to_light / radius;
	if (radial >= 1.0) {
		discard;
	}
	float ray_length = clamp(distance_to_light - source_skip, 0.0, 22.0);
	vec2 ray = to_light * (ray_length / max(distance_to_light, 0.01)) / design_size;
	float blocker = 0.0;
	if (ray_length > 1.0) {
		for (int i = 1; i <= 6; i++) {
			float fraction = float(i) / 6.0;
			blocker = max(blocker, texture(mask_tex, SCREEN_UV + ray * fraction).r * (1.0 - 0.72 * fraction));
		}
	}
	// 物件中心也用这张光图取色，轮廓内部的接收点少扣一点，避免被本身遮死。
	float occupied = texture(mask_tex, SCREEN_UV).r;
	float visibility = 1.0 - blocker * mix(0.72, 0.18, occupied);
	float falloff = 1.0 - smoothstep(0.0, 1.0, radial);
	COLOR = vec4(energy.rgb * (energy.a * opacity * falloff * visibility), 1.0);
}
