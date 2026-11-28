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
instance uniform vec3 apron_col = vec3(0.12, 0.42, 0.33);   // (uniform by business level: ShopPerson.set_uniform)
uniform float pivot_k = 1.0;

varying vec3 v_col;
varying float v_rough;
varying vec3 v_surface;
varying float v_front;
varying flat int v_part;
varying float v_near;   // 0 at the lens .. 1 from 1.8 m: dithered out up close

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

void vertex() {
	int part = person_part(UV);
	v_part = part;
	vec3 skin = srgb(pal8(fract(seed * 1.0),
		vec3(0.96, 0.81, 0.70), vec3(0.92, 0.74, 0.60), vec3(0.85, 0.65, 0.50), vec3(0.76, 0.55, 0.40),
		vec3(0.65, 0.45, 0.32), vec3(0.52, 0.35, 0.24), vec3(0.39, 0.26, 0.18), vec3(0.28, 0.19, 0.14)));
	if (part == 1) {
		v_col = skin;
	} else if (part == 9) {
		v_col = skin * vec3(0.78, 0.52, 0.50);
	} else if (part == 2) {
		v_col = srgb(pal8(fract(seed * 7.13),
			vec3(0.15, 0.17, 0.25), vec3(0.10, 0.10, 0.12), vec3(0.26, 0.34, 0.48), vec3(0.58, 0.52, 0.40),
			vec3(0.30, 0.30, 0.31), vec3(0.22, 0.26, 0.22), vec3(0.42, 0.34, 0.26), vec3(0.19, 0.21, 0.28)));
	} else if (part == 3) {
		v_col = srgb(pal8(fract(seed * 13.7),
			vec3(0.05, 0.04, 0.04), vec3(0.14, 0.09, 0.06), vec3(0.28, 0.17, 0.10), vec3(0.44, 0.24, 0.13),
			vec3(0.64, 0.48, 0.28), vec3(0.78, 0.65, 0.40), vec3(0.45, 0.44, 0.43), vec3(0.72, 0.71, 0.70)));
	} else if (part == 4) {
		v_col = srgb(shirt);
	} else if (part == 6) {
		v_col = srgb(pal8(fract(seed * 5.31),
			vec3(0.92, 0.91, 0.89), vec3(0.12, 0.12, 0.14), vec3(0.62, 0.16, 0.19), vec3(0.84, 0.70, 0.36),
			vec3(0.20, 0.32, 0.54), vec3(0.32, 0.42, 0.30), vec3(0.50, 0.36, 0.24), vec3(0.74, 0.72, 0.68)));
	} else if (part == 0) {
		v_col = srgb(pal8(fract(seed * 3.9),
			vec3(0.92, 0.92, 0.90), vec3(0.09, 0.09, 0.10), vec3(0.86, 0.84, 0.80), vec3(0.34, 0.21, 0.13),
			vec3(0.18, 0.21, 0.28), vec3(0.46, 0.30, 0.18), vec3(0.24, 0.24, 0.25), vec3(0.62, 0.18, 0.18)));
	} else if (part == 8) {
		v_col = vec3(0.88);
	} else {
		v_col = srgb(vec3(0.06, 0.05, 0.05));
	}
	v_rough = person_surface_roughness(part);
	v_surface = VERTEX;
	v_front = VERTEX.z;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	int limb = person_limb(UV);
	// Match stride length to this instance's vertical leg length (zero foot slip across height scales).
	float y_scale = max(length(MODEL_MATRIX[1].xyz), 0.5) * pivot_k;
	float ph = stride / (0.80 * y_scale) * 3.14159;
	person_pose_wk(v, n, limb, UV2.x, 1.0 - UV2.y, ph, walk, carry, look, 0.0, pivot_k, seed);
	person_pose_idle_k(v, n, limb, UV2.x, 1.0 - UV2.y, walk, carry, TIME, seed, pivot_k);
	VERTEX = v;
	NORMAL = n;
	// Someone right in front of the lens dissolves instead of filling the
	// screen (as crowd.gdshader does outside: in a narrow aisle or doorway
	// a customer between you and the camera hid half the shop).
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
	vec3 c = v_col;
	if (v_part == 4 && apron > 0.5 && v_front < -0.06) {
		c = srgb(apron_col);  // staff apron (the studio's green, or your brand's)
	}
	ALBEDO = person_cloth(c, v_surface, 1.0 - smoothstep(7.0, 23.0, length(VERTEX)), v_part);
	SPECULAR = v_part == 1 || v_part == 3 ? 0.32 : 0.24;
	ROUGHNESS = v_rough;
}
