// Shared by the street walkers (pedestrian.gdshader) and the people in the
// shops (npc.gdshader): the four body types of tools/blender/build_street.py
// carry, per vertex, what they are in UV.x (part + 0.5: shoes 0, skin 1,
// legs 2, hair 3, top 4, eyes 5, accent 6, tights 7) and which limb they
// belong to in UV.y (limb + 0.5, flipped by the glTF export: body 0, left
// leg 1, right leg 2, left arm 3, right arm 4, head 5). Limbs are posed by
// rotating round the hip, knee, shoulder and elbow, so they stay whole.

int person_part(vec2 uv) {
	return int(floor(uv.x));
}

int person_limb(vec2 uv) {
	return int(round(0.5 - uv.y));
}

// Rotation about the X axis (pitch) round a pivot; a > 0 swings a hanging
// limb forward (towards -Z).
vec3 pitch_about(vec3 p, vec3 pivot, float a) {
	vec3 r = p - pivot;
	float c = cos(a);
	float s = sin(a);
	return pivot + vec3(r.x, r.y * c - r.z * s, r.y * s + r.z * c);
}

vec3 pitch_dir(vec3 n, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(n.x, n.y * c - n.z * s, n.y * s + n.z * c);
}

// ph: stride phase (rad, one step per pi), walk 0..1, carry 0..1 (forearms
// up holding a basket / case), look: head yaw (rad).
void person_pose(inout vec3 v, inout vec3 n, int limb, float ph, float walk, float carry, float look) {
	float sw = sin(ph) * walk;
	if (limb == 1 || limb == 2) {
		float side = limb == 1 ? -1.0 : 1.0;
		float a = -sw * side * 0.36;
		// The knee folds as the leg swings back and through.
		float k = (max(0.0, -a) * 1.6 + 0.08 * walk) * (1.0 - smoothstep(0.42, 0.54, v.y));
		v = pitch_about(v, vec3(0.0, 0.475, 0.0), -k);
		n = pitch_dir(n, -k);
		v = pitch_about(v, vec3(0.0, 0.93, 0.0), a);
		n = pitch_dir(n, a);
	} else if (limb == 3 || limb == 4) {
		float side = limb == 3 ? -1.0 : 1.0;
		float a = mix(sw * side * 0.4, 0.3, carry);
		float e = (0.18 * walk + 1.25 * carry) * (1.0 - smoothstep(1.07, 1.17, v.y));
		v = pitch_about(v, vec3(0.0, 1.125, 0.0), e);
		n = pitch_dir(n, e);
		v = pitch_about(v, vec3(0.0, 1.4, 0.0), a);
		n = pitch_dir(n, a);
	} else if (limb == 5 && abs(look) > 0.001) {
		float c = cos(look);
		float s = sin(look);
		v.xz = vec2(v.x * c - v.z * s, v.x * s + v.z * c);
		n.xz = vec2(n.x * c - n.z * s, n.x * s + n.z * c);
	}
	// Hips sway a little and the body bobs twice a stride.
	v.y += abs(cos(ph)) * 0.025 * walk;
	v.x += sin(ph) * 0.012 * walk * step(0.5, v.y);
}

