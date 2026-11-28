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
uniform bool is_turn_lamp = false;
uniform bool is_far_lod = false;
uniform sampler2D lane_tex : filter_nearest, repeat_disable;

#include "res://src/world/shaders/fake_cabin.gdshaderinc"
uniform bool sealed = false;
uniform vec3 body_min = vec3(-0.9, 0.0, -2.2);
uniform vec3 body_max = vec3(0.9, 1.5, 2.2);
varying vec3 v_local;
varying vec3 v_cam;
varying float v_braking;
varying float v_turn;
varying float v_dist;

const float EASE = 12.0;     // Traffic.EASE
const float STEP = 3.0;      // Traffic.STEP
const int TEX_W = 1024;      // Traffic.TEX_W

vec4 lane_px(sampler2D tex, int i) {
	return texelFetch(tex, ivec2(i % TEX_W, i / TEX_W), 0);
}

#include "res://src/world/shaders/traffic_frame.gdshaderinc"

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
	v_turn = INSTANCE_CUSTOM.z;
	int capacity = textureSize(lane_tex, 0).y * TEX_W;
	bool has_lane = base_f >= 1.0 && base_f < float(capacity - 1);
	int base = has_lane ? int(base_f + 0.5) : 1;
	vec4 hd = lane_px(lane_tex, base - 1);
	if (has_lane && hd.x >= 2.0 && hd.x <= float(capacity - base)) {
		float n = hd.x;
		bool loop = hd.y > 0.5;
		vec3 pos;
		mat3 B = traffic_frame(lane_tex, base, n, loop, s, pos);
		vec3 lv = VERTEX;
		vec3 ln = NORMAL;
		if (!is_far_lod) {
			float curv = traffic_curvature(lane_tex, base, n, loop, s);
			float spd_n = clamp(abs(v) / 14.0, 0.0, 1.0);
			traffic_apply_suspension(lv, ln, v_braking, curv, spd_n);
		}
		v_local = lv;
		v_cam = transpose(B) * (INV_VIEW_MATRIX[3].xyz - pos);
		vec3 world = pos + B * lv;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		NORMAL = normalize(mat3(VIEW_MATRIX) * (B * ln));
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
	bool turn_side = (v_turn < -0.5 && v_local.x < -0.1) || (v_turn > 0.5 && v_local.x > 0.1);
	bool turn_blink = is_turn_lamp && turn_side && fract(traffic_time * 1.7) < 0.52;
	if (brake_on) {
		EMISSION = vec3(1.0, 0.04, 0.02) * (3.4 + 2.8 * night);
	} else if (turn_blink) {
		EMISSION = vec3(1.0, 0.48, 0.03) * (3.2 + 2.2 * night);
	} else {
		EMISSION = tint * emission * (1.0 + 3.5 * night);  // headlights and tail lights after dark
	}
	if (finish == 2 && sealed && v_dist < 220.0) {
		// See-through windows on sealed shells: smooth fade out over 195..220 m.
		float cab_k = smoothstep(220.0, 195.0, v_dist);
		vec3 bmin, bmax;
		cabin_box(body_min, body_max, bmin, bmax);
		vec3 dl = normalize(v_local - v_cam);
		vec3 dw = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
		float through;
		vec3 inside = fake_cabin(v_local, dl, bmin, bmax, cabin_outside(dw, sky_horizon, sky_top, night), through);
		float amb = dot(sky_horizon, vec3(0.3, 0.55, 0.15)) * 1.15 + 0.02;
		ALBEDO = mix(ALBEDO, vec3(0.012), cab_k);
		EMISSION += mix(inside * amb, inside, through) * vec3(0.80, 0.86, 0.88) * cab_k;
	}
	if (finish > 0) {
		float fres_far = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		vec3 sky_far = mix(sky_horizon, sky_top, 0.45) * (1.0 - 0.55 * night);
		float k_far = finish == 1 ? mix(0.08, 0.24, fres_far) : (finish == 2 ? mix(0.10, 0.34, fres_far) : 0.45);
		vec3 far_emit = sky_far * k_far;
		if (!is_far_lod && v_dist < 145.0) {
			// Smoothly blend city reflection into far sky sheen over 125..145 m.
			float refl_k = smoothstep(145.0, 125.0, v_dist);
			vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
			vec3 rw = reflect(-vw, nw);
			vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			vec3 env = finish == 1 ? paint_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night)
				: city_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night);
			float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), finish == 2 ? 3.0 : 4.0);
			float k = finish == 1 ? mix(0.09, 0.36, fres) : (finish == 2 ? mix(0.11, 0.48, fres) : 0.65);
			float glint = pow(max(dot(rw, normalize(sun_dir)), 0.0), finish == 1 ? 220.0 : 300.0) * (finish == 1 ? 0.9 : 0.75);
			vec3 near_emit = (env * k * fake_keep() + vec3(glint) * (1.0 - night)) * (1.0 - 0.55 * night) * bk.r;
			EMISSION += mix(far_emit, near_emit, refl_k);
		} else {
			EMISSION += far_emit;
		}
	}
}
