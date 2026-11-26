// ShopfrontKit modules (decorative shopfronts). One shader for every part;
// UV2.x is the surface (0 frame, 1 window glass, 2 sign board, 3 door glass,
// 4 threshold tiles), UV2.y the frame material (0 paint, 0.1 soffit,
// 0.25 dark metal, 0.3 brass, 0.5 stone, 0.6 leaves, 0.75 timber).
// Instance: COLOR = the shop's paint; INSTANCE_CUSTOM = (brand/255,
// trade/255, seed, open). Windows trace a shallow interior behind the glass
// (one box, two plane tests): shelving on the back wall, a display table or
// rail or counter by trade, floor, ceiling lights – lit at night while open.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

global uniform float night;
global uniform float wetness;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

varying vec3 v_local;
varying vec3 v_cam;
varying vec3 v_world;
varying flat vec4 v_inst;
varying flat vec3 v_paint;

// Interior palettes by trade (TRADES order in shopfront_kit.gd):
// shelving / walls, goods, layout (0 wall shelves + table, 1 clothes rails,
// 2 café tables + counter, 3 desks/office, 4 vitrines), light warmth.
const vec3 SHELF[24] = vec3[24](
	vec3(0.45,0.30,0.18), vec3(0.32,0.22,0.15), vec3(0.85,0.87,0.86), vec3(0.12,0.12,0.14), vec3(0.8,0.8,0.82), vec3(0.35,0.22,0.14),
	vec3(0.55,0.6,0.5), vec3(0.4,0.38,0.35), vec3(0.15,0.14,0.14), vec3(0.08,0.1,0.16), vec3(0.42,0.3,0.2), vec3(0.6,0.58,0.55),
	vec3(0.8,0.85,0.88), vec3(0.88,0.88,0.86), vec3(0.75,0.76,0.78), vec3(0.78,0.74,0.68), vec3(0.3,0.28,0.27), vec3(0.4,0.16,0.1),
	vec3(0.5,0.42,0.3), vec3(0.2,0.2,0.22), vec3(0.9,0.75,0.8), vec3(0.8,0.85,0.9), vec3(0.92,0.92,0.92), vec3(0.6,0.7,0.75));
const vec3 GOODS[24] = vec3[24](
	vec3(0.78,0.55,0.28), vec3(0.6,0.4,0.25), vec3(0.3,0.6,0.45), vec3(0.2,0.6,0.9), vec3(0.3,0.3,0.35), vec3(0.6,0.25,0.2),
	vec3(0.8,0.3,0.45), vec3(0.7,0.45,0.2), vec3(0.5,0.45,0.4), vec3(0.85,0.7,0.35), vec3(0.75,0.5,0.25), vec3(0.8,0.2,0.2),
	vec3(0.95,0.95,0.95), vec3(0.3,0.4,0.6), vec3(0.2,0.35,0.55), vec3(0.85,0.8,0.6), vec3(0.5,0.3,0.4), vec3(0.85,0.55,0.25),
	vec3(0.45,0.7,0.3), vec3(0.3,0.5,0.8), vec3(0.95,0.5,0.7), vec3(0.2,0.55,0.75), vec3(0.4,0.3,0.3), vec3(0.7,0.75,0.8));
const int LAYOUT[24] = int[24](0,2,0,4,4,0,0,0,3,4,0,0,3,3,3,0,1,2,0,1,0,3,3,0);

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_inst = INSTANCE_CUSTOM;
	v_paint = COLOR.rgb;
}

