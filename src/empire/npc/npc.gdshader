// Shop people (customers, staff) on the same hero-derived bodies as the
// street crowd (assets/models/crowd.glb, crowd.gdshader), so nobody changes
// look when they walk in off the pavement. Driven per instance instead of
// a MultiMesh: `stride` is the distance walked (m), `walk` 0..1 blends the
// swing in, `carry` raises the forearms (basket / box), `look` turns the
// head (rad). `seed` picks skin, hair, trousers, shoes and accents from the
// crowd's palettes; `shirt` is the top. Staff get an apron over the top.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://src/world/shaders/person_pose.gdshaderinc"

instance uniform float stride = 0.0;
instance uniform float walk = 0.0;
instance uniform float carry = 0.0;
instance uniform float look = 0.0;
instance uniform float seed = 0.0;
instance uniform vec3 shirt = vec3(0.4, 0.5, 0.7);
instance uniform float apron = 0.0;

varying vec3 v_col;
varying float v_rough;
varying float v_front;
varying flat int v_part;

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 pal5(float s, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
	return s < 0.2 ? a : (s < 0.4 ? b : (s < 0.6 ? c : (s < 0.8 ? d : e)));
}

void vertex() {
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
		v_col = shirt;
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
	v_rough = part == 8 || part == 5 ? 0.3 : (part == 0 ? 0.45 : (part == 3 ? 0.55 : 0.78));
	v_front = VERTEX.z;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	person_pose_w(v, n, person_limb(UV), UV2.x, 1.0 - UV2.y, stride / 0.72 * 3.14159, walk, carry, look);
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec3 c = v_col;
	if (v_part == 4 && apron > 0.5 && v_front < -0.06) {
		c = vec3(0.12, 0.42, 0.33);  // staff apron (the studio's green)
	}
	ALBEDO = c;
	ROUGHNESS = v_rough;
}
