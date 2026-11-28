// Contact shadow under a traffic/parked car (2026-11-21 cinematic pass): a
// soft dark ellipse on the road where the body meets it, so cars sit on the
// street instead of floating over the shadow map's soft, coarse edge. One
// extra quad in the car's own MultiMesh (no extra draw objects).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float night;
uniform float strength = 0.72;

void vertex() {
	// Mirror traffic.gdshader's INSTANCE_CUSTOM longitudinal offset so parked-car
	// contact shadows sit directly under the car instead of 5 m behind it.
	float spd = INSTANCE_CUSTOM.r;
	float phase = INSTANCE_CUSTOM.g;
	float span = max(INSTANCE_CUSTOM.b, 0.001);
	float d = mod(TIME * spd + phase, span);
	VERTEX.z -= d;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	vec2 d = abs(q) - vec2(0.58, 0.68);
	float box_d = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
	float body_ao = 1.0 - smoothstep(-0.08, 0.36, box_d);
	float core_ao = 1.0 - smoothstep(-0.18, 0.14, box_d);
	float a = clamp(body_ao * 0.62 + core_ao * 0.42, 0.0, 1.0) * strength * mix(1.0, 0.54, night);
	ALBEDO = vec3(0.01, 0.012, 0.016);
	ALPHA = a;
}
