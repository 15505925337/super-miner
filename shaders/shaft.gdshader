// 矿灯下面的一束光（光柱）：从灯往下散开的柔和扇形，叠加在画面上，里面有缓慢流动的明暗。
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.36, 1.0);
uniform float strength = 0.22;
uniform float half_angle = 0.62;     // 扇形半张角（弧度）
uniform float seed = 0.0;

void fragment() {
	// UV 的 (0.5, 0) 是灯的位置，往下是光柱
	vec2 p = vec2(UV.x - 0.5, UV.y);
	float d = length(p);
	float a = abs(atan(p.x, p.y));
	float cone = smoothstep(half_angle, half_angle * 0.25, a);
	float fall = smoothstep(1.0, 0.0, d) * smoothstep(0.0, 0.06, d);
	float streak = 0.75 + 0.25 * sin(atan(p.x, p.y) * 23.0 + seed * 7.0 + TIME * 0.35) * sin(atan(p.x, p.y) * 9.0 - TIME * 0.2 + seed);
	COLOR = vec4(tint.rgb * cone * fall * fall * streak * strength, COLOR.a);
}
