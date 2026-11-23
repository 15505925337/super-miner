// 界面面板：参考《八方旅人》那一类界面的做法——暗色半透明的底、上下渐变、细金线双框、四角小装饰、
// 左上一片柔光（像旁边有盏灯照着）、外面一圈柔和的投影。全部用着色器画，放大多少倍都清楚。
shader_type canvas_item;

uniform vec2 size = vec2(300.0, 200.0);          // 整块矩形的大小（含四周留给投影的边）
uniform float pad = 12.0;                         // 四周留给投影的宽度
uniform vec4 top_col : source_color = vec4(0.17, 0.115, 0.085, 0.9);
uniform vec4 bot_col : source_color = vec4(0.05, 0.04, 0.06, 0.94);
uniform vec4 gold : source_color = vec4(0.9, 0.74, 0.44, 1.0);
uniform float sheen = 0.16;                       // 左上柔光的强度
uniform float ornament = 1.0;                     // 1 = 画双框和四角装饰，0 = 只画单线（小面板用）

void fragment() {
	vec2 p = UV * size;
	vec2 s = size - vec2(pad * 2.0);
	vec2 q = p - vec2(pad);
	vec2 d2 = abs(q - s * 0.5) - s * 0.5;
	float inside = -max(d2.x, d2.y);              // 正 = 在面板里，数值是离边的距离
	float outside = length(max(d2, vec2(0.0)));
	if (inside < 0.0) {
		// 投影：往下偏一点，由实到虚
		float d = length(max(abs(q - s * 0.5 - vec2(0.0, 3.0)) - s * 0.5, vec2(0.0)));
		float a = smoothstep(pad, 0.0, d);
		COLOR = vec4(0.02, 0.012, 0.01, a * a * 0.6);
	} else {
		float t = q.y / s.y;
		vec4 base = mix(top_col, bot_col, t);
		vec2 lp = (q - vec2(s.x * 0.16, -6.0)) / vec2(s.x * 0.7, max(s.y * 0.55, 60.0));
		base.rgb += vec3(1.0, 0.84, 0.58) * exp(-dot(lp, lp) * 2.4) * sheen;
		float line = 1.0 - smoothstep(0.55, 1.05, abs(inside - 0.75));
		vec2 c = min(q, s - q);                    // 到最近一个角的横竖距离
		float deco = 0.0;
		if (ornament > 0.5) {
			float corner = step(c.x, 9.0) * step(c.y, 9.0);
			float line2 = (1.0 - smoothstep(0.3, 0.75, abs(inside - 3.6))) * 0.42 * (1.0 - corner);
			float diamond = 1.0 - smoothstep(2.0, 2.8, abs(c.x - 4.2) + abs(c.y - 4.2));
			float dot_in = smoothstep(0.4, 1.0, abs(c.x - 4.2) + abs(c.y - 4.2));
			deco = max(line2, diamond * (0.35 + 0.65 * dot_in));
		}
		float g = max(line, deco);
		vec3 gc = gold.rgb * mix(1.2, 0.62, smoothstep(0.0, 1.0, t)) * mix(1.0, 1.25, exp(-dot(lp, lp) * 1.5));
		base.rgb = mix(base.rgb, gc, g * gold.a);
		base.a = max(base.a, g * gold.a);
		COLOR = base;
	}
	// outside 留着备用（圆角时用）
	COLOR.a *= step(0.0, outside + 1.0);
}
