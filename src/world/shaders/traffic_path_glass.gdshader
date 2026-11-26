// Transparent automotive glazing for moving lane traffic (Traffic).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, skip_vertex_transform;

global uniform float night;
global uniform float wetness;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"
global uniform float traffic_time;
uniform vec3 tint : source_color = vec3(0.035, 0.045, 0.06);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.12;
uniform int finish = 2;
uniform bool is_tail_lamp = false;
uniform bool is_far_lod = false;
uniform sampler2D lane_tex : filter_nearest, repeat_disable;

const float EASE = 12.0;
const float STEP = 3.0;
const int TEX_W = 1024;

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
	int capacity = textureSize(lane_tex, 0).y * TEX_W;
	bool has_lane = base_f >= 1.0 && base_f < float(capacity - 1);
	int base = has_lane ? int(base_f + 0.5) : 1;
	vec4 hd = lane_px(lane_tex, base - 1);
	if (has_lane && hd.x >= 2.0 && hd.x <= float(capacity - base)) {
		float n = hd.x;
		bool loop = hd.y > 0.5;
		vec3 pos;
		mat3 B = traffic_frame(lane_tex, base, n, loop, s, pos);
		vec3 world = pos + B * VERTEX;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		NORMAL = normalize(mat3(VIEW_MATRIX) * (B * NORMAL));
	} else {
		VERTEX = vec3(0.0, 0.0, -1.0);
	}
}

void fragment() {
	ALBEDO = vec3(0.035, 0.045, 0.06);
	METALLIC = 0.04;
	ROUGHNESS = mix(0.09, 0.14, wetness);
	SPECULAR = 0.5;
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 rw = reflect(-vw, nw);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 env = city_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.8);
	float glint = pow(max(dot(rw, normalize(sun_dir)), 0.0), 240.0) * 0.62;
	EMISSION = (env * mix(0.11, 0.56, fres) * fake_keep() + vec3(glint) * (1.0 - night)) * (1.0 - 0.50 * night);
	ALPHA = mix(0.32, 0.84, fres);
}