// What you see through a window at p looking along d (module space: x along
// the bay 0..6, y up from the pavement, z out; the room runs back into the
// building to z = -3). Returns colour; `lamp` gets how much is ceiling light.
vec3 shop_interior(vec3 p, vec3 d, int trade, float seed, float lit, out float lamp) {
	vec3 bmin = vec3(0.0, 0.0, -3.0);
	vec3 bmax = vec3(6.0, 3.3, 0.0);
	vec3 q = vec3(p.x, p.y, -0.001);
	vec3 dd = vec3(abs(d.x) < 1e-4 ? 1e-4 : d.x, abs(d.y) < 1e-4 ? 1e-4 : d.y, min(d.z, -1e-3));
	vec3 t1 = (bmin - q) / dd;
	vec3 t2 = (bmax - q) / dd;
	vec3 tf = max(t1, t2);
	float tx = min(min(tf.x, tf.y), tf.z);
	vec3 h = q + dd * tx;
	vec3 shelf = SHELF[trade];
	vec3 goods = GOODS[trade];
	int lay = LAYOUT[trade];
	vec3 col;
	lamp = 0.0;
	if (tx == tf.z) {
		// back wall: shelving bays with stock (or a plain wall + pictures)
		float band = fract(h.y / 0.46);
		float bay = floor(h.x / 0.9);
		bool shelfline = band < 0.08 && h.y > 0.35 && h.y < 2.3;
		float cell = h21(vec2(floor(h.x / 0.16), floor(h.y / 0.46)) + seed * 31.0);
		bool stock = h.y > 0.4 && h.y < 2.3 && band > 0.1 && band < 0.1 + 0.75 * cell && lay != 3;
		col = shelf * (0.85 + 0.15 * h21(vec2(bay, 2.0)));
		if (stock) col = mix(goods, goods.zxy, step(0.66, cell)) * (0.6 + 0.5 * cell);
		if (shelfline) col = shelf * 0.6;
		if (lay == 3 && h.y > 1.3 && h.y < 2.0 && fract(h.x / 1.4) < 0.6) col = mix(goods, vec3(0.9), 0.4);   // posters / listings
	} else if (tx == tf.y) {
		if (dd.y < 0.0) {
			// floor: tiles / boards
			vec2 g = fract(h.xz / (lay == 2 ? 0.25 : 0.6));
			col = mix(shelf * 0.5, vec3(0.55, 0.52, 0.48), 0.5) * (0.85 + 0.15 * step(0.04, min(g.x, g.y)));
		} else {
			// ceiling: light strips / spots
			float strip = step(abs(fract(h.z / 1.1) - 0.5), 0.07) * step(0.6, h.x) * step(h.x, 5.4);
			col = vec3(0.86, 0.85, 0.82) * 0.7;
			lamp = strip;
			col = mix(col, vec3(1.0, 0.95, 0.85), strip);
		}
	} else {
		col = shelf * 0.9;   // side walls
	}
	// The display in the room (a plane across it): table / rails / counter / vitrine.
	float zp = lay == 2 ? -1.9 : (lay == 3 ? -1.7 : -1.2);
	float ts = (zp - q.z) / dd.z;
	if (ts > 0.0 && ts < tx) {
		vec3 s = q + dd * ts;
		float cx = fract(s.x / 2.0);
		bool hit = false;
		vec3 dc = goods;
		if (lay == 0) { hit = s.y < 0.85 && cx > 0.2 && cx < 0.8; dc = s.y > 0.78 ? goods : shelf * 0.7; }
		else if (lay == 1) { hit = (s.y > 0.5 && s.y < 1.55 && cx > 0.15 && cx < 0.85 && fract(s.x / 0.12) < 0.7) || abs(s.y - 1.58) < 0.03; dc = mix(goods, goods.yzx, step(0.5, fract(s.x / 0.5))) * 0.8; }
		else if (lay == 2) { hit = (s.y < 1.05 && s.x > 3.6) || (s.y < 0.75 && abs(cx - 0.5) < 0.18); dc = s.y > 0.98 ? vec3(0.8) : shelf; }
		else if (lay == 3) { hit = s.y < 0.76 && cx > 0.1 && cx < 0.9; dc = s.y > 0.72 ? vec3(0.85) : shelf * 0.8; }
		else { hit = s.y < 1.05 && cx > 0.12 && cx < 0.88; dc = s.y > 0.85 ? mix(goods, vec3(1.0), 0.3) : shelf; }
		if (hit) { col = dc; lamp = 0.0; }
	}
	return col;
}

