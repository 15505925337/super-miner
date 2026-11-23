// 底图用的着色器。做三件事：
//   1. 把程序生成的井壁质地（裂缝、岩块、土层）叠到手绘底图上——原图在井里那一大块几乎是纯平的；
//   2. 给出凹凸（法线贴图），灯照上去岩壁有明暗起伏，而不是一团平的亮斑；
//   3. 越往深处越暗。压暗的只是底图本身，灯光照上来还是亮的，所以井里是一池一池的光。
shader_type canvas_item;

uniform sampler2D relief : filter_linear, repeat_enable;      // 明暗细节，0.5 = 不变
uniform sampler2D relief_n : filter_linear, repeat_enable;    // 凹凸
uniform float detail = 0.55;          // 明暗细节叠多重
uniform float bump = 1.0;             // 凹凸多强
uniform float surface_y = 240.0;      // 地面线在底图里的位置（像素）
uniform float bottom_y = 1080.0;      // 井底
uniform float top_mul = 0.95;         // 地面线以上保留多少亮度
uniform float deep_mul = 0.5;         // 井底保留多少亮度
uniform float saturation = 1.12;      // 压暗后把颜色提一点，免得发灰
varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

vec2 mirror(vec2 uv) {                // 画面两边、下面多出来的地方是镜像着铺的，质地也跟着镜像
	vec2 m = mod(uv, 2.0);
	return mix(m, 2.0 - m, step(1.0, m));
}

void fragment() {
	vec2 uv2 = mirror(wp / vec2(1920.0, 1080.0));
	float d = texture(relief, uv2).r;
	vec3 c = COLOR.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c *= 1.0 + (d - 0.5) * 2.0 * detail;
	float t = smoothstep(surface_y - 30.0, bottom_y, wp.y);
	COLOR.rgb = c * mix(top_mul, deep_mul, t * (2.0 - t));
	NORMAL_MAP = texture(relief_n, uv2).rgb;
	NORMAL_MAP_DEPTH = bump;
}
