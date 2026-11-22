// Real clouds at the height of the tallest towers (2026-11-21): stacked
// horizontal slices (CloudLayer) whose density comes from drifting world-
// space noise, so they sit in the 3-D world – towers rise into them, they
// slide past as you move and drift with the wind – lit by the sun on top,
// shaded underneath, faded into the horizon and when you fly through.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec3 sun_dir;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform float night;
uniform float cover = 0.45;     // weather: 0 clear .. 1 overcast
uniform float slice = 0.0;      // 0 base .. 1 top of the layer
uniform float dark = 0.0;       // rain clouds
uniform float flight_fade = 0.0;

varying vec3 v_w;

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 wind = TIME * vec2(0.0042, 0.0016);
	vec2 p = v_w.xz / 1100.0 + wind;
	// Billows: broad shapes, cut into puffs by a finer octave; each slice a
	// little smaller than the one below (rounded tops).
	float d = fbm(p) * 0.72 + fbm(p * 3.3 + 7.0 + wind * 2.0) * 0.28;
	float thr = mix(0.66, 0.4, cover) + slice * 0.05;
	float a = smoothstep(thr, thr + 0.1, d);
	float dist = length(v_w.xz - CAMERA_POSITION_WORLD.xz);
	a *= 1.0 - smoothstep(2600.0, 4300.0, dist);
	a *= smoothstep(6.0, 50.0, abs(v_w.y - CAMERA_POSITION_WORLD.y));   // flying through
	float sunh = clamp(sun_dir.y, 0.0, 1.0);
	vec3 lit = mix(vec3(1.0, 0.72, 0.5), vec3(1.0, 0.98, 0.95), smoothstep(0.04, 0.4, sunh));
	vec3 shade = mix(sky_horizon, sky_top, 0.35) * mix(0.9, 0.55, dark);
	float core = smoothstep(thr, thr + 0.32, d);
	// The base slice is the shaded underside, the top slice the sunlit crown.
	vec3 col = mix(lit, shade, core * mix(0.62, 0.18, slice));
	col *= mix(1.0, 0.6, dark);
	col *= mix(1.0, 0.1, night);
	col = mix(col, sky_horizon, smoothstep(900.0, 4000.0, dist) * 0.55);   // aerial perspective
	ALBEDO = col;
	ALPHA = a * mix(0.82, 0.95, cover) * flight_fade;
}
