shader_type spatial;
// Transparent tinted automotive glass for all vehicles: see-through head-on
// with crisp sky reflections taking over at grazing angles.
render_mode blend_mix, cull_back;

uniform vec3 tint : source_color = vec3(0.035, 0.045, 0.06);
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
global uniform float night;
global uniform float wetness;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"

#include "res://src/vehicle/car_glass_damage.gdshaderinc"
#include "res://src/world/shaders/fake_cabin.gdshaderinc"
// Sealed shells (no modelled cabin): opaque, with a traced cabin behind the
// pane instead of the paint (2026-11-26).
uniform bool sealed = false;
uniform vec3 body_min = vec3(-0.9, 0.0, -2.2);
uniform vec3 body_max = vec3(0.9, 1.5, 2.2);

void fragment() {
	float cr = glass_crack();
	if (cr < 0.0) {
		discard;
	}
	ALBEDO = mix(tint, vec3(0.72, 0.74, 0.75), cr * 0.8);
	METALLIC = 0.04;
	ROUGHNESS = mix(0.088, 0.13, wetness);
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
	float fres = pow(1.0 - facing, 4.2);
	float sd = max(dot(r, normalize(sun_dir)), 0.0);
	float glint = pow(sd, 240.0) * 0.58 + pow(sd, 36.0) * 0.055;
	EMISSION = (env * mix(0.11, 0.68, fres) + vec3(glint)) * (1.0 - night * 0.46);
	ALPHA = mix(mix(0.30, 0.84, fres), 0.92, cr * 0.85);
	if (sealed) {
		vec3 bmin, bmax;
		cabin_box(body_min, body_max, bmin, bmax);
		vec3 cam_l = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
		vec3 dl = normalize(v_p - cam_l);
		vec3 dw = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
		float through;
		vec3 inside = fake_cabin(v_p, dl, bmin, bmax, cabin_outside(dw, sky_horizon, sky_top, night), through);
		float amb = dot(sky_horizon, vec3(0.3, 0.55, 0.15)) * 1.15 + 0.02;
		EMISSION += mix(inside * amb, inside, through) * vec3(0.80, 0.86, 0.88) * (1.0 - ALPHA) * 1.6;
		ALPHA = mix(1.0, 0.92, cr);
	}
	ROUGHNESS = mix(ROUGHNESS, 0.5, cr);
}
