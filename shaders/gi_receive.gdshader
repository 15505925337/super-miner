// 整件物件用中心的受光强度。按原有像素亮度限制增益，保留原画暗部和高光。
shader_type canvas_item;

uniform sampler2D resolved_tex : filter_linear, repeat_disable;
uniform vec2 well_origin;
uniform vec2 well_inv_size;
uniform float bounce_strength;
uniform float light_fade = 1.0;
varying vec2 light_uv;

void vertex() {
	light_uv = (MODEL_MATRIX[3].xy - well_origin) * well_inv_size;
}

void fragment() {
	vec3 bounce = texture(resolved_tex, light_uv).rgb;
	vec3 gain = 0.65 * (1.0 - exp(-bounce * bounce_strength * 0.85));
	float headroom = 1.0 - max(COLOR.r, max(COLOR.g, COLOR.b));
	COLOR.rgb *= 1.0 + gain * headroom * light_fade;
}
