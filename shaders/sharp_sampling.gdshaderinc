// 调用方用原坐标的梯度选多级缩小图，避免格内取整后缩小时失去抗锯齿。
vec2 sharp_uv(vec2 uv, vec2 texel_size, vec2 dx, vec2 dy) {
	// 旋转后也按贴图两轴各自计算一个屏幕像素覆盖的范围。
	vec2 footprint = vec2(length(vec2(dx.x, dy.x)), length(vec2(dx.y, dy.y))) / texel_size;
	vec2 width = clamp(footprint, vec2(0.0001), vec2(1.0));
	vec2 texel = uv / texel_size;
	vec2 edge = floor(texel + 0.5);
	// 格内对齐到像素中心，只有格子交界附近做双线性过渡。
	return (edge + clamp((texel - edge) / width, vec2(-0.5), vec2(0.5))) * texel_size;
}
