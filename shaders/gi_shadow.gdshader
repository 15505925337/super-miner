// 物件只沿本层主光投影，R 记录命中，G 记录下沿至接收点的距离。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform vec2 key_direction = vec2(0.0, 1.0);
uniform float wall_shadow_strength = 1.0;
uniform float daylight = 1.0;

#include "res://shaders/gi_trace.gdshaderinc"

const float SHADOW_REACH = 76.0;

void fragment() {
	vec2 blocker = vec2(0.0);
	if (daylight > 0.0 && wall_shadow_strength > 0.0) {
		vec2 origin = UV * design_size;
		vec2 ray = -key_direction;
		float edge_x = ray.x < 0.0 ? origin.x - 0.5 : design_size.x - 0.5 - origin.x;
		float reach = min(SHADOW_REACH, min(edge_x / max(abs(ray.x), 0.001), (origin.y - 0.5) / -ray.y));
		float distance_px = blocker_distance(origin, ray, reach);
		if (distance_px >= 0.0) {
			blocker = vec2(1.0, distance_px / SHADOW_REACH);
		}
	}
	COLOR = vec4(blocker, 0.0, 1.0);
}
