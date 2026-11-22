// Weather-driven sky with a high veil and a lower layer with lit cloud edges.
shader_type sky;
render_mode use_debanding, use_half_res_pass, disable_fog;

uniform vec3 zenith : source_color = vec3(0.24, 0.42, 0.72);
uniform vec3 horizon : source_color = vec3(0.84, 0.8, 0.78);
uniform vec3 haze : source_color = vec3(1.0, 0.66, 0.42);
uniform vec3 ground : source_color = vec3(0.32, 0.3, 0.3);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.86, 0.72);
uniform vec3 cloud_shade : source_color = vec3(0.56, 0.55, 0.64);
uniform float cloud_cover = 0.45;
// Set by Atmosphere as the day turns and the weather changes:
uniform float sun_glow = 1.0;      // halo strength round LIGHT0 (sun by day, moon at night)
uniform float disc_size = 0.999989; // cosine of the angular radius
uniform float disc_k = 6.0;
uniform float stars = 0.0;         // 0..1 star field (night, clear sky)
uniform float flash = 0.0;         // lightning
uniform float cloud_dark = 0.0;    // 0..1 rain clouds: heavier, lower, darker
uniform vec3 sky_fog_tint : source_color = vec3(0.66, 0.75, 0.85);
uniform float sky_fog_amount = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = mat2(vec2(1.65, 1.24), vec2(-1.24, 1.65)) * p + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float cloud_density(vec2 p, float threshold) {
	float density = fbm(p);
	float edge = vnoise(p * 6.0 + vec2(37.0, 8.0));
	return density - threshold - edge * 0.06;
}

vec3 cloud_masks(vec3 d, vec3 light_dir) {
	if (d.y <= 0.0) {
		return vec3(0.0);
	}
	float elevation = d.y;
	float forward_scatter = pow(max(dot(d, light_dir), 0.0), 5.0) * sun_glow;
	// High, wind-streaked ice cloud. It recedes into the haze over the horizon.
	vec2 upper = d.xz / (elevation + 0.14);
	upper = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * upper;
	upper *= vec2(0.58, 2.3);
	upper += vec2(-12.2, 14.2) + TIME * vec2(0.0018, 0.0007);
	float veil = smoothstep(0.46, 0.68, fbm(upper) + 0.11 * vnoise(upper * 3.0));
	float high_alpha = veil * smoothstep(0.02, 0.35, elevation) * (1.0 - 0.8 * cloud_dark) * 0.32;

	// View through the lower layer. Its longer path at a low elevation
	// brings clouds closer together near the horizon.
	vec2 lower = d.xz / (elevation + 0.12) * 1.35;
	lower += vec2(13.2, 5.55) + TIME * vec2(0.004, 0.0017) * (1.0 + cloud_dark);
	float threshold = mix(0.66, 0.225, cloud_cover);
	float density = cloud_density(lower, threshold);
	float optical_depth = max(density, 0.0) * mix(9.0, 19.0, cloud_dark) / (0.65 + 0.35 * elevation);
	float low_alpha = (1.0 - exp2(-optical_depth)) * smoothstep(0.012, 0.15, elevation);

	// Approximate the light path through a billow with one offset density
	// sample. Thin edges catch the sun while overlapping lobes stay shaded.
	vec2 towards_light = light_dir.xz / max(light_dir.y + 0.32, 0.25) * 0.23;
	float ahead = cloud_density(lower + towards_light, threshold);
	float lit_edge = clamp(0.45 + (density - ahead) * 4.5 - max(density, 0.0) * 1.25, 0.0, 1.0);
	lit_edge = clamp(lit_edge + forward_scatter * (1.0 - low_alpha) * 0.55, 0.0, 1.0);
	// RGB carries the masks with enough precision in Mobile's sky buffer.
	// Weight the lighting by coverage so thin edges interpolate cleanly.
	return vec3(low_alpha, high_alpha, low_alpha * lit_edge);
}

vec3 sky_colour(vec3 d, vec3 sun_dir, bool cubemap, vec3 cloud) {
	float h = d.y;
	float sd = max(dot(d, sun_dir), 0.0);
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon, zenith, pow(h, 0.45));
		// Warm haze hugging the horizon, stronger toward the sun.
		col = mix(col, haze, exp(-h * 12.0) * (0.15 + 0.6 * pow(sd, 3.0)));
	} else {
		col = mix(horizon * 0.9, ground, clamp(-h * 4.0, 0.0, 1.0));
	}
	col += sun_tint * (pow(sd, 6.0) * 0.35 + pow(sd, 64.0) * 0.6) * sun_glow;
	float disc = 0.0;
	if (cubemap) {
		// The light probes only need the broad loss of sky colour under cloud.
		float overcast = smoothstep(0.48, 0.98, cloud_cover) * smoothstep(0.0, 0.4, h);
		col = mix(col, mix(cloud_shade, cloud_lit, 0.35), overcast * 0.7);
	} else {
		float disc_aa = max(fwidth(sd) * 0.7, 0.000001);
		disc = smoothstep(disc_size - disc_aa, disc_size + disc_aa, sd);
		if (stars > 0.0 && h > 0.0) {
			// Stars: a hashed cell grid on the sky dome, twinkling a little.
			vec2 sp = vec2(atan(d.x, d.z) * 180.0, asin(clamp(h, 0.0, 1.0)) * 180.0);
			vec2 id = floor(sp);
			float r = hash12(id);
			vec2 f = fract(sp) - vec2(hash12(id + 7.1), hash12(id + 3.3)) * 0.6 - 0.2;
			float st = step(0.985, r) * (1.0 - smoothstep(0.0, 0.09, length(f))) * (0.6 + 0.4 * sin(TIME * (1.0 + r * 3.0) + r * 40.0));
			col += vec3(0.85, 0.9, 1.0) * st * stars * 1.6 * smoothstep(0.0, 0.25, h);
		}
		vec3 high_light = mix(cloud_shade, cloud_lit, 0.77 + pow(sd, 5.0) * sun_glow * 0.18);
		float lit_edge = clamp(cloud.b / max(cloud.r, 0.001), 0.0, 1.0);
		vec3 low_light = mix(cloud_shade, cloud_lit, lit_edge) * mix(1.0, 0.58, cloud_dark);
		low_light = mix(low_light, horizon, (1.0 - smoothstep(0.03, 0.42, h)) * 0.34);
		low_light += vec3(0.75, 0.8, 1.0) * flash * 0.6;
		col = mix(mix(col, high_light, cloud.g), low_light, cloud.r);
		disc *= (1.0 - cloud.r) * (1.0 - cloud.g);
	}
	col += sun_tint * disc * disc_k + vec3(0.75, 0.8, 1.0) * flash * 0.25 * max(h, 0.0);
	if (!cubemap) {
		// Apply fog only to the finished sky. The subpass stores data masks.
		float haze_weight = mix(1.0, 0.55, smoothstep(0.0, 0.75, h));
		col = mix(col, sky_fog_tint, sky_fog_amount * haze_weight);
	}
	return col;
}

void sky() {
	if (AT_HALF_RES_PASS) {
		COLOR = AT_CUBEMAP_PASS ? vec3(0.0) : cloud_masks(EYEDIR, LIGHT0_DIRECTION);
		ALPHA = 1.0;
	} else {
		vec3 cloud = AT_CUBEMAP_PASS ? vec3(0.0) : clamp(HALF_RES_COLOR.rgb, vec3(0.0), vec3(1.0));
		COLOR = sky_colour(EYEDIR, LIGHT0_DIRECTION, AT_CUBEMAP_PASS, cloud);
	}
}
