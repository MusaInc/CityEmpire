shader_type spatial;
render_mode cull_back;
// Brake disc: drilled/slotted cast-iron rotor from the baked rotor map
// (assets/vehicles/tex/rotor_*; planar wheel-face UV, circle = tyre) with
// the lathe rings shaded in wheel space; procedural fallback without UVs.
uniform sampler2D rotor_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rotor_m : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool textured = false;

varying vec3 rotor_point;
void vertex() {
	rotor_point = VERTEX;
}

void fragment() {
	float r = length(rotor_point.yz);
	float ang = atan(rotor_point.z, rotor_point.y);
	float edge = max(length(dFdx(rotor_point.yz)), length(dFdy(rotor_point.yz)));
	float detail = (1.0 - smoothstep(2.0, 8.0, length(VERTEX))) * (1.0 - smoothstep(0.008, 0.036, edge));
	float rings = sin(r * 620.0) * 0.045 + sin(r * 145.0 + 1.0) * 0.11;
	float sweep = smoothstep(0.27, 0.33, r) * (1.0 - smoothstep(0.54, 0.59, r));
	vec3 steel = mix(vec3(0.085, 0.072, 0.060), vec3(0.24, 0.245, 0.255), sweep);
	if (textured) {
		vec4 m = texture(rotor_m, UV);
		ALBEDO = steel * (1.0 + rings * detail) * mix(1.0, m.r, 0.9);
		ROUGHNESS = mix(0.62, m.g, sweep);
		METALLIC = mix(0.72, 0.92, sweep) * m.b;
		NORMAL_MAP = texture(rotor_n, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
		AO = m.r;
	} else {
		float slots = smoothstep(0.92, 0.98, sin(ang * 12.0 + r * 18.0)) * detail * 0.38;
		ALBEDO = steel * (1.0 + rings * detail - slots * sweep);
		ROUGHNESS = mix(0.56, clamp(0.28 + rings * detail * 0.35 + slots * 0.25, 0.18, 0.65), sweep);
		METALLIC = mix(0.76, 0.92, sweep);
	}
	SPECULAR = 0.52;
}
