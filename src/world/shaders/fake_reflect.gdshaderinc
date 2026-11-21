// Fake city reflections (2026-11-21): what glass, paint and chrome mirror,
// worked out per pixel from the reflection direction – no probe, no extra
// render: sky gradient + sun + soft cloud above the horizon, a band of
// skyline silhouettes (two depths, lit windows at night) at it, the dark
// street with lamp dots below. `wp` (world position) slides the skyline as
// things move, so reflections travel across bodywork and facades.

float fr_h(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float fr_h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 city_reflection(vec3 r, vec3 wp, vec3 top, vec3 hor, vec3 sun, float nt) {
	r = normalize(r);
	float az = atan(r.z, r.x) / 6.2832 + (wp.x + wp.z) * 0.0011;
	float y = r.y;
	// Sky.
	vec3 sky = mix(hor, top, smoothstep(0.02, 0.55, y));
	float sd = max(dot(r, normalize(sun)), 0.0);
	sky += hor * pow(sd, 8.0) * 0.6 * (1.0 - nt);
	vec2 cp = r.xz / max(y + 0.25, 0.1) * 1.6 + wp.xz * 0.0004;
	float cl = smoothstep(0.55, 0.8, fr_h2(floor(cp * 3.0)) * 0.5 + fr_h2(floor(cp * 7.0)) * 0.5);
	sky = mix(sky, mix(vec3(1.0), hor, 0.3) * (1.0 - 0.8 * nt), cl * 0.35 * smoothstep(0.03, 0.3, y));
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
		float win = step(0.25, fract(g.x)) * step(0.3, fract(g.y));
		float on = step(0.45, fr_h2(floor(g) + cell));
		vec3 glass = mix(sky * 0.7, vec3(1.0, 0.78, 0.45) * 1.6 * on, nt);
		col = mix(wall * (1.0 - 0.85 * nt), glass, win * 0.55);
	}
	// Street below the horizon: dark, with lamp dots at night.
	if (y < -0.015) {
		vec3 street = mix(vec3(0.045, 0.045, 0.05), hor * 0.18, smoothstep(-0.6, -0.02, y)) * (1.0 - 0.6 * nt);
		float lamp = step(0.93, fr_h(floor(az * 160.0))) * smoothstep(-0.12, -0.03, y) * (1.0 - smoothstep(-0.03, -0.015, y));
		col = street + vec3(1.0, 0.75, 0.42) * lamp * 2.5 * nt;
	}
	return col;
}
