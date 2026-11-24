shader_type spatial;
// Car glass: dark tint (you can just make out the cabin) with the same
// fake sky reflection as the paint, strong at grazing angles.
render_mode blend_mix, cull_back;

uniform vec3 tint : source_color = vec3(0.035, 0.045, 0.06);
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
global uniform float night;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"

void fragment() {
	ALBEDO = tint;
	METALLIC = 0.04;
	ROUGHNESS = 0.092;
	SPECULAR = 0.52;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 world_at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Crisp automotive glazing reflection: sharp horizon transition without
	// building window stripes across curved windscreens.
	vec3 sky = reflected_sky(r, world_at, r.y, sky_top, sky_horizon, sun_dir, night);
	vec3 ground = mix(vec3(0.032, 0.036, 0.042), sky_horizon * 0.24, smoothstep(-0.35, 0.0, r.y)) * (1.0 - 0.65 * night);
	vec3 env = mix(ground, sky, smoothstep(-0.025, 0.055, r.y)) * vec3(0.93, 0.98, 1.0);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 5.0);
	float sd = max(dot(r, normalize(sun_dir)), 0.0);
	float glint = pow(sd, 210.0) * 0.43 + pow(sd, 36.0) * 0.045;
	EMISSION = (env * mix(0.08, 0.58, fres) + vec3(glint)) * (1.0 - night * 0.52);
}
