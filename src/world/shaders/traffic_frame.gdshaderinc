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

// Curvature estimate (signed rad per ~6 m) from the 4 lane points for body roll.
float traffic_curvature(sampler2D tex, int base, float n, bool loop, float s) {
	float f = s / STEP;
	f = loop ? mod(f, n - 1.0) : clamp(f, 0.0, n - 1.001);
	int i = int(floor(f));
	int last = int(n + 0.5) - 1;
	int im = loop ? (i == 0 ? last - 1 : i - 1) : max(i - 1, 0);
	int i2 = loop ? (i + 2 > last ? i + 2 - last : i + 2) : min(i + 2, last);
	vec2 a = lane_px(tex, base + i).xz - lane_px(tex, base + im).xz;
	vec2 b = lane_px(tex, base + i2).xz - lane_px(tex, base + i + 1).xz;
	float la = length(a);
	float lb = length(b);
	if (la < 0.05 || lb < 0.05) return 0.0;
	a /= la;
	b /= lb;
	return clamp(a.x * b.y - a.y * b.x, -0.5, 0.5);
}

// Subtle suspension dive under braking and body roll through curves (body + glass stay locked).
void traffic_apply_suspension(inout vec3 v, inout vec3 n, float braking, float curv, float spd_norm) {
	float pitch = -0.024 * braking * clamp(spd_norm * 1.5, 0.25, 1.0);
	float roll = clamp(curv * spd_norm * 0.085, -0.045, 0.045);
	float cy = 0.42;
	vec3 r = v - vec3(0.0, cy, 0.0);
	if (abs(pitch) > 0.0005) {
		float cp = cos(pitch);
		float sp = sin(pitch);
		r = vec3(r.x, r.y * cp - r.z * sp, r.y * sp + r.z * cp);
		n = vec3(n.x, n.y * cp - n.z * sp, n.y * sp + n.z * cp);
	}
	if (abs(roll) > 0.0005) {
		float cr = cos(roll);
		float sr = sin(roll);
		r = vec3(r.x * cr - r.y * sr, r.x * sr + r.y * cr, r.z);
		n = vec3(n.x * cr - n.y * sr, n.x * sr + n.y * cr, n.z);
	}
	v = r + vec3(0.0, cy, 0.0);
}
