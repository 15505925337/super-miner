// 井壁方向遮挡的距离场步进。
uniform sampler2D distance_tex : filter_linear, repeat_disable;
uniform vec2 design_size;

const int MAX_STEPS = 64;
const float SOLID_COVERAGE = 0.35;

vec3 sample_field(vec2 point) {
	// 解码是线性的。跨 RG 字节边界插值也能得到连续的距离。
	return texture(distance_tex, point / design_size).rgb;
}

float blocker_distance(vec2 origin, vec2 ray, float reach) {
	float prev_coverage = sample_field(origin).b;
	if (prev_coverage >= SOLID_COVERAGE) {
		return 0.0;
	}
	float traveled = 0.65;
	float prev_traveled = 0.0;
	for (int i = 0; i < MAX_STEPS && traveled < reach; i++) {
		vec3 field = sample_field(origin + ray * traveled);
		if (field.b >= SOLID_COVERAGE) {
			// 按覆盖率插值下沿交点，距离不跟着离散跳步抖动。
			float fraction = (SOLID_COVERAGE - prev_coverage) / max(field.b - prev_coverage, 0.001);
			return mix(prev_traveled, traveled, clamp(fraction, 0.0, 1.0));
		}
		float distance_px = dot(field.rg, vec2(31.875, 8160.0));
		prev_traveled = traveled;
		prev_coverage = field.b;
		traveled += clamp((distance_px - 1.0) * 0.88, 0.65, 8.0);
	}
	return -1.0;
}
