shader_type spatial;
// See-through car glass for bodies with a modelled cabin (the Kestrel,
// tools/blender/kestrel.py): car_glass's tint and fake sky reflection, with
// the cabin showing through head-on and the sky taking over at grazing angles.
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
	ROUGHNESS = 0.05;
	SPECULAR = 0.65;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 world_at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 sky = reflected_sky(r, world_at, r.y, sky_top, sky_horizon, sun_dir, night);
	vec3 ground = mix(vec3(0.03, 0.034, 0.04), sky_horizon * 0.22, smoothstep(-0.32, 0.0, r.y)) * (1.0 - 0.65 * night);
	vec3 env = mix(ground, sky, smoothstep(-0.02, 0.045, r.y)) * vec3(0.94, 0.98, 1.0);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 4.0);
	float sd = max(dot(r, normalize(sun_dir)), 0.0);
	float glint = pow(sd, 240.0) * 0.78 + pow(sd, 40.0) * 0.06;
	EMISSION = (env * mix(0.08, 0.56, fres) + vec3(glint)) * (1.0 - night * 0.62);
	ALPHA = mix(0.32, 0.92, fres);
}
