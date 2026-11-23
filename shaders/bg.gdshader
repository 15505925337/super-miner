// 井壁、远景和支架共用调色，保留原画里的明暗分布。
shader_type canvas_item;

uniform vec3 grade = vec3(1.0);    // 伽马、对比度、饱和度

void fragment() {
	if (grade != vec3(1.0)) {
		vec3 c = pow(COLOR.rgb, vec3(1.0 / grade.x));
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c = mix(vec3(l), c, grade.z);
		COLOR.rgb = clamp((c - 0.5) * grade.y + 0.5, 0.0, 1.0);
	}
}
