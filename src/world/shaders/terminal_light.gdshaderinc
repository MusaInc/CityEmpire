// Position relative to the westmost ceiling fixture, in terminal axes.
vec2 terminal_axes(vec3 wp, vec2 anchor) {
	return vec2(wp.z - anchor.y, anchor.x - wp.x);
}

vec2 terminal_fixture_offset(vec2 p) {
	float x = p.x - clamp(round(p.x / 16.0), 0.0, 17.0) * 16.0;
	float z = min(abs(p.y), min(abs(p.y - 18.0), abs(p.y - 38.0)));
	return vec2(x, z);
}

vec3 terminal_irradiance(vec2 p, float up) {
	vec2 d = terminal_fixture_offset(p) * vec2(0.68, 0.48);
	float pool = 1.0 / (1.0 + dot(d, d) * 0.050);
	float apron = smoothstep(-16.0, -7.0, p.y) * (1.0 - smoothstep(54.0, 60.0, p.y));
	return vec3(1.0, 0.96, 0.88) * (0.24 + pool * (0.20 + 0.20 * up)) * apron;
}
