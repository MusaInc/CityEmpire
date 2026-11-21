// Contact shadow under a traffic/parked car (2026-11-21 cinematic pass): a
// soft dark ellipse on the road where the body meets it, so cars sit on the
// street instead of floating over the shadow map's soft, coarse edge. One
// extra quad in the car's own MultiMesh (no extra draw objects).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float night;
uniform float strength = 0.62;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q * vec2(1.0, 1.0));
	float a = (1.0 - smoothstep(0.35, 1.0, d)) * strength * mix(1.0, 0.7, night);
	ALBEDO = vec3(0.0);
	ALPHA = a;
}
