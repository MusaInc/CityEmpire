// Shop people (customers, staff) on the city's low-poly pedestrian model
// (tools/blender/build_street.py), animated in the vertex shader like the
// street walkers (pedestrian.gdshader) but driven per instance instead of
// sliding along a pavement: `stride` is the distance walked (m, the leg
// cycle follows it), `walk` 0..1 blends the swing in, `carry` raises the
// forearms (basket / box), `look` turns the head (rad). Colours per person.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform int part = 0;  // 0 other (shoes), 1 skin, 2 trousers, 3 hair, 4 shirt
uniform float roughness = 0.8;

instance uniform float stride = 0.0;
instance uniform float walk = 0.0;
instance uniform float carry = 0.0;
instance uniform float look = 0.0;
instance uniform vec3 shirt : source_color = vec3(0.4, 0.5, 0.7);
instance uniform vec3 skin : source_color = vec3(0.8, 0.62, 0.5);
instance uniform vec3 trousers : source_color = vec3(0.15, 0.16, 0.22);
instance uniform vec3 hair : source_color = vec3(0.1, 0.07, 0.05);
instance uniform float apron = 0.0;  // staff: a coloured apron over the shirt

varying vec3 v_col;
varying float v_front;

void vertex() {
	v_col = part == 1 ? skin : (part == 2 ? trousers : (part == 3 ? hair : (part == 4 ? shirt : vec3(0.08))));
	v_front = VERTEX.z;
	float ph = stride / 0.7 * 3.14159;  // one step per 0.7 m
	float sw = sin(ph) * walk;
	float side = sign(VERTEX.x);
	if (abs(VERTEX.x) < 0.2 && VERTEX.y < 0.86) {
		float kk = (0.86 - VERTEX.y);
		VERTEX.z += sw * side * kk * 0.5;
		VERTEX.y += max(0.0, sw * side) * kk * 0.12;
		VERTEX.z += max(0.0, -sw * side) * max(0.0, 0.45 - VERTEX.y) * 0.5 * walk;
	} else if (abs(VERTEX.x) > 0.2 && VERTEX.y < 1.45) {
		// Arms: swing while walking, or held forward (carrying).
		float arm = (1.45 - VERTEX.y);
		VERTEX.z -= sw * side * arm * 0.42 * (1.0 - carry);
		if (VERTEX.y < 1.16) {
			float fk = (1.16 - VERTEX.y);
			VERTEX.z -= fk * 1.6 * carry;
			VERTEX.y += fk * 0.9 * carry;
		}
	}
	VERTEX.y += abs(cos(ph)) * 0.025 * walk;
	if (VERTEX.y > 1.5) {
		float c = cos(look);
		float s = sin(look);
		VERTEX.xz = vec2(VERTEX.x * c - VERTEX.z * s, VERTEX.x * s + VERTEX.z * c);
	}
}

void fragment() {
	vec3 c = v_col;
	if (part == 4 && apron > 0.5 && v_front < -0.08) {
		c = vec3(0.12, 0.42, 0.33);  // staff apron (the studio's green)
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
}
