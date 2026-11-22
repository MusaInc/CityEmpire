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
// Pivots are the hero rig's (metres up): hip 0.94, knee 0.49, shoulder 1.5,
// elbow 1.21.
void person_pose_w(inout vec3 v, inout vec3 n, int limb, float cw, float lw, float ph, float walk, float carry, float look) {
	float cycle = sin(ph);
	float sw = cycle * walk;
	float height = v.y;
	if (limb == 1 || limb == 2) {
		float side = limb == 1 ? -1.0 : 1.0;
		float swing = -cycle * side;
		float through = cos(ph) * -side;
		float a = sw * -side * 0.33;
		// The knee flexes during swing, then extends before heel contact.
		float k = (max(through, 0.0) * (0.17 + 0.61 * max(-swing, 0.0)) + 0.045) * walk;
		vec3 vk = pitch_about(v, vec3(0.0, 0.49, 0.02), -k);
		v = mix(v, vk, lw);
		n = normalize(mix(n, pitch_dir(n, -k), lw));
		vec3 vh = pitch_about(v, vec3(0.0, 0.94, 0.0), a);
		v = mix(v, vh, cw);
		n = normalize(mix(n, pitch_dir(n, a), cw));
		float foot = lw * (1.0 - smoothstep(0.065, 0.15, height));
		// Release the toe in swing and level the foot before the next step.
		float rollover = clamp(k * 0.62 - a * 0.45, -0.17, 0.27);
		vec3 ankle = pitch_about(vec3(0.0, 0.070, 0.0), vec3(0.0, 0.49, 0.02), -k);
		ankle = pitch_about(ankle, vec3(0.0, 0.94, 0.0), a);
		v = mix(v, pitch_about(v, ankle, rollover), foot);
		n = normalize(mix(n, pitch_dir(n, rollover), foot));
	} else if (limb == 3 || limb == 4) {
		float side = limb == 3 ? -1.0 : 1.0;
		float a = mix((sw * side - cos(ph) * side * walk * 0.16) * 0.32, 0.30, carry);
		float e = 0.13 + 0.12 * walk + 1.18 * carry + max(0.0, sw * side) * 0.24;
		vec3 ve = pitch_about(v, vec3(0.0, 1.21, 0.0), e);
		v = mix(v, ve, lw);
		n = normalize(mix(n, pitch_dir(n, e), lw));
		vec3 vs = pitch_about(v, vec3(0.0, 1.48, 0.0), a);
		v = mix(v, vs, cw);
		n = normalize(mix(n, pitch_dir(n, a), cw));
	} else if (limb == 5 && abs(look) > 0.001) {
		float c = cos(look * cw);
		float s = sin(look * cw);
		v.xz = vec2(v.x * c - v.z * s, v.x * s + v.z * c);
		n.xz = vec2(n.x * c - n.z * s, n.x * s + n.z * c);
	}
	float torso = smoothstep(0.89, 1.55, height);
	float yaw = sw * (0.07 * torso - 0.025) * (1.0 - 0.75 * carry);
	float c = cos(yaw);
	float s = sin(yaw);
	v.xz = mat2(vec2(c, s), vec2(-s, c)) * v.xz;
	n.xz = mat2(vec2(c, s), vec2(-s, c)) * n.xz;
	v.y += (1.0 - cos(ph * 2.0)) * 0.007 * walk * smoothstep(0.06, 0.7, height);
	v.x += cycle * 0.010 * walk * smoothstep(0.15, 1.0, height);
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
