// Shop people (customers, staff) on the city's pedestrian bodies
// (tools/blender/build_street.py), posed like the street walkers
// (person_pose.gdshaderinc) but driven per instance instead of sliding along
// a pavement: `stride` is the distance walked (m, the leg cycle follows it),
// `walk` 0..1 blends the swing in, `carry` raises the forearms (basket /
// box), `look` turns the head (rad). Colours per person.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://src/world/shaders/person_pose.gdshaderinc"

instance uniform float stride = 0.0;
instance uniform float walk = 0.0;
instance uniform float carry = 0.0;
instance uniform float look = 0.0;
instance uniform vec3 shirt : source_color = vec3(0.4, 0.5, 0.7);
instance uniform vec3 skin : source_color = vec3(0.8, 0.62, 0.5);
instance uniform vec3 trousers : source_color = vec3(0.15, 0.16, 0.22);
instance uniform vec3 hair : source_color = vec3(0.1, 0.07, 0.05);
instance uniform vec3 accent : source_color = vec3(0.45, 0.28, 0.16);
instance uniform float apron = 0.0;  // staff: a coloured apron over the top

varying vec3 v_col;
varying float v_front;
varying flat int v_part;

void vertex() {
	int part = person_part(UV);
	v_part = part;
	v_col = part == 1 ? skin : (part == 2 ? trousers : (part == 3 ? hair : (part == 4 ? shirt
		: (part == 6 ? accent : (part == 0 ? vec3(0.08) : vec3(0.05))))));
	v_front = VERTEX.z;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	person_pose(v, n, person_limb(UV), stride / 0.7 * 3.14159, walk, carry, look);
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec3 c = v_col;
	if (v_part == 4 && apron > 0.5 && v_front < -0.06) {
		c = vec3(0.12, 0.42, 0.33);  // staff apron (the studio's green)
	}
	ALBEDO = c;
	ROUGHNESS = v_part == 5 ? 0.3 : 0.8;
}
