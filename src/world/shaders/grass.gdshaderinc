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
	float broad = gr_noise(p / 42.0) * 0.58 + gr_noise(p / 14.0) * 0.28 + gr_noise(p / 4.8 + vec2(3.1, 8.7)) * 0.14;
	float patch = gr_noise(p * 0.62 + vec2(7.1, 4.2));
	float tuft = gr_noise(p * 2.4 + vec2(11.3, 2.9));
	float dry = clamp(terrain * 0.38 + smoothstep(0.36, 0.80, broad) * 0.66, 0.0, 1.0);
	float luminance = dot(base, vec3(0.2126, 0.7152, 0.0722));
	// Natural desaturated olive-emerald turf with dry straw/thatch in sun-baked patches.
	vec3 g = mix(base, vec3(luminance), 0.24)
		* mix(vec3(0.76, 0.83, 0.72), vec3(1.12, 0.90, 0.64), dry);
	g *= 0.78 + 0.28 * patch + 0.12 * tuft;
	// Subtle soil/thatch peeking through worn verges and dry hollows.
	float bare = smoothstep(0.74, 0.92, broad * 0.7 + (1.0 - patch) * 0.3) * clamp(terrain * 0.8 + 0.18, 0.0, 1.0);
	g = mix(g, vec3(0.26, 0.21, 0.14) * (0.85 + 0.3 * tuft), bare * 0.55);

	float detail = closeup * (1.0 - smoothstep(0.045, 0.18, metres_per_pixel));
	vec2 du = dFdx(p / 1.6);
	vec2 dv = dFdy(p / 1.6);
	if (detail > 0.005) {
		vec2 uv = p / 1.6;
		// Second rotated macro-scale sample breaks up any visible tile repetition.
		vec2 uv2 = vec2(p.x * 0.76 - p.y * 0.65, p.x * 0.65 + p.y * 0.76) / 4.7;
		vec3 sample_rgb;
		if (terrain > 1.5) {
			sample_rgb = textureGrad(grass_coast, uv, du, dv).rgb / vec3(0.155, 0.164, 0.043);
		} else {
			float verge = clamp(terrain + smoothstep(0.50, 0.78, broad) * 0.34, 0.0, 1.0);
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
		vec3 macro_rgb = textureGrad(grass_verge, uv2, du * 0.34, dv * 0.34).rgb / vec3(0.147, 0.153, 0.040);
		vec3 combined = mix(sample_rgb, sample_rgb * clamp(macro_rgb, vec3(0.65), vec3(1.35)), 0.38);
		g *= mix(vec3(1.0), clamp(combined, vec3(0.36), vec3(1.80)), detail * 0.82);
	}
	return g;
}
