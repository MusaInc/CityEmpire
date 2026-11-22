shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	vec2 edge = abs(UV * 2.0 - 1.0);
	float at_edge = max(edge.x, edge.y);
	ALBEDO = vec3(0.021, 0.016, 0.014);
	ALPHA = 0.27 * (1.0 - smoothstep(0.46, 1.0, at_edge));
}
