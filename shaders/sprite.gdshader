// 物件用的着色器：在图的轮廓外面加一圈描边光。底图颜色和物件接近、看不清时用（比如蓝底上的蓝晶石）。
// 不开描边时和普通的图没有区别，灯光和法线贴图照常起作用。
shader_type canvas_item;

uniform vec4 rim : source_color = vec4(1.0, 1.0, 1.0, 0.0);   // 描边的颜色，透明度为 0 就是不描
uniform float rim_px = 3.0;                                    // 描边宽度（贴图像素）

void fragment() {
	vec4 c = COLOR;
	if (rim.a > 0.0 && c.a < 0.95) {
		float m = 0.0;
		for (int i = 0; i < 12; i++) {             // 往四周两圈各看 12 个方向，附近有图就算在描边里
			float a = float(i) * 0.5235988;
			vec2 d = vec2(cos(a), sin(a)) * rim_px * TEXTURE_PIXEL_SIZE;
			m = max(m, max(texture(TEXTURE, UV + d).a, texture(TEXTURE, UV + d * 0.5).a));
		}
		float ra = smoothstep(0.2, 0.7, m) * rim.a;
		COLOR = vec4(mix(rim.rgb, c.rgb, c.a), max(c.a, ra));
	}
}