void fragment() {
	int surf = int(round(UV2.x));
	float mat = UV2.y;
	vec3 nrm = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = nrm;
	float seed = v_inst.z;
	float open = v_inst.w;
	int brand = int(round(v_inst.x * 255.0));
	int trade = clamp(int(round(v_inst.y * 255.0)), 0, 23);
	float lit = open * smoothstep(0.15, 0.6, night);
	// Age: grime from the pavement up, streaks under ledges, by the seed.
	float age = 0.35 + 0.5 * fract(seed * 7.3);
	float grime = vn(v_world.xz * 0.7 + v_world.y * 1.3) * 0.5 + vn(v_world.xz * 3.1 + v_world.y * 5.0) * 0.5;
	float splash = (1.0 - smoothstep(0.0, 0.7, v_local.y)) * age;
	if (surf == 0) {
		vec3 c = v_paint;
		float rough = 0.55;
		float metal = 0.0;
		if (mat > 0.05 && mat < 0.15) { c = v_paint * 0.7; }
		else if (mat > 0.2 && mat < 0.27) { c = vec3(0.09, 0.095, 0.1); rough = 0.42; metal = 0.6; }
		else if (mat > 0.27 && mat < 0.35) { c = vec3(0.62, 0.46, 0.22); rough = 0.32; metal = 0.85; }
		else if (mat > 0.45 && mat < 0.55) { c = vec3(0.47, 0.45, 0.42) * (0.88 + 0.2 * vn(v_world.xz * 2.0 + v_world.y)); rough = 0.85; }
		else if (mat > 0.55 && mat < 0.65) { c = vec3(0.12, 0.24, 0.09) * (0.75 + 0.5 * vn(v_world.xz * 9.0 + v_world.y * 9.0)); rough = 0.9; }
		else if (mat > 0.7) { c = vec3(0.3, 0.2, 0.13) * (0.85 + 0.25 * vn(vec2(v_world.y * 30.0, v_world.x + v_world.z))); rough = 0.8; }
		else {
			// gloss paint, chipped and dulled with age
			float chip = step(0.86 - 0.12 * age, vn(v_world.xz * 11.0 + v_world.y * 13.0));
			c = mix(c, c * 0.55 + vec3(0.05), chip * 0.7);
			rough = mix(0.32, 0.6, age);
		}
		c *= 1.0 - (0.22 * splash + 0.12 * age * smoothstep(0.55, 0.9, grime));
		c *= 1.0 - 0.12 * wetness;
		ALBEDO = c;
		ROUGHNESS = mix(rough, rough * 0.55, wetness);
		METALLIC = metal;
		// shopfront lit from within at night: a warm spill on its own frame
		EMISSION = c * vec3(1.0, 0.82, 0.6) * 0.18 * lit * smoothstep(0.4, 1.4, v_local.y) * (1.0 - smoothstep(3.0, 3.6, v_local.y));
	} else if (surf == 2) {
		// The fascia sign: its atlas cell (2 columns x 16 rows).
		vec2 cell = vec2(float(brand % 2), float(brand / 2));
		vec2 uv = (cell + clamp(UV, vec2(0.002), vec2(0.998))) / vec2(2.0, 16.0);
		vec4 a = texture(atlas, uv);
		vec3 c = a.rgb * (1.0 - 0.18 * age * smoothstep(0.5, 0.9, grime));
		ALBEDO = c;
		ROUGHNESS = 0.5;
		// lettering glows at night (lit letters / trough light over the board)
		EMISSION = (a.rgb * a.a * 1.25 + c * 0.22) * lit;
	} else if (surf == 4) {
		// threshold mosaic: little tiles with a border
		vec2 g = fract(v_local.xz / 0.05);
		float h = h21(floor(v_local.xz / 0.05) + seed);
		ALBEDO = mix(vec3(0.82, 0.8, 0.74), vec3(0.18, 0.3, 0.42), step(0.82, h)) * (0.88 + 0.12 * step(0.1, min(g.x, g.y))) * (1.0 - 0.25 * age);
		ROUGHNESS = 0.5;
	} else {
		// Glass: reflections over the shop inside.
		vec3 dl = normalize(v_local - v_cam);
		float lamp;
		vec3 inside = shop_interior(v_local, dl, trade, seed, lit, lamp);
		if (surf == 3) inside *= 0.9;
		float day = clamp(dot(sky_horizon, vec3(0.3, 0.55, 0.15)) * 1.3, 0.05, 1.2);
		float roomlight = mix(day * 0.75, 0.0, smoothstep(0.2, 0.7, night)) + lit * (0.95 + 0.6 * lamp) + (1.0 - open) * night * 0.04;
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
		vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 rw = reflect(-vw, nw);
		vec3 env = city_reflection(rw, v_world, sky_top, sky_horizon, sun_dir, night);
		float fres = pow(1.0 - clamp(dot(nrm, VIEW), 0.0, 1.0), 4.0);
		float k = mix(0.06, 0.55, fres);
		// a little grime at the glass's foot and edges
		float dirt = (1.0 - smoothstep(0.64, 1.0, v_local.y)) * 0.35 * age;
		ALBEDO = vec3(0.02);
		ROUGHNESS = mix(0.08, 0.035, refl_probe);
		METALLIC = 0.1;
		SPECULAR = 0.5;
		EMISSION = inside * roomlight * (1.0 - k) * (1.0 - dirt) * mix(vec3(1.0), vec3(1.0, 0.86, 0.66), lit) + env * k * (1.0 - 0.5 * night) * fake_keep();
	}
}
