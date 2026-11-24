// 跳跃泛洪。把最近轮廓点的整数坐标编码进 RGBA8，空点用全零表示。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_nearest, repeat_disable;
uniform ivec2 design_size;
uniform int jump;

vec2 encode_axis(float coord) {
	float hi = floor(coord / 256.0);
	return vec2(coord - hi * 256.0, hi) / 255.0;
}

vec2 decode_seed(vec4 packed_seed) {
	return vec2(dot(packed_seed.rg, vec2(255.0, 65280.0)) - 1.0,
			dot(packed_seed.ba, vec2(255.0, 65280.0)));
}

bool in_well(ivec2 cell) {
	return all(greaterThanEqual(cell, ivec2(0))) && all(lessThan(cell, design_size));
}

bool solid_at(ivec2 cell) {
	return in_well(cell) && texelFetch(src, cell, 0).r >= 0.20;
}

void fragment() {
	ivec2 cell = ivec2(UV * vec2(design_size));
	vec4 best = vec4(0.0);
	if (jump == 0) {
		// 只标记边界。内部点也可由距离场快速步进出去。
		if (solid_at(cell) && (!solid_at(cell + ivec2(1, 0)) || !solid_at(cell - ivec2(1, 0))
				|| !solid_at(cell + ivec2(0, 1)) || !solid_at(cell - ivec2(0, 1)))) {
			best = vec4(encode_axis(float(cell.x) + 1.0), encode_axis(float(cell.y)));
		}
	} else {
		float best_d2 = 1000000.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				ivec2 neighbor = cell + ivec2(x, y) * jump;
				if (!in_well(neighbor)) {
					continue;
				}
				vec4 candidate = texelFetch(src, neighbor, 0);
				vec2 seed = decode_seed(candidate);
				if (seed.x < -0.5) {
					continue;
				}
				vec2 delta = seed - vec2(cell);
				float d2 = dot(delta, delta);
				if (d2 < best_d2) {
					best_d2 = d2;
					best = candidate;
				}
			}
		}
	}
	COLOR = best;
}
