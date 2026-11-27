// The near crowd (Crowd): the hero-derived bodies, placed by the CPU each
// frame (no sliding here). INSTANCE_CUSTOM = (stride m, seed 0..1, walk
// 0..1, head yaw rad); the instance COLOR is the top's colour. Skin, hair,
// trousers, shoes and accents come from palettes by the seed.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://src/world/shaders/person_pose.gdshaderinc"

global uniform float wetness;
global uniform float night;
uniform float pivot_k = 1.0;  // 1.0 for male bodies, 0.925 for female bodies

varying vec3 v_col;
varying float v_rough;
varying vec3 v_surface;
varying vec3 v_norm_l;
varying flat int v_part;
varying float v_near;   // 0 at the lens .. 1 from 1.8 m: dithered out up close
varying float v_fade;   // spawn fade-in (Crowd packs 16 steps into the seed's whole part)

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 pal5(float s, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
	return s < 0.2 ? a : (s < 0.4 ? b : (s < 0.6 ? c : (s < 0.8 ? d : e)));
}

void vertex() {
	// Unpack INSTANCE_CUSTOM.y: whole part = fade_step (0..16) + pose_mode * 32.
	float raw_y = INSTANCE_CUSTOM.y;
	float pose_f = floor(raw_y / 32.0);
	int pose_mode = int(pose_f + 0.5);
	float rem_y = raw_y - pose_f * 32.0;
	float kk = floor(rem_y);
	float seed = rem_y - kk;
	v_fade = 1.0 - kk / 16.0;
	int part = person_part(UV);
	v_part = part;
	vec3 skin = srgb(pal5(fract(seed * 1.0), vec3(0.95, 0.78, 0.65), vec3(0.86, 0.66, 0.52), vec3(0.7, 0.5, 0.36),
		vec3(0.52, 0.35, 0.25), vec3(0.34, 0.23, 0.17)));
	if (part == 1) {
		v_col = skin;
	} else if (part == 9) {
		v_col = skin * vec3(0.76, 0.52, 0.50);
	} else if (part == 2) {
		v_col = srgb(pal5(fract(seed * 7.13), vec3(0.16, 0.18, 0.26), vec3(0.1, 0.1, 0.11), vec3(0.3, 0.38, 0.52),
			vec3(0.6, 0.54, 0.42), vec3(0.32, 0.31, 0.3)));
	} else if (part == 3) {
		v_col = srgb(pal5(fract(seed * 13.7), vec3(0.06, 0.05, 0.04), vec3(0.22, 0.13, 0.08), vec3(0.4, 0.26, 0.15),
			vec3(0.76, 0.62, 0.36), vec3(0.6, 0.58, 0.56)));
	} else if (part == 4) {
		v_col = COLOR.rgb;
	} else if (part == 6) {
		v_col = srgb(pal5(fract(seed * 5.31), vec3(0.92, 0.92, 0.9), vec3(0.12, 0.12, 0.14), vec3(0.62, 0.15, 0.18),
			vec3(0.85, 0.72, 0.4), vec3(0.2, 0.32, 0.55)));
	} else if (part == 0) {
		v_col = srgb(pal5(fract(seed * 3.9), vec3(0.92, 0.92, 0.9), vec3(0.09, 0.09, 0.1), vec3(0.95, 0.95, 0.93),
			vec3(0.35, 0.22, 0.13), vec3(0.2, 0.22, 0.28)));
	} else if (part == 8) {
		v_col = vec3(0.88);
	} else {
		v_col = srgb(vec3(0.06, 0.05, 0.05));
	}
	v_rough = person_surface_roughness(part);
	v_surface = VERTEX;
	v_norm_l = NORMAL;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	int limb = person_limb(UV);
	// Match stride length to this instance's scaled leg excursion (zero foot slip across height scales).
	float z_scale = max(length(MODEL_MATRIX[2].xyz), 0.5);
	float ph = INSTANCE_CUSTOM.x / (0.82 * z_scale) * 3.14159;
	if (pose_mode == 2) {
		person_pose_activity(v, n, limb, UV2.x, 1.0 - UV2.y, ph, 0.0, INSTANCE_CUSTOM.w, 2, pivot_k, TIME, seed);
		person_pose_idle(v, n, limb, UV2.x, 1.0 - UV2.y, 0.0, 0.0, TIME, seed);
	} else {
		person_pose_w(v, n, limb, UV2.x, 1.0 - UV2.y, ph, INSTANCE_CUSTOM.z, 0.0, INSTANCE_CUSTOM.w, COLOR.a);
		person_pose_idle(v, n, limb, UV2.x, 1.0 - UV2.y, INSTANCE_CUSTOM.z, 0.0, TIME, seed);
		if (pose_mode > 0) {
			person_pose_activity(v, n, limb, UV2.x, 1.0 - UV2.y, ph, INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w, pose_mode, pivot_k, TIME, seed);
		}
	}
	VERTEX = v;
	NORMAL = n;
	// Someone right in front of the lens dissolves instead of filling the
	// screen (the sidestep keeps it rare; this is the safety net).
	float cd = length((MODELVIEW_MATRIX * vec4(0.0, 0.9, 0.0, 1.0)).xyz);
	v_near = clamp((cd - 0.7) / 1.1, 0.0, 1.0) * clamp(v_fade, 0.0, 1.0);
}

