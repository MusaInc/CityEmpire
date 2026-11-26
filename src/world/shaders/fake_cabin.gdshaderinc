// See-through windows on sealed car shells (2026-11-26: "all cars need to
// have transparent windows"). The fleet bodies have their panes laid on the
// painted shell with no cabin behind, so real transparency would show paint.
// Instead each pane traces the view ray into a cabin box (model space; the
// car's front is -Z) and draws what you'd see through the glass: seat backs
// and headrests (front and rear rows), the floor, the headliner, door panels
// below the belt line, and – where the ray reaches the far side's windows –
// the street and sky beyond. One box intersection and two plane tests per
// pixel: mobile-cheap, no extra geometry, works on every LOD.

vec3 cabin_outside(vec3 dir_world, vec3 sky_h, vec3 sky_t, float nite) {
	float up = smoothstep(-0.15, 0.35, dir_world.y);
	vec3 street = mix(vec3(0.15, 0.155, 0.16), sky_h * 0.55, 0.35) * (1.0 - 0.82 * nite) + vec3(0.035, 0.028, 0.02) * nite;
	vec3 sky = mix(sky_h, sky_t, smoothstep(0.2, 0.8, dir_world.y));
	return mix(street, sky, up);
}

// p, d: point on the pane and view direction, model space (d into the car).
// Returns the colour seen through the pane (unlit: the caller scales it by
// the ambient level) and in `through` how much of it is the outside world.
vec3 fake_cabin(vec3 p, vec3 d, vec3 bmin, vec3 bmax, vec3 outside, out float through) {
	vec3 q = clamp(p, bmin + vec3(0.001), bmax - vec3(0.001));
	vec3 dd = d;
	dd.x = abs(dd.x) < 1e-4 ? 1e-4 : dd.x;
	dd.y = abs(dd.y) < 1e-4 ? 1e-4 : dd.y;
	dd.z = abs(dd.z) < 1e-4 ? 1e-4 : dd.z;
	vec3 t1 = (bmin - q) / dd;
	vec3 t2 = (bmax - q) / dd;
	vec3 tf = max(t1, t2);
	float tx = min(min(tf.x, tf.y), tf.z);
	vec3 h = q + dd * tx;
	vec3 size = bmax - bmin;
	float belt = bmin.y + 0.40 * size.y;
	vec3 trim = vec3(0.040, 0.041, 0.045);
	vec3 col;
	through = 0.0;
	if (tx == tf.y) {
		col = dd.y > 0.0 ? vec3(0.17, 0.165, 0.155) : vec3(0.022, 0.022, 0.024);   // headliner / carpet
	} else if (h.y > belt) {
		col = outside;            // the far side's window: the world beyond
		through = 1.0;
	} else {
		col = trim;               // door panels, dash, boot wall
	}
	// Seat backs (vertical planes across the car) with headrests, front row
	// split in two; nearer seats hide farther ones.
	float zs[2] = float[2](bmin.z + 0.46 * size.z, bmin.z + 0.80 * size.z);
	float best = tx;
	for (int i = 0; i < 2; i++) {
		float ts = (zs[i] - q.z) / dd.z;
		if (ts <= 0.0 || ts >= best) {
			continue;
		}
		vec3 s = q + dd * ts;
		float hx = 0.5 * size.x;
		float cx = 0.5 * (bmin.x + bmax.x);
		float ax = abs(s.x - cx);
		float yy = (s.y - bmin.y) / size.y;
		bool front = i == 0;
		float seat_w = front ? 0.40 * hx : 0.92 * hx;
		float seat_c = front ? 0.50 * hx : 0.0;
		bool back = yy < 0.58 && (front ? abs(ax - seat_c) < seat_w : ax < seat_w);
		bool rest = yy >= 0.58 && yy < 0.74 && (front ? abs(ax - seat_c) < 0.42 * seat_w : abs(ax - 0.5 * hx) < 0.17 * hx);
		if (back || rest) {
			// a soft vertical shade across the seat (bolsters darker)
			float edge = front ? abs(ax - seat_c) / seat_w : ax / seat_w;
			col = vec3(0.055, 0.054, 0.058) * (1.05 - 0.35 * edge * edge) * (rest ? 0.9 : 1.0);
			through = 0.0;
			best = ts;
		}
	}
	return col;
}

// The cabin box from the body's bounds (min/max of the whole shell, model space).
void cabin_box(vec3 body_min, vec3 body_max, out vec3 bmin, out vec3 bmax) {
	vec3 sz = body_max - body_min;
	bmin = vec3(body_min.x + 0.10, body_min.y + 0.30 * sz.y, body_min.z + 0.22 * sz.z);
	bmax = vec3(body_max.x - 0.10, body_max.y - 0.06, body_max.z - 0.12 * sz.z);
}
