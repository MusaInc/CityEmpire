// The near crowd (Crowd): the hero-derived bodies, placed by the CPU each
// frame (no sliding here). INSTANCE_CUSTOM = (stride m, seed 0..1, walk
// 0..1, head yaw rad); the instance COLOR is the top's colour. Skin, hair,
// trousers, shoes and accents come from palettes by the seed.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://src/world/shaders/person_pose.gdshaderinc"

varying vec3 v_col;
varying float v_rough;
varying vec3 v_surface;
varying flat int v_part;
varying float v_near;   // 0 at the lens .. 1 from 1.8 m: dithered out up close

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 pal5(float s, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
	return s < 0.2 ? a : (s < 0.4 ? b : (s < 0.6 ? c : (s < 0.8 ? d : e)));
}

void vertex() {
	float seed = INSTANCE_CUSTOM.y;
	int part = person_part(UV);
	v_part = part;
	vec3 skin = srgb(pal5(fract(seed * 1.0), vec3(0.95, 0.78, 0.65), vec3(0.86, 0.66, 0.52), vec3(0.7, 0.5, 0.36),
		vec3(0.52, 0.35, 0.25), vec3(0.34, 0.23, 0.17)));
	if (part == 1) {
		v_col = skin;
	} else if (part == 9) {
		v_col = skin * vec3(0.78, 0.55, 0.52);
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
		v_col = vec3(0.85);
	} else {
		v_col = srgb(vec3(0.06, 0.05, 0.05));
	}
	v_rough = person_surface_roughness(part);
	v_surface = VERTEX;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	person_pose_w(v, n, person_limb(UV), UV2.x, 1.0 - UV2.y, INSTANCE_CUSTOM.x / 0.72 * 3.14159, INSTANCE_CUSTOM.z, 0.0, INSTANCE_CUSTOM.w);
	VERTEX = v;
	NORMAL = n;
	// Someone right in front of the lens dissolves instead of filling the
	// screen (the sidestep keeps it rare; this is the safety net).
	float cd = length((MODELVIEW_MATRIX * vec4(0.0, 0.9, 0.0, 1.0)).xyz);
	v_near = clamp((cd - 0.7) / 1.1, 0.0, 1.0);
}

void fragment() {
	if (v_near < 0.999) {
		vec2 g = mod(floor(FRAGCOORD.xy), 4.0);
		float bayer = (mod(g.x + g.y * 2.0, 4.0) * 4.0 + mod(g.x * 3.0 + g.y, 4.0)) / 16.0;
		if (v_near <= bayer) {
			discard;
		}
	}
	ALBEDO = person_cloth(v_col, v_surface, 1.0 - smoothstep(7.0, 23.0, length(VERTEX)), v_part);
	SPECULAR = v_part == 1 || v_part == 3 ? 0.32 : 0.24;
	ROUGHNESS = v_rough;
}
