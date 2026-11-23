// 商店的整屏场景：暖棕色的木板后墙、一层货架、一张柜台、两盏灯的暖光。全部用着色器画。
// 以后有了商店的背景图，换成图即可；现在先用它把"站在店里"的感觉立起来。
shader_type canvas_item;

uniform vec2 size = vec2(640.0, 360.0);
uniform float shelf_y = 196.0;       // 货架板的上沿
uniform float counter_y = 292.0;     // 柜台的上沿
uniform float flicker = 1.0;         // 灯光的摇曳（由脚本每帧给）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * size;
	// 后墙：竖着的木板，板缝发暗，每块板深浅不一
	float w = 46.0;
	float id = floor(p.x / w);
	float fx = fract(p.x / w) * w;
	float seam = 1.0 - smoothstep(0.0, 1.6, min(fx, w - fx));
	vec3 col = mix(vec3(0.15, 0.1, 0.07), vec3(0.085, 0.058, 0.05), p.y / size.y);
	col *= 0.9 + 0.16 * hash(vec2(id, 3.0));
	col += 0.006 * sin(p.y * 0.31 + hash(vec2(id, 1.0)) * 30.0);
	col *= 1.0 - seam * 0.55;
	// 货架：一块横板，上沿受光，板下面有一道阴影
	float sy = p.y - shelf_y;
	if (sy >= 0.0 && sy < 7.0) {
		col = mix(vec3(0.42, 0.26, 0.14), vec3(0.24, 0.14, 0.08), sy / 7.0);
		col += vec3(0.3, 0.2, 0.1) * (1.0 - smoothstep(0.0, 1.4, sy));
		col *= 0.92 + 0.1 * hash(vec2(floor(p.x / 3.0), 7.0));
	} else if (sy >= 7.0) {
		col *= 1.0 - 0.5 * (1.0 - smoothstep(7.0, 26.0, sy));
	}
	// 两盏灯的暖光：一盏照着掌柜，一盏照着货架
	vec2 l1 = (p - vec2(96.0, 96.0)) / vec2(190.0, 170.0);
	vec2 l2 = (p - vec2(404.0, 120.0)) / vec2(300.0, 150.0);
	float light = exp(-dot(l1, l1) * 2.2) * 0.95 + exp(-dot(l2, l2) * 2.0) * 0.8;
	col += col * vec3(2.6, 1.9, 1.1) * light * flicker;
	col += vec3(0.09, 0.055, 0.02) * light * flicker;
	// 柜台：正面一块深色的木头，台面的边受光
	float cy = p.y - counter_y;
	if (cy >= 0.0) {
		vec3 wood = mix(vec3(0.3, 0.18, 0.1), vec3(0.11, 0.07, 0.05), smoothstep(0.0, 70.0, cy));
		wood *= 0.9 + 0.12 * hash(vec2(floor(p.y / 2.0), floor(p.x / 90.0)));
		wood += vec3(0.42, 0.28, 0.13) * (1.0 - smoothstep(0.0, 2.2, cy)) * (0.5 + light);
		wood *= 1.0 - 0.35 * smoothstep(2.0, 5.0, cy) * (1.0 - smoothstep(5.0, 9.0, cy));
		col = wood;
	}
	// 四角压暗
	vec2 q = UV - 0.5;
	col *= 1.0 - 0.55 * smoothstep(0.35, 0.75, length(q * vec2(1.0, 1.15)));
	COLOR = vec4(col, 0.97);
}
