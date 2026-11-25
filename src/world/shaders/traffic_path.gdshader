// Moving traffic (Traffic): cars follow lane polylines stored in lane_tex
// (texel = x, y, z every Traffic.STEP m; the texel before a lane's first is
// its header: point count, loop flag). Traffic stores motion in an
// invertible upper-triangular MODEL_MATRIX with exact power-of-two scales.
// All geometry is positioned in lane space and then written in view space.
shader_type spatial;
render_mode cull_back, diffuse_burley, skip_vertex_transform;

global uniform float night;
global uniform float wetness;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"
global uniform float traffic_time;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.4;
// The kind's Blender bake on UV2 (VehicleTex: R ambient occlusion, B cavity).
uniform sampler2D bake_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform bool has_bake = false;
// 0 plain, 1 paint (clearcoat), 2 glass (sky reflections), 3 chrome.
uniform int finish = 0;
uniform bool is_tail_lamp = false;
uniform bool is_far_lod = false;
uniform sampler2D lane_tex : filter_nearest, repeat_disable;

varying float v_braking;
varying float v_dist;

const float EASE = 12.0;     // Traffic.EASE
const float STEP = 3.0;      // Traffic.STEP
const int TEX_W = 1024;      // Traffic.TEX_W

vec4 lane_px(sampler2D tex, int i) {
	return texelFetch(tex, ivec2(i % TEX_W, i / TEX_W), 0);
}

void vertex() {
	float base_f = MODEL_MATRIX[1][0] * 65536.0;
	float s0 = MODEL_MATRIX[2][0] * 1024.0;
	float t0 = MODEL_MATRIX[2][1] * 1024.0;
	float v = MODEL_MATRIX[3][0];
	float stop = MODEL_MATRIX[3][1];
	float e = MODEL_MATRIX[3][2];
	float dt = max(traffic_time - t0, 0.0);
	float s;
	if (v >= 0.0) {
		s = s0 + v * dt;
	} else {
		float x = -v * dt;
		s = s0 + (x <= 2.0 * EASE ? x * x / (4.0 * EASE) : x - EASE);
	}
	float u = s - (stop - e);
	if (u > 0.0) {
		s = u < 2.0 * e ? stop - e + u - u * u / (4.0 * e) : stop;
	}
	v_braking = max(INSTANCE_CUSTOM.x, (stop < 1.0e8 && u > 0.0) ? 1.0 : 0.0);
	int capacity = textureSize(lane_tex, 0).y * TEX_W;
	bool has_lane = base_f >= 1.0 && base_f < float(capacity - 1);
	int base = has_lane ? int(base_f + 0.5) : 1;
	vec4 hd = lane_px(lane_tex, base - 1);
	if (has_lane && hd.x >= 2.0 && hd.x <= float(capacity - base)) {
		float n = hd.x;
		bool loop = hd.y > 0.5;
		float f = s / STEP;
		f = loop ? mod(f, n - 1.0) : clamp(f, 0.0, n - 1.001);
		int i = int(floor(f));
		float k = f - float(i);
		int last = int(n + 0.5) - 1;
		// (Loops repeat their first point at the end: indices wrap over n - 1.)
		int im = loop ? (i == 0 ? last - 1 : i - 1) : max(i - 1, 0);
		int i2 = loop ? (i + 2 > last ? i + 2 - last : i + 2) : min(i + 2, last);
		vec3 p0 = lane_px(lane_tex, base + im).xyz;
		vec3 p1 = lane_px(lane_tex, base + i).xyz;
		vec3 p2 = lane_px(lane_tex, base + i + 1).xyz;
		vec3 p3 = lane_px(lane_tex, base + i2).xyz;
		vec3 pos = mix(p1, p2, k);
		vec3 fw = mix(p2 - p0, p3 - p1, k);
		fw = length(fw) > 1e-4 ? normalize(fw) : vec3(0.0, 0.0, -1.0);
		vec3 zb = -fw;
		vec3 xb = normalize(cross(vec3(0.0, 1.0, 0.0), zb));
		vec3 yb = cross(zb, xb);
		mat3 B = mat3(xb, yb, zb);
		vec3 world = pos + B * VERTEX;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		NORMAL = normalize(mat3(VIEW_MATRIX) * (B * NORMAL));
		v_dist = length(VERTEX);
	} else {
		// The instance has no complete lane; collapse it to one point.
		VERTEX = vec3(0.0, 0.0, -1.0);
		v_dist = 9999.0;
	}
}

void fragment() {
	vec3 c = use_instance_color ? COLOR.rgb : tint;
	vec3 bk = has_bake ? texture(bake_tex, UV2).rgb : vec3(1.0);
	ALBEDO = c * (0.7 + 0.3 * bk.b);
	AO = bk.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = mix(roughness, roughness * 0.5, wetness);
	METALLIC = use_instance_color ? 0.35 : 0.0;
	if (finish == 1) {
		// Lacquered paint: a glossy clear coat over a slightly metallic base.
		METALLIC = 0.33;
		ROUGHNESS = mix(0.36, 0.23, wetness);
		CLEARCOAT = 0.58;
		CLEARCOAT_ROUGHNESS = 0.18;
	} else if (finish == 2) {
		// Glass as on your own car (car_glass.gdshader): dark tint, smooth,
		// the city reflected strongest at grazing angles (below). It was a
		// near-mirror metal and read oddly next to the player's car.
		ALBEDO = vec3(0.037, 0.043, 0.046);
		METALLIC = 0.02;
		ROUGHNESS = 0.18;
		SPECULAR = 0.5;
	} else if (finish == 3) {
		METALLIC = 1.0;
		ROUGHNESS = 0.16;
		ALBEDO = max(c, vec3(0.55));
	}
	bool brake_on = v_braking > 0.5 && (is_tail_lamp || (emission > 0.5 && tint.r > 0.45 && tint.g < 0.12 && tint.b < 0.12));
	if (brake_on) {
		EMISSION = vec3(1.0, 0.04, 0.02) * (3.4 + 2.8 * night);
	} else {
		EMISSION = tint * emission * (1.0 + 3.5 * night);  // headlights and tail lights after dark
	}
	if (finish > 0) {
		if (!is_far_lod && v_dist < 140.0) {
			// The city in paint, glass and chrome (fake_reflect.gdshaderinc).
			vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
			vec3 rw = reflect(-vw, nw);
			vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			vec3 env = finish == 1 ? paint_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night)
				: city_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night);
			float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), finish == 2 ? 3.0 : 4.0);
			float k = finish == 1 ? mix(0.09, 0.36, fres) : (finish == 2 ? mix(0.11, 0.48, fres) : 0.65);
			float glint = pow(max(dot(rw, normalize(sun_dir)), 0.0), finish == 1 ? 220.0 : 300.0) * (finish == 1 ? 0.9 : 0.75);
			EMISSION += (env * k + vec3(glint) * (1.0 - night)) * (1.0 - 0.55 * night) * bk.r;
		} else {
			// Far-LOD lightweight sky sheen (skips INV_VIEW_MATRIX & procedural skyline reflection).
			float fres_far = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
			vec3 sky_far = mix(sky_horizon, sky_top, 0.45) * (1.0 - 0.55 * night);
			float k_far = finish == 1 ? mix(0.08, 0.24, fres_far) : (finish == 2 ? mix(0.10, 0.34, fres_far) : 0.45);
			EMISSION += sky_far * k_far;
		}
	}
}
