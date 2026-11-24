// 发光源只提供平滑照明。井壁的影子统一由主光方向计算。
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec2 design_size;
uniform vec4 energy;
uniform float reach;
uniform float falloff_px;
uniform vec2 falloff_scale = vec2(1.0);
uniform float line_half_width;
uniform vec2 light_dir;
uniform vec2 center;
uniform float opacity = 1.0;
uniform float light_fade = 1.0;

void fragment() {
	float strength = energy.a * opacity * light_fade;
	if (strength <= 0.0) {
		discard;
	}
	vec2 origin = SCREEN_UV * design_size;
	vec2 to_light = center - origin;
	// 岩浆是整条光带，取接收点下方最近的位置。
	to_light.x -= clamp(to_light.x, -line_half_width, line_half_width);
	float distance_px = length(to_light);
	if (distance_px >= reach) {
		discard;
	}
	vec2 ray = to_light / max(0.001, distance_px);

	// 场景灯纵向照下去，横向收束。点光和岩浆沿用原来的径向衰减。
	vec2 normalized_offset = to_light * falloff_scale / falloff_px;
	float radial = 1.0 + dot(normalized_offset, normalized_offset);
	float falloff = (1.0 - smoothstep(reach * 0.72, reach, distance_px)) / (radial * radial);
	// 场景灯顺着原画主光方向更亮。零方向的光源向四周均匀发光。
	float facing = mix(1.0, mix(0.32, 1.0, smoothstep(-0.35, 0.90, dot(-ray, light_dir))), length(light_dir));
	COLOR = vec4(energy.rgb * (strength * falloff * facing), 1.0);
}
