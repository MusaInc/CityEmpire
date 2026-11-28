// Shared by car_glass and car_glass_clear: collision cracks and shattering.
// Damage (CarVisual, from Car.glass): crack level per pane group – front
// (windscreen, laminated: crazes but stays), rear, left, right (tempered:
// past 1.0 they're gone). half_size = the body's half extents.
uniform vec4 crack = vec4(0.0);
uniform vec3 half_size = vec3(0.9, 0.75, 2.3);
varying vec3 v_p;
varying vec3 v_n;

void vertex() {
	v_p = VERTEX;
	v_n = NORMAL;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi edge: crazed glass.
float craze(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}


// 0..1 crack cover at this fragment, or -1 = this pane is gone (discard).
float glass_crack() {
	float cr = 0.0;
	vec2 cuv = v_p.xy;
	if (dot(crack, vec4(1.0)) > 0.001) {
		vec3 nn = normalize(v_n);
		bool side_pane = abs(nn.x) > 0.6;
		float which = side_pane ? (nn.x < 0.0 ? crack.z : crack.w) : (v_p.z < 0.0 ? crack.x : crack.y);
		cuv = side_pane ? v_p.zy : v_p.xy;
		if (which >= 0.999 && (side_pane || v_p.z > 0.0)) {
			// Tempered side/rear glass: cleanly blown out (zero floating pane).
			return -1.0;
		}
		if (which <= 0.001) {
			return 0.0;
		}
		// Multi-scale spiderweb impact fracture: tight frosted core, concentric
		// Voronoi rings and sharp radial fracture rays.
		vec2 hit = side_pane ? vec2(0.0, 0.95) : vec2(0.22, 0.92);
		float dist = length(cuv - hit);
		float reach = 0.25 + which * 1.65;
		float near_hit = 1.0 - smoothstep(reach * 0.35, reach + 0.02, dist);
		float fine = 1.0 - smoothstep(0.0, 0.042 + 0.024 * which, craze(cuv * mix(8.0, 20.0, which)));
		float coarse = 1.0 - smoothstep(0.0, 0.032 + 0.015 * which, craze(cuv * 5.2 + vec2(1.7, 3.1)));
		float ang = atan(cuv.y - hit.y, cuv.x - hit.x);
		float rays = 1.0 - smoothstep(0.0, 0.028, abs(fract(ang * 3.8 + hash2(floor(cuv * 2.5)).x * 0.22) - 0.5) * dist * 0.55);
		float core_frost = (1.0 - smoothstep(0.04, 0.16 + 0.14 * which, dist)) * smoothstep(0.35, 0.9, which) * 0.65;
		cr = clamp(max(max(fine, coarse * 0.7), max(rays * step(0.12, which), core_frost)) * near_hit * clamp(which * 2.2, 0.0, 1.0), 0.0, 1.0);
	}
	return cr;
}
