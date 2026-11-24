// 所有轮廓只沿本层主光投一块影子。光源颜色由另外的缓冲计算。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform vec2 key_direction = vec2(0.0, 1.0);
uniform float wall_shadow_strength = 1.0;
uniform float daylight = 1.0;

#include "res://shaders/gi_trace.gdshaderinc"

void fragment() {
	float shadow = 0.0;
	if (daylight > 0.0 && wall_shadow_strength > 0.0) {
		vec2 origin = UV * design_size;
		vec2 ray = -key_direction;
		float edge_x = ray.x < 0.0 ? origin.x - 0.5 : design_size.x - 0.5 - origin.x;
		float reach = min(SHADOW_FADE_END, min(edge_x / max(abs(ray.x), 0.001), (origin.y - 0.5) / -ray.y));
		float visibility = trace_visibility(origin, origin + ray * reach, sample_field(origin).b);
		shadow = (1.0 - visibility) * wall_shadow_strength;
	}
	COLOR = vec4(shadow, 0.0, 0.0, 1.0);
}
