shader_type spatial;
// Car paint: a lit base coat plus a cheap fake clear-coat reflection of the
// actual sky (the Atmosphere's sky_top / sky_horizon globals) with a crisp
// horizon line and a dark "street" below it. Gives bodies the glossy,
// shaped look of real paint on every renderer (incl. the web build), with
// no reflection probes. Dirt/scorch from damage dulls it.
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
	float mottling = 0.56 + 0.20 * sin(31.0 * v_p.z + sin(33.0 * v_p.y)) *
		sin(44.0 * v_p.y + 12.0 * v_p.x);
	float film_detail = mix(0.56, mottling, 1.0 - smoothstep(3.0, 11.0, distance_to_lens));
	float grime = lower * road_film * film_detail;
	float wear = clamp(dirt * 0.76 + grime, 0.0, 0.93);
	vec3 base = mix(base_color, vec3(0.107, 0.087, 0.068), grime * 0.31);
	base = mix(base, vec3(0.068, 0.058, 0.05), dirt * 0.39);

	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	float ao = mix(0.78, 1.0, smoothstep(0.12, 0.73, v_y)) * mix(0.60, 1.0, smoothstep(-0.74, 0.20, n.y));
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// Realistic Schlick clearcoat Fresnel + metallic flop (deeper at grazing
	// angles, crisp metallic sheen face-on without plastic over-saturation).
	float fresnel = pow(1.0 - facing, 5.0);
	float flop = pow(1.0 - facing, 2.2);
	vec3 shade = base * mix(vec3(0.68, 0.70, 0.74), vec3(0.92), sqrt(clamp(base, vec3(0.0), vec3(1.0))));
	ALBEDO = mix(base, shade, metallic * flop * 0.65) * ao;
	METALLIC = metallic * (1.0 - wear * 0.51);
	ROUGHNESS = clamp(roughness + wear * 0.32 - rain_film * 0.081, 0.14, 0.84);
	SPECULAR = 0.52;
	CLEARCOAT = clamp((gloss * 0.64 + rain_film * 0.21) * (1.0 - wear), 0.0, 1.0);
	CLEARCOAT_ROUGHNESS = clamp(roughness * 0.48 + wear * 0.34 - rain_film * 0.041, 0.09, 0.56);
	if (!showroom) {
		vec3 world_at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 env = paint_reflection(r, world_at, sky_top, sky_horizon, sun_dir, night);
		float sd = max(dot(r, normalize(sun_dir)), 0.0);
		float glint = pow(sd, mix(105.0, 170.0, rain_film)) * 0.40 + pow(sd, 24.0) * 0.047;
		// Flakes must resolve on screen to sparkle. Avoid stipple on a
		// moving bonnet or at the van's large, shallow side angles.
		vec3 cell = v_p * 195.0;
		float resolve = (1.0 - smoothstep(0.7, 1.9, length(fwidth(cell)))) *
			(1.0 - smoothstep(2.2, 5.6, distance_to_lens));
		float fhash = hash3(floor(cell));
		float fine_sparkle = step(0.955, fhash) * pow(sd, 44.0) * 0.14;
		float broad_shimmer = smoothstep(0.72, 0.99, fhash) * pow(sd, 15.0) * 0.045;
		vec3 flake_col = mix(base, vec3(1.0), 0.68) * (fine_sparkle + broad_shimmer) * resolve * flake * metallic * (1.0 - wear);
		float coat = mix(0.04, 0.34, fresnel) * (gloss + rain_film * 0.18) * (1.0 - wear);
		EMISSION = min(env * coat + vec3(glint * gloss * (1.0 - wear)) + flake_col, vec3(1.35)) * (1.0 - night * 0.67);
	}
}
