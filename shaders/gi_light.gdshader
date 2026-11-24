// 每个发光源在覆盖区域内投五条确定性的视线。距离场决定每步能跳多远。
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform sampler2D distance_tex : filter_linear, repeat_disable;
uniform vec2 design_size;
uniform vec4 energy;
uniform float reach;
uniform float falloff_px;
uniform float source_skip;
uniform float source_width;
uniform float line_half_width;
uniform vec2 light_dir;
uniform vec2 center;
uniform float opacity = 1.0;
uniform float shadow_strength;
uniform float light_fade = 1.0;

const int RAY_COUNT = 5;
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
	float end = min(span - source_skip, SHADOW_FADE_END);
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

void fragment() {
	float strength = energy.a * opacity * light_fade;
	if (strength <= 0.0) {
		discard;
	}
	vec2 origin = SCREEN_UV * design_size;
	vec2 to_light = center - origin;
	// 岩浆是整条光带，取接收点下方的灯面，再在灯面上取五个位置。
	to_light.x -= clamp(to_light.x, -line_half_width, line_half_width);
	float distance_px = length(to_light);
	if (distance_px >= reach) {
		discard;
	}
	vec2 ray = to_light / max(0.001, distance_px);
	vec2 across = vec2(-ray.y, ray.x);
	float visibility = 1.0;
	if (shadow_strength > 0.0 && distance_px > source_skip) {
		float origin_coverage = sample_field(origin).b;
		float visible_rays = 0.0;
		for (int i = 0; i < RAY_COUNT; i++) {
			float offset = float(i) / float(RAY_COUNT - 1) * 2.0 - 1.0;
			vec2 target = clamp(origin + to_light + across * source_width * offset,
					vec2(0.5), design_size - vec2(0.5));
			visible_rays += trace_visibility(origin, target, origin_coverage);
		}
		visibility = mix(1.0, visible_rays / float(RAY_COUNT), 1.0 - exp(-2.0 * shadow_strength));
	}
	float normalized_distance = distance_px / falloff_px;
	float radial = 1.0 + normalized_distance * normalized_distance;
	float falloff = (1.0 - smoothstep(reach * 0.72, reach, distance_px)) / (radial * radial);
	// 场景灯顺着原画主光方向更亮。零方向的光源向四周均匀发光。
	float facing = mix(1.0, mix(0.32, 1.0, smoothstep(-0.35, 0.90, dot(-ray, light_dir))), length(light_dir));
	COLOR = vec4(energy.rgb * (strength * visibility * falloff * facing), 1.0);
}
