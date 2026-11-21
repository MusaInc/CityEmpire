// Headlight beam variant of traffic_path.gdshader: the light a moving car's
// dipped beams throw on the road ahead (additive, no real light: mobile
// budget), laid on the lane itself (see vertex()).
// Moving traffic (Traffic): cars follow lane polylines stored in lane_tex
// (texel = x, y, z every Traffic.STEP m; the texel before a lane's first is
// its header: point count, loop flag). The instance "transform" carries the
// car's motion, not a transform (full precision on every renderer):
//   row 0 = (first texel, s0, t0, v), row 1 = (stop m along the lane, its
//   ease distance, -, -).
// s = s0 + v (t - t0) (v < 0: pulling away from rest at |v|), eased to a
// stop at `stop`. The traffic node sits at the origin, so MODEL_MATRIX is
// that data; positions are computed here and output in view space.
// Fragment as traffic.gdshader.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

global uniform float night;
global uniform float wetness;
const float moving = 1.0;
global uniform float traffic_time;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.4;
uniform float beam = 0.85;
uniform sampler2D lane_tex : filter_nearest, repeat_disable;

const float EASE = 12.0;     // Traffic.EASE
const float STEP = 3.0;      // Traffic.STEP
const int TEX_W = 1024;      // Traffic.TEX_W

vec4 lane_px(sampler2D tex, int i) {
	return texelFetch(tex, ivec2(i % TEX_W, i / TEX_W), 0);
}

// The lane's point and direction at `s` m along it (Catmull-Rom-ish blend
// of the polyline, as the cars drive it).
void lane_at(int base, float n, bool loop, float s, out vec3 pos, out vec3 fw) {
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
	pos = mix(p1, p2, k);
	fw = mix(p2 - p0, p3 - p1, k);
	fw = length(fw) > 1e-4 ? normalize(fw) : vec3(0.0, 0.0, -1.0);
}

void vertex() {
	float base_f = MODEL_MATRIX[0][0];
	float s0 = MODEL_MATRIX[1][0];
	float t0 = MODEL_MATRIX[2][0];
	float v = MODEL_MATRIX[3][0];
	float stop = MODEL_MATRIX[0][1];
	float e = MODEL_MATRIX[1][1];
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
	int base = int(base_f + 0.5);
	vec4 hd = lane_px(lane_tex, base - 1);
	float n = hd.x;
	bool loop = hd.y > 0.5;
	// The beam is laid on the road the car is about to drive: each vertex
	// (a grid, CityWorld._beam_grid) sits on the lane `ahead` m further on,
	// its own height and heading – over a crest, down a hill, round a bend
	// – not on the plane of the car (that floated over dips and sank into
	// rises, like the old lamp pools). Past a lane's end it stays level.
	float ahead = -VERTEX.z;
	vec3 pos;
	vec3 fw;
	lane_at(base, n, loop, s + ahead, pos, fw);
	if (!loop && s + ahead > (n - 1.0) * STEP) {
		vec3 pe;
		vec3 fe;
		lane_at(base, n, loop, (n - 1.0) * STEP - 0.01, pe, fe);
		pos = pe + fe * (s + ahead - (n - 1.0) * STEP);
		fw = fe;
	}
	vec3 zb = -fw;
	vec3 xb = normalize(cross(vec3(0.0, 1.0, 0.0), zb));
	vec3 world = pos + xb * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	// No lamps by day: no fragments at all.
	if (night < 0.2) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	// UV.y 0 at the bumper .. 1 at the far end, UV.x across. Two lamps whose
	// throws merge a few metres out; bright from ~2 m to ~12 m, then a long
	// fade (dipped beam), stronger on a wet road.
	float t = UV.y;
	float x = abs(UV.x - 0.5) * 2.0;
	float lobes = exp(-pow((x - 0.25) / 0.45, 2.0));
	float edge = (1.0 - smoothstep(0.75, 1.0, x));
	float a = smoothstep(0.0, 0.1, t) * pow(1.0 - t, 1.5) * lobes * edge * (0.6 + 0.4 * wetness);
	ALBEDO = vec3(1.0, 0.92, 0.78) * a * beam * smoothstep(0.25, 0.7, night) * moving;
}
