// 加法叠上金块的自发光和扫光，沿用贴图透明度，扫光止于金块边缘。
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec2 sweep_axis = vec2(0.5);
uniform vec3 sweep = vec3(0.0); // 高光带的位置、强度和宽度倍率
uniform vec4 light_col : source_color = vec4(1.0);

void fragment() {
	if (sweep.y > 0.0) {
		float diagonal = dot(UV - vec2(0.5), sweep_axis) + 0.5;
		float distance = abs(diagonal - sweep.x) / sweep.z;
		float highlight = 1.0 - smoothstep(0.012, 0.095, distance);
		COLOR.rgb += light_col.rgb * (highlight * sweep.y);
	}
}
