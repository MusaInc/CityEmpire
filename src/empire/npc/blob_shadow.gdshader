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
	// Tight inner foot-contact core + soft elliptical stride penumbra.
	float r = length(p * vec2(1.05, 0.82));
	float soft = 1.0 - smoothstep(0.18, 1.0, r);
	float core = 1.0 - smoothstep(0.05, 0.55, r);
	float a = clamp(soft * 0.42 + core * 0.34, 0.0, 0.72) * v_k;
	ALBEDO = vec3(0.012, 0.015, 0.022);
	ALPHA = a;
}
