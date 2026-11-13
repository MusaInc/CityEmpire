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
		float k = (max(0.0, -a) * 1.6 + 0.08 * walk) * smoothstep(0.54, 0.42, v.y);
		v = pitch_about(v, vec3(0.0, 0.475, 0.0), -k);
		n = pitch_dir(n, -k);
		v = pitch_about(v, vec3(0.0, 0.93, 0.0), a);
		n = pitch_dir(n, a);
	} else if (limb == 3 || limb == 4) {
		float side = limb == 3 ? -1.0 : 1.0;
		float a = mix(sw * side * 0.4, 0.3, carry);
		float e = (0.18 * walk + 1.25 * carry) * smoothstep(1.17, 1.07, v.y);
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
