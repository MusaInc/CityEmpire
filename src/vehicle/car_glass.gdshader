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
	METALLIC = 0.2;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 env = city_reflection(r, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, sky_top, sky_horizon, sun_dir, night);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float glint = pow(max(dot(r, normalize(sun_dir)), 0.0), 300.0) * 8.0;
	EMISSION = (env * mix(0.18, 0.9, fres) + vec3(glint)) * (1.0 - night * 0.5);
}
