// 井壁方向遮挡的距离场步进。
uniform sampler2D distance_tex : filter_linear, repeat_disable;
uniform vec2 design_size;

const int MAX_STEPS = 64;
const float SHADOW_FADE_START = 18.0;
const float SHADOW_FADE_END = 178.0;
const float SOLID_COVERAGE = 0.35;

vec3 sample_field(vec2 point) {
	// 解码是线性的。跨 RG 字节边界插值也能得到连续的距离。
	return texture(distance_tex, point / design_size).rgb;
}

float trace_visibility(vec2 origin, vec2 target, float origin_coverage) {
	vec2 delta = target - origin;
	float span = length(delta);
	float end = min(span, SHADOW_FADE_END);
	if (end <= 0.75) {
		return 1.0;
	}
	vec2 ray = delta / span;
	float traveled = 0.65;
	float prev_traveled = 0.0;
	float prev_coverage = origin_coverage;
	float exited = -4.0;
	float visibility = 1.0;
	bool escaping = origin_coverage >= SOLID_COVERAGE;
	for (int i = 0; i < MAX_STEPS && traveled < end; i++) {
		vec3 field = sample_field(origin + ray * traveled);
		float distance_px = dot(field.rg, vec2(31.875, 8160.0));
		if (field.b >= SOLID_COVERAGE) {
			if (!escaping) {
				// 在前后两个采样之间找轮廓交点，避免直接用步进落点画出一圈圈的台阶。
				float fraction = (SOLID_COVERAGE - prev_coverage) / max(field.b - prev_coverage, 0.001);
				float hit_distance = mix(prev_traveled, traveled, clamp(fraction, 0.0, 1.0));
				return min(visibility, smoothstep(SHADOW_FADE_START, SHADOW_FADE_END, hit_distance));
			}
		} else {
			if (escaping) {
				escaping = false;
				exited = traveled;
			}
			if (traveled > exited + 3.0) {
				float recovery = smoothstep(SHADOW_FADE_START, SHADOW_FADE_END, traveled);
				float penumbra = 1.25 + traveled * 0.04;
				float pass_light = smoothstep(0.35, penumbra, distance_px);
				visibility = min(visibility, mix(recovery, 1.0, pass_light));
			}
		}
		prev_traveled = traveled;
		prev_coverage = field.b;
		// 为细绳留出采样余量，并限制采样间隔，减少软影被跨过的距离。
		traveled += clamp((distance_px - 1.0) * 0.88, 0.65, 8.0);
	}
	return visibility;
}
