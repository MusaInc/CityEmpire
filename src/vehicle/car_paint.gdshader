shader_type spatial;
// Automotive base coat and dielectric clearcoat. Godot's sky and local
// probes carry reflections; direct sun glints support the web renderer.
render_mode blend_mix, cull_back;

uniform vec3 base_color : source_color = vec3(0.7);
uniform float metallic = 0.45;
uniform float roughness = 0.3;
uniform float gloss = 1.0;       // 0 matte .. 1 full clear coat
uniform float dirt = 0.0;        // 0 clean .. 1 wrecked
uniform float road_film = 0.0;
uniform bool showroom = false;
global uniform float wetness;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
global uniform float night;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"

uniform float flake = 1.0;       // metallic flake sparkle (0 = solid colour)

varying float v_y;
varying vec3 v_p;

void vertex() {
	v_y = VERTEX.y;  // body-local height above the ground
	v_p = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	float distance_to_lens = length(VERTEX);
	float rain_film = showroom ? 0.0 : wetness;
	float lower = 1.0 - smoothstep(0.29, 0.79, v_y);
	float mottling = 0.52 + 0.12 * hash3(floor(v_p * 9.0));
	float film_detail = mix(0.56, mottling, 1.0 - smoothstep(3.0, 11.0, distance_to_lens));
	float grime = lower * road_film * film_detail;
	float wear = clamp(dirt * 0.76 + grime, 0.0, 0.93);
	vec3 base = mix(base_color, vec3(0.107, 0.087, 0.068), grime * 0.31);
	base = mix(base, vec3(0.068, 0.058, 0.05), dirt * 0.39);
	// Ground-bounce AO: subtle darkening along rocker panels and lower bumper.
	float under_ao = mix(0.74, 1.0, smoothstep(0.06, 0.58, v_y));

	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 world_at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 4.2);

	// Subtle metallic flop: deeper, richer pigment at grazing angles.
	vec3 paint_col = mix(base, base * base * 1.15 + base * 0.18, fres * metallic * 0.45);
	ALBEDO = paint_col * under_ao;
	METALLIC = clamp(metallic * 1.12, 0.0, 0.92) * (1.0 - wear * 0.51);
	ROUGHNESS = clamp(roughness * 0.86 + wear * 0.32 - rain_film * 0.09, 0.10, 0.84);
	SPECULAR = 0.58;
	CLEARCOAT = clamp((gloss * 0.86 + rain_film * 0.18) * (1.0 - wear), 0.0, 1.0);
	CLEARCOAT_ROUGHNESS = clamp(roughness * 0.32 + wear * 0.34 - rain_film * 0.045, 0.05, 0.52);
	if (!showroom) {
		float sd = max(dot(r, normalize(sun_dir)), 0.0);
		float glint = pow(sd, mix(150.0, 220.0, rain_film)) * 0.24 + pow(sd, 28.0) * 0.035;
		// Clearcoat automotive environment reflection (sky, horizon & dark urban band).
		vec3 env_refl = paint_reflection(r, world_at, sky_top, sky_horizon, sun_dir, night);
		float coat_k = clamp((gloss + rain_film * 0.22) * (1.0 - wear), 0.0, 1.0);
		float env_w = mix(0.05, 0.42, fres) * coat_k * mix(0.75, 1.0, under_ao);
		// Flakes must resolve on screen to sparkle. Avoid stipple on a
		// moving bonnet or at the van's large, shallow side angles.
		vec3 cell = v_p * 195.0;
		float resolve = (1.0 - smoothstep(0.7, 1.9, length(fwidth(cell)))) *
			(1.0 - smoothstep(2.2, 5.6, distance_to_lens));
		float fhash = hash3(floor(cell));
		float fine_sparkle = step(0.955, fhash) * pow(sd, 44.0) * 0.18;
		float broad_shimmer = smoothstep(0.72, 0.99, fhash) * pow(sd, 15.0) * 0.055;
		vec3 flake_col = mix(base, vec3(1.0), 0.68) * (fine_sparkle + broad_shimmer) * resolve * flake * metallic * (1.0 - wear);
		vec3 sun_hi = (vec3(glint * coat_k) + flake_col) * (1.0 - night);
		EMISSION = env_refl * env_w * mix(1.0, 0.45, night) + sun_hi;
	}
}