// The crowd's bodies (tools/blender/build_crowd.py, made from the hero):
// limbs blend by their skin weights instead of a hard tag, so hips,
// shoulders, knees and elbows bend smoothly. cw: how much the vertex follows
// its limb; lw: how much it follows the lower segment (shin / forearm).
// Pivots scale by pivot_k (1.0 male, ~0.925 female) so every body bends at its
// true anatomical joints without clothing shear or limb stretching.
void person_pose_wk(inout vec3 v, inout vec3 n, int limb, float cw, float lw, float ph, float walk, float carry, float look, float alarm, float pivot_k, float seed) {
	float y_hip = 0.94 * pivot_k;
	float y_knee = 0.49 * pivot_k;
	float y_ankle = 0.070 * pivot_k;
	float y_sh = 1.48 * pivot_k;
	float y_el = 1.21 * pivot_k;
	float y_neck = 1.56 * pivot_k;
	float cycle = sin(ph);
	float sw = cycle * walk;
	float height = v.y;
	// Per-person walking style: subtle arm-swing vigour, stride energy, and posture personality.
	float style_arm = mix(0.80, 1.22, fract(seed * 11.3));
	float style_posture = (fract(seed * 17.9) - 0.5) * 0.052;
	float style_stride = mix(0.92, 1.08, fract(seed * 23.7));
	if (limb == 1 || limb == 2) {
		float side = limb == 1 ? -1.0 : 1.0;
		float swing = -cycle * side;
		float through = cos(ph) * -side;
		float a = sw * -side * (0.35 * style_stride + 0.24 * alarm);
		// Swing knee flexion + subtle loading-response cushion right after heel strike.
		float load_k = max(0.0, swing) * max(0.0, -through) * 0.16;
		float k = (max(through, 0.0) * (0.20 + (0.64 + 0.38 * alarm) * max(-swing, 0.0)) + load_k + 0.045) * walk;
		vec3 vk = pitch_about(v, vec3(0.0, y_knee, 0.02 * pivot_k), -k);
		v = mix(v, vk, lw);
		n = normalize(mix(n, pitch_dir(n, -k), lw));
		vec3 vh = pitch_about(v, vec3(0.0, y_hip, 0.0), a);
		v = mix(v, vh, cw);
		n = normalize(mix(n, pitch_dir(n, a), cw));
		float foot = lw * (1.0 - smoothstep(0.065 * pivot_k, 0.15 * pivot_k, height));
		// Natural heel-to-toe rocker: slight dorsiflexion before heel contact, toe-off push behind.
		float heel_strike = max(0.0, swing) * max(0.0, through) * 0.16 * walk;
		float toe_off = max(0.0, -swing) * max(0.0, -through) * 0.24 * walk;
		float rollover = clamp(k * 0.58 - a * 0.42 + heel_strike - toe_off, -0.22, 0.30);
		vec3 ankle = pitch_about(vec3(0.0, y_ankle, 0.0), vec3(0.0, y_knee, 0.02 * pivot_k), -k);
		ankle = pitch_about(ankle, vec3(0.0, y_hip, 0.0), a);
		v = mix(v, pitch_about(v, ankle, rollover), foot);
		n = normalize(mix(n, pitch_dir(n, rollover), foot));
	} else if (limb == 3 || limb == 4) {
		float side = limb == 3 ? -1.0 : 1.0;
		// Pendular forearm phase lag (~0.52 rad) for natural relaxed human arm swing.
		float arm_lag = sin(ph - 0.52) * walk;
		float a = mix((sw * side - cos(ph) * side * walk * 0.16) * (0.32 * style_arm + 0.22 * alarm), 0.30, carry);
		float e = 0.14 + 0.12 * walk + 1.18 * carry + 0.56 * alarm + max(0.0, arm_lag * side) * 0.28 * style_arm - max(0.0, -arm_lag * side) * 0.06;
		vec3 ve = pitch_about(v, vec3(0.0, y_el, 0.0), e);
		v = mix(v, ve, lw);
		n = normalize(mix(n, pitch_dir(n, e), lw));
		vec3 vs = pitch_about(v, vec3(0.0, y_sh, 0.0), a);
		v = mix(v, vs, cw);
		n = normalize(mix(n, pitch_dir(n, a), cw));
	} else if (limb == 5 && abs(look) > 0.001) {
		float c = cos(look * cw);
		float s = sin(look * cw);
		v.xz = vec2(v.x * c - v.z * s, v.x * s + v.z * c);
		n.xz = vec2(n.x * c - n.z * s, n.x * s + n.z * c);
		// Subtle natural head tilt into turns/glances.
		float tilt_z = -look * 0.08 * cw;
		vec3 hr = v - vec3(0.0, y_neck, 0.0);
		float cz = cos(tilt_z);
		float sz = sin(tilt_z);
		v = vec3(0.0, y_neck, 0.0) + vec3(hr.x * cz - hr.y * sz, hr.x * sz + hr.y * cz, hr.z);
		n = vec3(n.x * cz - n.y * sz, n.x * sz + n.y * cz, n.z);
	}
	float lean = (-alarm * (0.10 + 0.14 * walk) + style_posture) * smoothstep(y_hip * 0.97, y_sh * 0.91, height);
	v = pitch_about(v, vec3(0.0, y_hip, 0.0), lean);
	n = pitch_dir(n, lean);
	float torso = smoothstep(y_hip * 0.95, y_sh * 1.05, height);
	float yaw = sw * (0.078 * torso - 0.032) * (1.0 - 0.75 * carry);
	float c = cos(yaw);
	float s = sin(yaw);
	v.xz = mat2(vec2(c, s), vec2(-s, c)) * v.xz;
	n.xz = mat2(vec2(c, s), vec2(-s, c)) * n.xz;
	v.y += (1.0 - cos(ph * 2.0)) * 0.009 * pivot_k * walk * smoothstep(0.06 * pivot_k, 0.70 * pivot_k, height);
	// Natural stance-side lateral hip weight transfer, counter-balanced by upper torso.
	v.x += cycle * 0.015 * pivot_k * walk * smoothstep(0.15 * pivot_k, y_hip * 1.04, height)
		- cycle * 0.007 * pivot_k * walk * smoothstep(y_hip * 1.12, y_neck * 1.04, height);
}