void fragment() {
	if (v_near < 0.999) {
		vec2 g = mod(floor(FRAGCOORD.xy), 4.0);
		float bayer = (mod(g.x + g.y * 2.0, 4.0) * 4.0 + mod(g.x * 3.0 + g.y, 4.0)) / 16.0;
		if (v_near <= bayer) {
			discard;
		}
	}
	vec3 base_c = v_col;
	// Subtle procedural facial depth on skin (under-chin, eye-socket, cheek warmth) so faces don't read flat.
	if (v_part == 1 && v_surface.y > 1.46 * pivot_k) {
		float under = smoothstep(-0.1, -0.7, v_norm_l.y);
		float side = abs(v_norm_l.x);
		float cheek = smoothstep(0.35, 0.85, side) * smoothstep(1.56 * pivot_k, 1.66 * pivot_k, v_surface.y);
		base_c *= mix(1.0, 0.82, under * 0.65);
		base_c = mix(base_c, base_c * vec3(1.06, 0.94, 0.92), cheek * 0.28);
	}
	vec3 albedo = person_cloth(base_c, v_surface, 1.0 - smoothstep(7.0, 23.0, length(VERTEX)), v_part);
	// Glacier/RE4-style vertical ground-bounce AO: grounds feet and hems onto the street.
	float foot_ao = mix(0.68, 1.0, smoothstep(0.02, 0.58, v_surface.y));
	float wet = clamp(wetness, 0.0, 1.0);
	// Wet rain darkening on clothing/hair and damp sheen on skin/fabric.
	float cloth_wet = v_part == 1 ? 0.06 : 0.18;
	ALBEDO = albedo * foot_ao * (1.0 - cloth_wet * wet);
	SPECULAR = mix(v_part == 1 || v_part == 3 ? 0.34 : 0.24, 0.56, wet * 0.65);
	ROUGHNESS = mix(v_rough, max(0.24, v_rough - 0.26), wet);
	// Warm dermal subsurface scattering on skin so faces/hands don't look plastic.
	if (v_part == 1 || v_part == 9) {
		BACKLIGHT = ALBEDO * vec3(0.36, 0.13, 0.06);
	}
	// Subtle cool rim separation at night so walkers read cleanly against dark alleys.
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.6);
	RIM = 0.18 + 0.24 * night;
	RIM_TINT = 0.35;
	EMISSION = vec3(0.45, 0.58, 0.80) * edge * 0.055 * night;
}
