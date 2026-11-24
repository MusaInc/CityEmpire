// Contact-shadow variant of traffic_path.gdshader (moving traffic).
// Moving traffic (Traffic): cars follow lane polylines stored in lane_tex
// (texel = x, y, z every Traffic.STEP m; the texel before a lane's first is
// its header: point count, loop flag). Traffic stores motion in an
// invertible upper-triangular MODEL_MATRIX with exact power-of-two scales.
// All geometry is positioned in lane space and then written in view space.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

global uniform float night;
global uniform float wetness;
global uniform float traffic_time;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.4;
// 0 plain, 1 paint (clearcoat), 2 glass (sky reflections), 3 chrome.
uniform int finish = 0;
uniform sampler2D lane_tex : filter_nearest, repeat_disable;

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
	} else {
		// The instance has no complete lane; collapse it to one point.
		VERTEX = vec3(0.0, 0.0, -1.0);
	}
}

uniform float strength = 0.72;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	vec2 d = abs(q) - vec2(0.58, 0.68);
	float box_d = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
	float body_ao = 1.0 - smoothstep(-0.08, 0.36, box_d);
	float core_ao = 1.0 - smoothstep(-0.18, 0.14, box_d);
	float a = clamp(body_ao * 0.62 + core_ao * 0.42, 0.0, 1.0) * strength * mix(1.0, 0.54, night);
	ALBEDO = vec3(0.01, 0.012, 0.016);
	ALPHA = a;
}
