// 平铺模式下，宽 1 像素的绳芯每走 1 个设计像素，UV.x 增加 1。
shader_type canvas_item;

void fragment() {
	float phase = UV.x * 0.6 + (UV.y - 0.5) * 0.42;
	float distance_to_band = abs(fract(phase + 0.5) - 0.5);
	float pixel_span = fwidth(phase);
	float feather = max(pixel_span * 0.5, 0.02);
	float band = 1.0 - smoothstep(0.17 - feather, 0.17 + feather, distance_to_band);
	band *= 1.0 - smoothstep(0.38, 0.75, pixel_span);
	// 沿用绳芯当前的颜色，冻结和大力状态也有斜纹。
	COLOR.rgb *= mix(vec3(1.0), vec3(0.91, 0.87, 0.83), band);
}