void person_pose_w(inout vec3 v, inout vec3 n, int limb, float cw, float lw, float ph, float walk, float carry, float look, float alarm) {
	person_pose_wk(v, n, limb, cw, lw, ph, walk, carry, look, alarm, 1.0, 0.5);
}

// Subtle standing life for stopped/browsing/waiting people: chest breathing,
// gentle asynchronous weight shift across the feet, and soft head/arm motion.
void person_pose_idle_k(inout vec3 v, inout vec3 n, int limb, float cw, float lw, float walk, float carry, float t, float seed, float pivot_k) {
	float idle = clamp(1.0 - walk, 0.0, 1.0);
	if (idle <= 0.001) {
		return;
	}
	float y_hip = 0.94 * pivot_k;
	float y_knee = 0.49 * pivot_k;
	float y_sh = 1.48 * pivot_k;
	float y_el = 1.21 * pivot_k;
	float y_neck = 1.56 * pivot_k;
	float height = v.y;
	float b_ph = t * (1.45 + fract(seed * 5.71) * 0.45) + seed * 6.28318;
	float breath = sin(b_ph) * idle;
	float s_ph = t * (0.34 + fract(seed * 3.17) * 0.16) + seed * 19.3;
	float s_raw = clamp(sin(s_ph) * 1.45, -1.0, 1.0);
	float shift = s_raw * s_raw * (3.0 - 2.0 * abs(s_raw)) * sign(s_raw) * idle;

	// Soften the unloaded knee slightly so weight rests naturally on one leg.
	if (limb == 1 || limb == 2) {
		float side = limb == 1 ? -1.0 : 1.0;
		float unload = max(0.0, -side * shift);
		float k = unload * 0.065;
		if (k > 0.001) {
			vec3 vk = pitch_about(v, vec3(0.0, y_knee, 0.02 * pivot_k), -k);
			v = mix(v, vk, lw);
			n = normalize(mix(n, pitch_dir(n, -k), lw));
			vec3 vh = pitch_about(v, vec3(0.0, y_hip, 0.0), k * 0.45);
			v = mix(v, vh, cw);
			n = normalize(mix(n, pitch_dir(n, k * 0.45), cw));
		}
	} else if ((limb == 3 || limb == 4) && carry < 0.5) {
		float side = limb == 3 ? -1.0 : 1.0;
		float arm_sway = (sin(b_ph - 0.55) * 0.018 + shift * side * 0.028) * idle * (1.0 - carry);
		vec3 vs = pitch_about(v, vec3(0.0, y_sh, 0.0), arm_sway);
		v = mix(v, vs, cw);
		n = normalize(mix(n, pitch_dir(n, arm_sway), cw));
		float el_relax = sin(b_ph - 0.8) * 0.022 * idle * (1.0 - carry);
		vec3 ve = pitch_about(v, vec3(0.0, y_el, 0.0), el_relax);
		v = mix(v, ve, lw);
		n = normalize(mix(n, pitch_dir(n, el_relax), lw));
	} else if (limb == 5) {
		float nod = breath * 0.014;
		vec3 vh = pitch_about(v, vec3(0.0, y_neck, 0.0), nod);
		v = mix(v, vh, cw);
		n = normalize(mix(n, pitch_dir(n, nod), cw));
	}

	// Subtle ribcage breath expansion and lateral weight shift with upper-spine counter-balance.
	float torso = smoothstep(y_hip * 0.96, y_sh * 1.05, height);
	float chest = smoothstep(y_hip * 1.04, y_sh * 0.99, height) * (1.0 - smoothstep(y_sh * 1.03, y_neck * 1.10, height));
	v.y += breath * 0.006 * pivot_k * torso;
	v.z -= breath * 0.0045 * pivot_k * chest * (1.0 - smoothstep(-0.02, 0.14, v.z));
	v.x += shift * 0.022 * pivot_k * smoothstep(0.18 * pivot_k, y_hip * 1.02, height)
		- shift * 0.008 * pivot_k * smoothstep(y_hip * 1.13, y_neck * 1.06, height);

	float i_yaw = shift * 0.042 * torso * (1.0 - 0.7 * carry);
	float ic = cos(i_yaw);
	float is_ = sin(i_yaw);
	v.xz = mat2(vec2(ic, is_), vec2(-is_, ic)) * v.xz;
	n.xz = mat2(vec2(ic, is_), vec2(-is_, ic)) * n.xz;
}

