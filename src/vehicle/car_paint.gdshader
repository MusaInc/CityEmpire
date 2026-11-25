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
// Textures (VehicleTex / tools/blender/ws_texture.py): the clear coat's
// orange peel on UV (1 unit = 1 m; the tile spans 12 cm) and the body's
// Blender bake on UV2 (R ambient occlusion, G convex edges, B cavity).
uniform sampler2D peel_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float peel_scale = 8.3;
uniform float peel_depth = 0.07;
uniform sampler2D bake_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float ao_strength = 0.0;
// Localised damage (CarVisual, from Car.scuff / transfer): scratches and
// bare metal per side (front, rear, left, right) and the paint another car
// left on each side. half_size = the body's half extents (body-local).
uniform vec4 scuff = vec4(0.0);
uniform vec4 transfer_on = vec4(0.0);
uniform vec3 tr_front : source_color = vec3(0.5);
uniform vec3 tr_rear : source_color = vec3(0.5);
uniform vec3 tr_left : source_color = vec3(0.5);
uniform vec3 tr_right : source_color = vec3(0.5);
uniform vec3 half_size = vec3(0.9, 0.75, 2.3);

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

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void fragment() {
	float distance_to_lens = length(VERTEX);
	float rain_film = showroom ? 0.0 : wetness;
	vec3 bk = texture(bake_tex, UV2).rgb;
	float bake_ao = mix(1.0, bk.r, ao_strength);
	float bake_cav = mix(1.0, bk.b, ao_strength);
	float edge = bk.g * ao_strength;
	float lower = 1.0 - smoothstep(0.29, 0.79, v_y);
	float mottling = 0.52 + 0.12 * hash3(floor(v_p * 9.0));
	float film_detail = mix(0.56, mottling, 1.0 - smoothstep(3.0, 11.0, distance_to_lens));
	float grime = lower * road_film * film_detail;
	float wear = clamp(dirt * 0.76 + grime, 0.0, 0.93);
	vec3 base = mix(base_color, vec3(0.107, 0.087, 0.068), grime * 0.31);
	// Road grime and damage gather in the shut lines and recesses first.
	base = mix(base, vec3(0.09, 0.075, 0.06), (1.0 - bake_cav) * (0.25 + road_film * 1.5 + dirt) * 0.5);
	base = mix(base, vec3(0.068, 0.058, 0.05), dirt * 0.39);
	// Stone chips / scrapes on the sharp edges once the car is knocked about.
	float chip = smoothstep(0.45, 0.85, edge) * smoothstep(0.25, 0.8, dirt) * step(0.55, hash3(floor(v_p * 70.0)));
	base = mix(base, vec3(0.42, 0.42, 0.40), chip * 0.85);
	// Collision scratches: long streaks along the panel (lengthwise on the
	// flanks, across on the noses), deeper ones down to primer and bare metal,
	// the other car's colour smeared in between.
	float bare = 0.0;
	if (dot(scuff, vec4(1.0)) > 0.001) {
		vec3 q = v_p / max(half_size, vec3(0.1));
		float hgt = smoothstep(0.08, 0.3, v_y) * (1.0 - smoothstep(0.95, 1.25, v_y));
		float wf = smoothstep(0.55, 0.92, -q.z) * scuff.x;
		float wr = smoothstep(0.55, 0.92, q.z) * scuff.y;
		float wl = smoothstep(0.6, 0.95, -q.x) * scuff.z;
		float wrt = smoothstep(0.6, 0.95, q.x) * scuff.w;
		float side_w = max(wl, wrt);
		float nose_w = max(wf, wr);
		float w_all = max(side_w, nose_w);
		// Where: a few clustered zones (a scrape is local), growing with the
		// amount of scuffing; nothing elsewhere.
		float zone = smoothstep(0.55, 0.85, vnoise3(v_p * 1.3 + 4.0) + w_all * 0.45 - 0.22);
		// What: thin scratch lines along the panel (lengthwise on the flanks,
		// across the noses), only some lines, broken into runs.
		float along = side_w >= nose_w ? v_p.z : v_p.x;
		float ly = v_p.y * 46.0 + vnoise3(vec3(along * 1.7, 0.0, 3.0)) * 3.0;
		float line_w = clamp(fwidth(ly) * 1.2, 0.08, 0.6);
		float l = 1.0 - smoothstep(0.0, line_w, abs(fract(ly) - 0.5) * 2.0 - (1.0 - line_w));
		float gate = step(0.55, hash3(vec3(floor(ly), floor(along * 1.4), 2.0)));
		float near_k = 1.0 - smoothstep(3.0, 10.0, distance_to_lens);
		float s_amt = clamp(l * gate * zone * hgt * w_all * 1.6, 0.0, 1.0) * mix(0.35, 1.0, near_k);
		bare = s_amt * step(0.7, hash3(vec3(floor(ly), floor(along * 4.0), 5.0)));
		vec3 tr = tr_front * transfer_on.x * wf + tr_rear * transfer_on.y * wr + tr_left * transfer_on.z * wl + tr_right * transfer_on.w * wrt;
		float tr_w = clamp(dot(transfer_on, vec4(wf, wr, wl, wrt)), 0.0, 1.0);
		vec3 scratch_col = mix(base * 1.45 + 0.1, tr / max(tr_w, 0.001), tr_w * 0.6);
		// A dull scuffed haze over the zone, sharp scratches on top.
		base = mix(base, base * 1.12 + 0.03, zone * w_all * hgt * 0.35);
		base = mix(base, scratch_col, s_amt * 0.8);
		base = mix(base, vec3(0.6, 0.61, 0.62), bare);
		chip = max(chip, bare);
	}
	// Ground-bounce AO: subtle darkening along rocker panels and lower bumper
	// (the bake carries the real occlusion; this is the fallback).
	float under_ao = mix(mix(0.74, 0.9, ao_strength), 1.0, smoothstep(0.06, 0.58, v_y));

	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 world_at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 4.2);

	// Subtle metallic flop: deeper, richer pigment at grazing angles.
	vec3 paint_col = mix(base, base * base * 1.15 + base * 0.18, fres * metallic * 0.45);
	ALBEDO = paint_col * under_ao;
	float peel_near = 1.0 - smoothstep(2.5, 9.0, distance_to_lens);
	NORMAL_MAP = texture(peel_n, UV * peel_scale).rgb;
	NORMAL_MAP_DEPTH = peel_depth * peel_near * (1.0 - wear * 0.6);
	AO = bake_ao;
	AO_LIGHT_AFFECT = 0.4;
	METALLIC = clamp(metallic * 1.12, 0.0, 0.92) * (1.0 - wear * 0.51) * (1.0 - chip * 0.6);
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
		// (Occluded panels - door shuts, wheel arches, under the bumper - see
		// none of the sky.)
		float env_w = mix(0.05, 0.42, fres) * coat_k * mix(0.75, 1.0, under_ao) * bake_ao * bake_ao;
		// Flakes must resolve on screen to sparkle. Avoid stipple on a
		// moving bonnet or at the van's large, shallow side angles.
		vec3 cell = v_p * 195.0;
		float resolve = (1.0 - smoothstep(0.7, 1.9, length(fwidth(cell)))) *
			(1.0 - smoothstep(2.2, 5.6, distance_to_lens));
		float fhash = hash3(floor(cell));
		float fine_sparkle = step(0.955, fhash) * pow(sd, 44.0) * 0.18;
		float broad_shimmer = smoothstep(0.72, 0.99, fhash) * pow(sd, 15.0) * 0.055;
		vec3 flake_col = mix(base, vec3(1.0), 0.68) * (fine_sparkle + broad_shimmer) * resolve * flake * metallic * (1.0 - wear);
		vec3 sun_hi = (vec3(glint * coat_k) + flake_col) * (1.0 - night) * bake_ao * (1.0 - chip);
		EMISSION = env_refl * env_w * mix(1.0, 0.45, night) + sun_hi;
	}
}
