// Contact shadows for the near crowd (Crowd): one soft dark disc under each
// walker, drawn as a single MultiMesh of flat quads. The crowd casts no real
// shadows (too costly for dozens of people on a phone); without this they
// looked pasted onto the pavement. INSTANCE_CUSTOM.x = strength (0..1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

varying float v_k;

void vertex() {
	v_k = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Elliptical (longer front to back, under the stride), soft edged.
	float r = length(p * vec2(1.0, 0.8));
	float a = (1.0 - smoothstep(0.25, 1.0, r)) * 0.42 * v_k;
	ALBEDO = vec3(0.02, 0.025, 0.03);
	ALPHA = a;
}
