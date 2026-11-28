// Pedestrians walked entirely on the GPU (like traffic.gdshader): each
// MultiMesh instance starts at one end of a pavement segment facing along it;
// INSTANCE_CUSTOM = (speed m/s, phase m, segment length m, lift slope m/m: the
// pavement's rise over the road surface changes along terraced blocks). The body
// slides along local -Z and wraps; the walk cycle poses the limbs
// (person_pose.gdshaderinc). Speed 0 = standing (chatting, window shopping).
// Colours per walker: the top takes the instance colour, skin / legs / hair
// / accessories come from palettes by a per-walker seed. Near the hero
// (global player_pos, set by Player) walkers sidestep and turn to look.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://src/world/shaders/person_pose.gdshaderinc"

global uniform vec3 player_pos;
global uniform float wetness;
global uniform float night;
uniform float crowd_radius = 0.0;  // m round the hero handed to the CPU crowd (0: none)
uniform float pivot_k = 1.0;       // 1.0 male, 0.925 female
// Pavements follow the road surface (+ kerb, in the instance origin).
global uniform sampler2D ground_height : filter_linear, repeat_disable;
global uniform vec4 ground_rect;

varying vec3 v_col;
varying float v_rough;
varying float v_foot_y;
varying flat int v_part;
varying float v_hand;   // 0 inside the CPU crowd's radius .. 1 beyond: dithered hand-over

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 pal8(float s, vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, vec3 c5, vec3 c6, vec3 c7) {
	if (s < 0.125) return c0;
	if (s < 0.250) return c1;
	if (s < 0.375) return c2;
	if (s < 0.500) return c3;
	if (s < 0.625) return c4;
	if (s < 0.750) return c5;
	if (s < 0.875) return c6;
	return c7;
}

vec3 pick(int part, float s, vec3 top) {
	vec3 skin = srgb(pal8(s,
		vec3(0.96, 0.81, 0.70), vec3(0.92, 0.74, 0.60), vec3(0.85, 0.65, 0.50), vec3(0.76, 0.55, 0.40),
		vec3(0.65, 0.45, 0.32), vec3(0.52, 0.35, 0.24), vec3(0.39, 0.26, 0.18), vec3(0.28, 0.19, 0.14)));
	if (part == 1) {
		return skin;
	} else if (part == 9) {
		return skin * vec3(0.78, 0.52, 0.50);
	} else if (part == 2) {
		return srgb(pal8(s,
			vec3(0.15, 0.17, 0.25), vec3(0.10, 0.10, 0.12), vec3(0.26, 0.34, 0.48), vec3(0.58, 0.52, 0.40),
			vec3(0.30, 0.30, 0.31), vec3(0.22, 0.26, 0.22), vec3(0.42, 0.34, 0.26), vec3(0.19, 0.21, 0.28)));
	} else if (part == 3) {
		return srgb(pal8(s,
			vec3(0.05, 0.04, 0.04), vec3(0.14, 0.09, 0.06), vec3(0.28, 0.17, 0.10), vec3(0.44, 0.24, 0.13),
			vec3(0.64, 0.48, 0.28), vec3(0.78, 0.65, 0.40), vec3(0.45, 0.44, 0.43), vec3(0.72, 0.71, 0.70)));
	} else if (part == 4) {
		return top;
	} else if (part == 6) {
		return srgb(pal8(s,
			vec3(0.92, 0.91, 0.89), vec3(0.12, 0.12, 0.14), vec3(0.62, 0.16, 0.19), vec3(0.84, 0.70, 0.36),
			vec3(0.20, 0.32, 0.54), vec3(0.32, 0.42, 0.30), vec3(0.50, 0.36, 0.24), vec3(0.74, 0.72, 0.68)));
	} else if (part == 0) {
		return srgb(pal8(s,
			vec3(0.92, 0.92, 0.90), vec3(0.09, 0.09, 0.10), vec3(0.86, 0.84, 0.80), vec3(0.34, 0.21, 0.13),
			vec3(0.18, 0.21, 0.28), vec3(0.46, 0.30, 0.18), vec3(0.24, 0.24, 0.25), vec3(0.62, 0.18, 0.18)));
	} else if (part == 8) {
		return vec3(0.88);
	}
	return srgb(vec3(0.06, 0.05, 0.05));  // eyes, tights
}

