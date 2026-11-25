// Moving traffic's rigid road frame (Traffic lanes in lane_tex), shared by
// the body, glass and contact-shadow shaders so every part moves as one:
// plan position and heading from the smoothed lane at the car's centre;
// height and pitch from the lane under each axle (half a wheelbase ahead and
// behind), so both axles sit on the road over crests, dips and ramp ends.
// (One tangent at the centre left the wheels buried in every sag and
// floating over every crest.) Needs lane_px(), STEP and TEX_W first.
const float TF_AXLE = 1.35;

vec3 tf_point(sampler2D tex, int base, float n, bool loop, float s) {
	float f = s / STEP;
	f = loop ? mod(f, n - 1.0) : clamp(f, 0.0, n - 1.001);
	int i = int(floor(f));
	float k = f - float(i);
	return mix(lane_px(tex, base + i).xyz, lane_px(tex, base + i + 1).xyz, k);
}

mat3 traffic_frame(sampler2D tex, int base, float n, bool loop, float s, out vec3 pos) {
	float f = s / STEP;
	f = loop ? mod(f, n - 1.0) : clamp(f, 0.0, n - 1.001);
	int i = int(floor(f));
	float k = f - float(i);
	int last = int(n + 0.5) - 1;
	int im = loop ? (i == 0 ? last - 1 : i - 1) : max(i - 1, 0);
	int i2 = loop ? (i + 2 > last ? i + 2 - last : i + 2) : min(i + 2, last);
	vec3 p0 = lane_px(tex, base + im).xyz;
	vec3 p1 = lane_px(tex, base + i).xyz;
	vec3 p2 = lane_px(tex, base + i + 1).xyz;
	vec3 p3 = lane_px(tex, base + i2).xyz;
	pos = mix(p1, p2, k);
	vec3 fw = mix(p2 - p0, p3 - p1, k);
	vec2 h = length(fw.xz) > 1e-4 ? normalize(fw.xz) : vec2(0.0, -1.0);
	vec3 pf = tf_point(tex, base, n, loop, s + TF_AXLE);
	vec3 pr = tf_point(tex, base, n, loop, s - TF_AXLE);
	float run = max(length(pf.xz - pr.xz), 0.5);
	float grade = clamp((pf.y - pr.y) / run, -0.6, 0.6);
	pos.y = 0.5 * (pf.y + pr.y);
	vec3 fw3 = normalize(vec3(h.x, grade, h.y));
	vec3 zb = -fw3;
	vec3 xb = normalize(cross(vec3(0.0, 1.0, 0.0), zb));
	vec3 yb = cross(zb, xb);
	return mat3(xb, yb, zb);
}
