// 每个发光源在覆盖区域内投五条确定性的视线。距离场决定每步能跳多远。
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 energy;
uniform float reach;
uniform float falloff_px;
uniform vec2 falloff_scale = vec2(1.0);
uniform float source_skip;
uniform float source_width;
uniform float line_half_width;
uniform vec2 light_dir;
uniform vec2 center;
uniform float opacity = 1.0;
uniform float shadow_strength;
uniform float light_fade = 1.0;

#include "res://shaders/gi_trace.gdshaderinc"

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
			visible_rays += trace_visibility(origin, target, origin_coverage, source_skip);
		}
		visibility = mix(1.0, visible_rays / float(RAY_COUNT), 1.0 - exp(-2.0 * shadow_strength));
	}
	// 场景灯纵向照下去，横向收束。点光和岩浆沿用原来的径向衰减。
	vec2 normalized_offset = to_light * falloff_scale / falloff_px;
	float radial = 1.0 + dot(normalized_offset, normalized_offset);
	float falloff = (1.0 - smoothstep(reach * 0.72, reach, distance_px)) / (radial * radial);
	// 场景灯顺着原画主光方向更亮。零方向的光源向四周均匀发光。
	float facing = mix(1.0, mix(0.32, 1.0, smoothstep(-0.35, 0.90, dot(-ray, light_dir))), length(light_dir));
	COLOR = vec4(energy.rgb * (strength * visibility * falloff * facing), 1.0);
}