void vertex() {
	float spd = INSTANCE_CUSTOM.x;
	float len = max(INSTANCE_CUSTOM.z, 0.01);
	float d = mod(INSTANCE_CUSTOM.y + TIME * spd, len);
	float seed = fract(INSTANCE_CUSTOM.y * 0.618 + spd * 3.7 + len * 0.137);
	int part = person_part(UV);
	int limb = person_limb(UV);
	v_col = pick(part, fract(seed * (part == 2 ? 7.13 : (part == 3 ? 13.7 : (part == 6 ? 5.31 : (part == 0 ? 3.9 : 1.0))))), COLOR.rgb);
	v_rough = person_surface_roughness(part);
	v_foot_y = VERTEX.y;
	v_part = part;

	// Reaction to the hero: how close (ground level only), which side, where.
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, -d, 1.0)).xyz;
	float gy = texture(ground_height, (wp.xz - ground_rect.xy) / ground_rect.zw).g;
	wp.y += gy;
	vec3 rel = (inverse(MODEL_MATRIX) * vec4(player_pos, 1.0)).xyz - vec3(0.0, 0.0, -d);
	float k = (1.0 - smoothstep(2.0, 7.0, length((player_pos - wp).xz)))
		* (1.0 - smoothstep(2.5, 6.0, abs(player_pos.y - wp.y)));

	float walking = step(0.05, spd);
	float y_scale = max(length(MODEL_MATRIX[1].xyz), 0.5) * pivot_k;
	float ph = walking > 0.5 ? d / (0.80 * y_scale) * 3.14159 : 0.0;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	// Standing people shift their weight and glance about now and then.
	float idle_look = (1.0 - walking) * sin(TIME * 0.4 + seed * 40.0) * 0.5 * step(0.4, sin(TIME * 0.13 + seed * 9.0));
	float a = atan(rel.x, -rel.z);
	person_pose_wk(v, n, limb, UV2.x, 1.0 - UV2.y, ph, walking, 0.0, idle_look + (limb == 5 ? a * k * 0.6 : 0.0), 0.0, pivot_k, seed);
	if (k > 0.001) {
		// Turn towards the hero, and step aside.
		float turn = a * k * 0.35;
		float cs = cos(turn);
		float sn = sin(turn);
		v.xz = vec2(v.x * cs - v.z * sn, v.x * sn + v.z * cs);
		n.xz = vec2(n.x * cs - n.z * sn, n.x * sn + n.z * cs);
		v.x -= (rel.x >= 0.0 ? 1.0 : -1.0) * k * 1.1 * walking;
	}
	// Fade in/out at the segment ends so the wrap isn't a pop.
	// Only far off (a few pixels) or off screen: near and in view a walker
	// shrinking away was plainly visible.
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp + vec3(0.0, 1.0, 0.0), 1.0);
	float onscreen = (clip.w > 0.0 && abs(clip.x / clip.w) < 1.2 && abs(clip.y / clip.w) < 1.2) ? 1.0 : 0.0;
	float far_k = smoothstep(110.0, 140.0, length(CAMERA_POSITION_WORLD - wp));
	float endk = smoothstep(0.0, 1.5, d) * (1.0 - smoothstep(len - 1.5, len, d));
	float s = walking > 0.5 ? mix(1.0, endk, max(1.0 - onscreen, far_k)) : 1.0;
	// Near the hero the CPU crowd (City Empire's Crowd) takes over the
	// pavements: these walkers only carry the streets beyond it.
	// (2026-11-27: a 12 m dithered band, not a hard cut – at 92 m a walker
	// is 15–20 px tall and the cut was a visible pop as you moved.)
	v_hand = crowd_radius > 0.0 ? smoothstep(crowd_radius - 4.0, crowd_radius + 8.0, length((player_pos - wp).xz)) : 1.0;
	s *= step(0.001, v_hand);
	v *= s;
	v.z -= d;
	v.y += (gy + INSTANCE_CUSTOM.w * d) / length(MODEL_MATRIX[1].xyz);  // (instances are scaled)
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	if (v_hand < 0.999) {
		vec2 g = mod(floor(FRAGCOORD.xy), 4.0);
		float bayer = (mod(g.x + g.y * 2.0, 4.0) * 4.0 + mod(g.x * 3.0 + g.y, 4.0)) / 16.0;
		if (v_hand <= bayer) {
			discard;
		}
	}
	float foot_ao = mix(0.68, 1.0, smoothstep(0.02, 0.58, v_foot_y));
	float wet = clamp(wetness, 0.0, 1.0);
	float cloth_wet = v_part == 1 ? 0.06 : 0.18;
	ALBEDO = v_col * foot_ao * (1.0 - cloth_wet * wet);
	ROUGHNESS = mix(v_rough, max(0.24, v_rough - 0.26), wet);
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.6);
	EMISSION = vec3(0.45, 0.58, 0.80) * edge * 0.05 * night;
}
