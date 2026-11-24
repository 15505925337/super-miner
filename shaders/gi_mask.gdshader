// 用原图透明度在黑底上画白色遮挡，忽略贴图的颜色。
shader_type canvas_item;
render_mode unshaded;

void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, COLOR.a);
}