void person_pose_idle(inout vec3 v, inout vec3 n, int limb, float cw, float lw, float walk, float carry, float t, float seed) {
	person_pose_idle_k(v, n, limb, cw, lw, walk, carry, t, seed, 1.0);
}

// Living-world activity poses layered onto the crowd's procedural rig:
//   mode 0 = normal walk/idle
//   mode 1 = jog (forward lean, higher knee lift, bent pumping arms)
//   mode 2 = sit (90 deg hip/knee fold, pelvis lowered onto bench seat)
//   mode 3 = phone (right forearm raised to chest/eye level, slight head tilt down)
//   mode 4 = chat (gentle alternating hand gestures while standing/talking)
// pivot_k scales joint Y pivots for female (~0.925) vs male (1.0) bodies.
void person_pose_activity(inout vec3 v, inout vec3 n, int limb, float cw, float lw, float ph, float walk, float look, int mode, float pivot_k, float t, float seed) {
	float y_hip = 0.94 * pivot_k;
	float y_knee = 0.49 * pivot_k;
	float y_sh = 1.48 * pivot_k;
	float y_el = 1.21 * pivot_k;
	float y_neck = 1.56 * pivot_k;
	if (mode == 1) {
		// Jogging: extra knee drive, 90-deg bent elbows, forward lean.
		float sw = sin(ph) * walk;
		if (limb == 1 || limb == 2) {
			float side = limb == 1 ? -1.0 : 1.0;
			float extra_k = max(0.0, cos(ph) * -side) * 0.42 * walk;
			vec3 vk = pitch_about(v, vec3(0.0, y_knee, 0.02), -extra_k);
			v = mix(v, vk, lw);
			n = normalize(mix(n, pitch_dir(n, -extra_k), lw));
		} else if (limb == 3 || limb == 4) {
			float side = limb == 3 ? -1.0 : 1.0;
			float bend = 0.92 * walk;
			vec3 ve = pitch_about(v, vec3(0.0, y_el, 0.0), bend);
			v = mix(v, ve, lw);
			n = normalize(mix(n, pitch_dir(n, bend), lw));
			float pump = sw * side * 0.24;
			vec3 vs = pitch_about(v, vec3(0.0, y_sh, 0.0), pump);
			v = mix(v, vs, cw);
			n = normalize(mix(n, pitch_dir(n, pump), cw));
		}
		float lean = -0.13 * walk * smoothstep(y_hip * 0.95, y_sh, v.y);
		v = pitch_about(v, vec3(0.0, y_hip, 0.0), lean);
		n = pitch_dir(n, lean);
	} else if (mode == 2) {
		// Seated on a bench: hips forward, knees bent down, relaxed hands on lap.
		if (limb == 1 || limb == 2) {
			float k_fold = 1.42;
			vec3 vk = pitch_about(v, vec3(0.0, y_knee, 0.02), -k_fold);
			v = mix(v, vk, lw);
			n = normalize(mix(n, pitch_dir(n, -k_fold), lw));
			float h_fold = 1.46;
			vec3 vh = pitch_about(v, vec3(0.0, y_hip, 0.0), h_fold);
			v = mix(v, vh, cw);
			n = normalize(mix(n, pitch_dir(n, h_fold), cw));
		} else if (limb == 3 || limb == 4) {
			float el = 0.85;
			vec3 ve = pitch_about(v, vec3(0.0, y_el, 0.0), el);
			v = mix(v, ve, lw);
			n = normalize(mix(n, pitch_dir(n, el), lw));
			float sh = 0.22;
			vec3 vs = pitch_about(v, vec3(0.0, y_sh, 0.0), sh);
			v = mix(v, vs, cw);
			n = normalize(mix(n, pitch_dir(n, sh), cw));
		} else if (limb == 5 && abs(look) > 0.001) {
			float c = cos(look * cw);
			float s = sin(look * cw);
			v.xz = vec2(v.x * c - v.z * s, v.x * s + v.z * c);
			n.xz = vec2(n.x * c - n.z * s, n.x * s + n.z * c);
		}
		// Lower pelvis onto standard 0.45 m bench height.
		v.y -= 0.41 * pivot_k;
	} else if (mode == 3) {
		// Checking / texting on phone: right arm raised, slight head tilt down.
		if (limb == 4) {
			float el = 1.38;
			vec3 ve = pitch_about(v, vec3(0.0, y_el, 0.0), el);
			v = mix(v, ve, lw);
			n = normalize(mix(n, pitch_dir(n, el), lw));
			float sh = 0.42;
			vec3 vs = pitch_about(v, vec3(0.0, y_sh, 0.0), sh);
			v = mix(v, vs, cw);
			n = normalize(mix(n, pitch_dir(n, sh), cw));
		} else if (limb == 5) {
			float tilt = -0.24;
			vec3 vh = pitch_about(v, vec3(0.0, y_neck, 0.0), tilt);
			v = mix(v, vh, cw);
			n = normalize(mix(n, pitch_dir(n, tilt), cw));
		}
	} else if (mode == 4) {
		// Socialising / chatting: gentle asynchronous hand gestures + subtle nod.
		float talk_ph = t * (2.1 + fract(seed * 7.3) * 0.7) + seed * 19.0;
		float talk_on = smoothstep(0.1, 0.7, sin(t * 0.45 + seed * 13.0));
		if (limb == 3 || limb == 4) {
			float side = limb == 3 ? -1.0 : 1.0;
			float gest = (0.45 + 0.25 * sin(talk_ph * side)) * talk_on;
			vec3 ve = pitch_about(v, vec3(0.0, y_el, 0.0), gest);
			v = mix(v, ve, lw);
			n = normalize(mix(n, pitch_dir(n, gest), lw));
			float sh = (0.14 + 0.12 * cos(talk_ph)) * talk_on;
			vec3 vs = pitch_about(v, vec3(0.0, y_sh, 0.0), sh);
			v = mix(v, vs, cw);
			n = normalize(mix(n, pitch_dir(n, sh), cw));
		} else if (limb == 5) {
			float nod = sin(talk_ph * 0.6) * 0.06 * talk_on;
			vec3 vh = pitch_about(v, vec3(0.0, y_neck, 0.0), nod);
			v = mix(v, vh, cw);
			n = normalize(mix(n, pitch_dir(n, nod), cw));
		}
	}
}

float person_surface_roughness(int part) {
	if (part == 1 || part == 9) return .62;
	if (part == 3) return .70;
	if (part == 5 || part == 8) return .42;
	if (part == 0) return .72;
	return .90;
}

vec3 person_cloth(vec3 color, vec3 local, float closeup, int part) {
	if (part == 2 || part == 4 || part == 6 || part == 7) {
		// Garment-space grain and gentle fold shading, held to the fabric.
		vec2 weave = local.xy + local.zy * vec2(.63, .13);
		float grain = sin(weave.x * 460.0) * sin(weave.y * 535.0);
		float filtered = 1.0 - smoothstep(.003, .011, length(fwidth(weave)));
		float folds = sin(local.x * 38.0 + local.y * 41.0 + local.z * 28.0);
		vec3 neutral = vec3(dot(color, vec3(.2126, .7152, .0722)));
		return mix(color, neutral, .08) * (1.0 + closeup * (.052 * folds + .06 * grain * filtered));
	}
	return color;
}
