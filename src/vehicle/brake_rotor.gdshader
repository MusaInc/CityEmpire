shader_type spatial;
render_mode cull_back;

varying vec3 rotor_point;
void vertex() {
	rotor_point = VERTEX;
}

void fragment() {
	float r = length(rotor_point.yz);
	float edge = max(length(dFdx(rotor_point.yz)), length(dFdy(rotor_point.yz)));
	float detail = (1.0 - smoothstep(2.0, 7.0, length(VERTEX))) * (1.0 - smoothstep(0.008, 0.034, edge));
	float rings = sin(r * 572.0) * 0.036 + sin(r * 131.0 + 1.0) * 0.09;
	float sweep = smoothstep(0.27, 0.33, r) * (1.0 - smoothstep(0.53, 0.58, r));
	vec3 steel = mix(vec3(0.079, 0.068, 0.057), vec3(0.18, 0.18, 0.175), sweep);
	ALBEDO = steel * (1.0 + rings * detail);
	ROUGHNESS = mix(0.59, 0.35 + rings * detail * 0.4, sweep);
	METALLIC = 0.82;
	SPECULAR = 0.43;
}
