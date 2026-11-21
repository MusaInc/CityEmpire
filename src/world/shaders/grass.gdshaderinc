// Grass used on the city parks, coastal landforms and airfields. Base colour
// and slow variation are visible at distance. Mipmapped botanical detail
// resolves on foot and along the road, with no per-blade geometry.
global uniform sampler2D grass_lawn : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D grass_coast : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D grass_verge : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

float gr_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float gr_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(gr_hash(i), gr_hash(i + vec2(1.0, 0.0)), f.x), mix(gr_hash(i + vec2(0.0, 1.0)), gr_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// terrain: 0 park, 0..1 airport transition, 2 coastal fescue.
vec3 grass_shade(vec3 base, vec2 p, float closeup, float metres_per_pixel, float terrain) {
	float broad = gr_noise(p / 38.0) * 0.66 + gr_noise(p / 13.0) * 0.34;
	float patch = gr_noise(p * 0.58 + vec2(7.1, 4.2));
	float dry = clamp(terrain * 0.48 + smoothstep(0.44, 0.84, broad) * 0.64, 0.0, 1.0);
	vec3 g = base * mix(vec3(0.90, 1.0, 0.84), vec3(1.16, 0.98, 0.67), dry);
	g *= 0.86 + 0.28 * patch;

	float detail = closeup * (1.0 - smoothstep(0.027, 0.115, metres_per_pixel));
	vec2 du = dFdx(p / 1.6);
	vec2 dv = dFdy(p / 1.6);
	if (detail > 0.005) {
		vec2 uv = p / 1.6;
		vec3 sample_rgb;
		if (terrain > 1.5) {
			sample_rgb = textureGrad(grass_coast, uv, du, dv).rgb / vec3(0.155, 0.164, 0.043);
		} else {
			float verge = clamp(terrain + smoothstep(0.52, 0.78, broad) * 0.31, 0.0, 1.0);
			if (verge >= 0.995) {
				sample_rgb = textureGrad(grass_verge, uv, du, dv).rgb / vec3(0.147, 0.153, 0.040);
			} else {
				sample_rgb = textureGrad(grass_lawn, uv, du, dv).rgb / vec3(0.078, 0.142, 0.012);
				if (verge > 0.005) {
					vec3 parched = textureGrad(grass_verge, uv, du, dv).rgb / vec3(0.147, 0.153, 0.040);
					sample_rgb = mix(sample_rgb, parched, verge);
				}
			}
		}
		g *= mix(vec3(1.0), clamp(sample_rgb, vec3(0.38), vec3(1.85)), detail * 0.78);
	}
	return g;
}
