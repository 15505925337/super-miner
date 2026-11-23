// 低档画质用的"光斑贴图"：不算法线、不用真灯，整屏乘一层明暗。
// 一次画完所有灯，手机和老电脑也带得动。
shader_type canvas_item;
render_mode unshaded, blend_mul;

uniform vec3 ambient = vec3(0.2);
uniform int count = 0;
uniform vec4 lights[12];      // xy 位置（游戏像素），z 半径，w 强度
uniform vec3 colors[12];
uniform vec2 origin = vec2(0.0);   // 这块矩形左上角在游戏坐标里的位置
varying vec2 gpos;

void vertex() {
	gpos = VERTEX + origin;
}

void fragment() {
	vec3 l = ambient;
	for (int i = 0; i < count; i++) {
		float f = clamp(1.0 - distance(gpos, lights[i].xy) / lights[i].z, 0.0, 1.0);
		l += colors[i] * (f * f * (3.0 - 2.0 * f)) * lights[i].w;
	}
	COLOR = vec4(min(l, vec3(1.0)), 1.0);
}
