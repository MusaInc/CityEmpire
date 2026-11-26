// Fake city reflections (2026-11-21): what glass, paint and chrome mirror,
// worked out per pixel from the reflection direction – no probe, no extra
// render: sky gradient + sun + soft cloud above the horizon, a band of
// skyline silhouettes (two depths, lit windows at night) at it, the dark
// street with lamp dots below. `wp` (world position) slides the skyline as
// things move, so reflections travel across bodywork and facades.

// Real reflections (2026-11-26): when CityReflections' probes are live
// (Medium/High), the engine's own PBR reflection shows the real city –
// Schlick Fresnel and roughness-dependent blur included – so these fakes
// drop to a faint fill (fake_keep) instead of painting a generic skyline
// over it. On Low (refl_probe 0) they carry the look as before.
global uniform float refl_probe;
float fake_keep() { return mix(1.0, 0.2, clamp(refl_probe, 0.0, 1.0)); }

float fr_h(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float fr_h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 reflected_sky(vec3 r, vec3 wp, float y, vec3 top, vec3 hor, vec3 sun, float nt) {
	vec3 sky = mix(hor, top, smoothstep(0.02, 0.55, y));
	float sd = max(dot(r, normalize(sun)), 0.0);
	sky += hor * pow(sd, 8.0) * 0.20 * (1.0 - nt);
	vec2 cp = r.xz / max(y + 0.25, 0.1) * 1.6 + wp.xz * 0.0004;
	// Smooth cloud banks across curved panels; a floored noise grid stamped
	// rectangular patches into the reflected sky on light paint.
	float bank = sin(cp.x * 2.3 + sin(cp.y * 2.1)) + 0.55 * sin(cp.y * 3.6 + cp.x);
	float cl = smoothstep(0.38, 1.35, bank);
	sky = mix(sky, mix(vec3(1.0), hor, 0.3) * (1.0 - 0.8 * nt), cl * 0.35 * smoothstep(0.03, 0.3, y));
	return sky;
}

// A rough clear coat blends distant buildings into a broad horizon band.
// Distinct window cells are reserved for glass and polished metal.
vec3 paint_reflection(vec3 r, vec3 wp, vec3 top, vec3 hor, vec3 sun, float nt) {
	float y = r.y;
	vec3 sky = reflected_sky(r, wp, y, top, hor, sun, nt);
	vec3 street = mix(vec3(0.045), hor * 0.18, smoothstep(-0.6, 0.0, y));
	vec3 skyline = mix(vec3(0.16, 0.17, 0.19), hor * 0.55, 0.5);
	vec3 below = mix(street, skyline, smoothstep(-0.16, 0.06, y)) * (1.0 - 0.65 * nt);
	return mix(below, sky, smoothstep(-0.03, 0.26, y));
}

vec3 city_reflection(vec3 r, vec3 wp, vec3 top, vec3 hor, vec3 sun, float nt) {
	r = normalize(r);
	// Position slides the reflected skyline (a flat facade reflects one
	// direction everywhere: without this a whole tower face mirrored one block
	// as a flat slab, 2026-11-21) – along the face and up it.
	float az = atan(r.z, r.x) / 6.2832 + dot(wp.xz, vec2(0.0013, 0.0009));
	float y = r.y + sin(wp.y * 0.038 + wp.x * 0.009) * 0.014;
	vec3 sky = reflected_sky(r, wp, y, top, hor, sun, nt);
	// Skyline: far blocks (many, lower) and near blocks (fewer, taller).
	float cf = floor(az * 90.0);
	float hf = 0.03 + 0.12 * fr_h(cf) * fr_h(cf + 3.1);
	float cn = floor(az * 28.0 + 0.37);
	float hn = 0.05 + 0.26 * fr_h(cn + 9.7) * step(0.35, fr_h(cn + 1.3));
	vec3 col = sky;
	bool near_b = y < hn;
	bool far_b = y < hf;
	if (near_b || far_b) {
		float cell = near_b ? cn : cf;
		float fx = fract(az * (near_b ? 28.0 : 90.0) + (near_b ? 0.37 : 0.0));
		// Sunlit or shaded face by which way it turns, darker when near.
		float lit = mix(0.55, 1.0, fr_h(cell + 5.0)) * (near_b ? 0.7 : 0.9);
		vec3 wall = mix(vec3(0.16, 0.17, 0.19), hor * 0.55, 0.5) * lit;
		wall = mix(wall, hor * 0.8, (near_b ? 0.15 : 0.45));   // aerial haze
		// Window grid: glass reflecting sky by day, warm lights by night.
		vec2 g = vec2(fx * (near_b ? 9.0 : 5.0), y * (near_b ? 120.0 : 200.0));
		vec2 lit_window = smoothstep(vec2(0.15, 0.20), vec2(0.32, 0.42), fract(g))
			* (1.0 - smoothstep(vec2(0.78), vec2(0.98), fract(g)));
		float win = lit_window.x * lit_window.y;
		float on = step(0.45, fr_h2(floor(g) + cell));
		vec3 glass = mix(sky * 0.7, vec3(1.0, 0.78, 0.45) * 1.6 * on, nt);
		vec3 facade = mix(wall * (1.0 - 0.85 * nt), glass, win * mix(0.26, 0.54, nt));
		col = mix(sky, facade, 1.0 - smoothstep(-0.016, 0.012, y - (near_b ? hn : hf)));
	}
	// Street below the horizon: dark, with lamp dots at night.
	if (y < -0.015) {
		vec3 street = mix(vec3(0.045, 0.045, 0.05), hor * 0.18, smoothstep(-0.6, -0.02, y)) * (1.0 - 0.6 * nt);
		float lamp = step(0.93, fr_h(floor(az * 160.0))) * smoothstep(-0.12, -0.03, y) * (1.0 - smoothstep(-0.03, -0.015, y));
		col = street + vec3(1.0, 0.75, 0.42) * lamp * 2.5 * nt;
	}
	return col;
}
