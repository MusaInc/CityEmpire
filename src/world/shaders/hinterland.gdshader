shader_type spatial;
render_mode diffuse_burley, specular_disabled;
// Hills and mountains round the bay (Hinterland): sand at the waterline,
// meadow and forest on the foothills, rock on steep or high ground, snow on
// the highest western peaks. World-space noise breaks up every band; the
// scene fog does the aerial perspective.

global uniform float night;
global uniform vec3 sky_horizon;
global uniform float wetness;

varying vec3 v_world;
varying vec3 v_wn;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.5 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.2; }

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float y = v_world.y;
	vec2 p = v_world.xz;
	float slope = 1.0 - clamp(v_wn.y, 0.0, 1.0);          // 0 flat … 1 vertical
	float n = fbm(p * 0.006);
	float n2 = fbm(p * 0.03);
	vec3 sand = vec3(0.68, 0.61, 0.47);
	vec3 meadow = mix(vec3(0.24, 0.34, 0.14), vec3(0.36, 0.42, 0.19), n2);
	vec3 forest = mix(vec3(0.08, 0.14, 0.08), vec3(0.14, 0.21, 0.11), n2);
	vec3 rock = mix(vec3(0.29, 0.28, 0.27), vec3(0.45, 0.41, 0.36), n2 * 0.7 + vnoise(p * 0.0025) * 0.3);
	vec3 snow = vec3(0.90, 0.92, 0.96);
	// Forest on the middle slopes, patchy; meadow lower and on flats.
	float forest_k = smoothstep(0.28, 0.52, n + 0.3 * smoothstep(20.0, 200.0, y)) * (1.0 - smoothstep(380.0, 560.0, y + n * 120.0));
	vec3 c = mix(meadow, forest, forest_k);
	c = mix(sand, c, smoothstep(1.5, 9.0, y + n2 * 4.0));
	// Treeline ~520 m (ragged), then scree and bare rock in strata; steep
	// faces are rock at any height.
	float rocky = smoothstep(0.42, 0.62, slope + n * 0.15) + smoothstep(500.0, 760.0, y + n * 180.0 - slope * 120.0);
	vec3 scree = mix(vec3(0.42, 0.40, 0.37), vec3(0.31, 0.30, 0.29), vnoise(p * 0.012));
	rock = mix(rock, scree, (1.0 - smoothstep(0.15, 0.35, slope)) * 0.45);
	c = mix(c, rock, clamp(rocky, 0.0, 1.0));
	// Snow only on the high massifs: lower on shaded (north-facing) slopes,
	// lying in gullies and on gentle ledges, never on the steep faces – so
	// the summits are patched white instead of a crust along the skyline.
	float north_face = clamp(-v_wn.z, -1.0, 1.0);
	float line = 820.0 - 120.0 * north_face + n * 150.0 - n2 * 60.0;
	float snowy = smoothstep(line, line + 90.0, y) * (1.0 - smoothstep(0.42, 0.62, slope + n2 * 0.1));
	c = mix(c, snow, snowy);
	// Wet sand darkens at the waterline.
	c *= 1.0 - 0.25 * (1.0 - smoothstep(-1.0, 2.5, y));
	// Ground detail the 45 m mesh can't carry: forest canopy as dark/light
	// clumps, rock strata, and small-scale relief in the normal so light
	// rakes across the slopes instead of shading one smooth sheet.
	float canopy = vnoise(p * 0.11) * 0.6 + vnoise(p * 0.31) * 0.4;
	c *= mix(1.0, 0.72 + 0.5 * canopy, forest_k * (1.0 - clamp(rocky, 0.0, 1.0)));
	c *= mix(1.0, 0.85 + 0.25 * vnoise(vec2(p.x * 0.004, y * 0.25)), clamp(rocky, 0.0, 1.0) * (1.0 - snowy));
	float e = 3.0;
	float s0 = fbm(p * 0.045);
	float gx = fbm((p + vec2(e, 0.0)) * 0.045) - s0;
	float gz = fbm((p + vec2(0.0, e)) * 0.045) - s0;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	// (Far off the fine relief only shimmers: fade it.)
	float amp = 6.0 * (0.4 + 0.6 * clamp(rocky + forest_k * 0.6, 0.0, 1.0)) * (1.0 - 0.75 * smoothstep(1800.0, 5000.0, dist));
	vec3 wn = normalize(v_wn - vec3(gx, 0.0, gz) * amp);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// Aerial perspective on top of the scene fog: distant ranges lose
	// contrast and go blue-grey toward the horizon colour.
	float haze = (1.0 - exp(-dist / 11000.0)) * 0.32 * (1.0 - night);
	vec3 emit = sky_horizon * haze * 0.55;
	// Subtle distant foothill town & coastal settlement light clusters at night
	// along low gentle slopes so the bay horseshoe feels alive after dark.
	if (night > 0.15 && y > 3.5 && y < 225.0 && slope < 0.38) {
		float elev_band = smoothstep(3.5, 16.0, y) * (1.0 - smoothstep(130.0, 225.0, y));
		float gentle = 1.0 - smoothstep(0.16, 0.38, slope);
		float cluster = smoothstep(0.56, 0.80, vnoise(p * 0.0019 + 11.4));
		if (cluster > 0.01) {
			vec2 cell = p / 24.0;
			vec2 id = floor(cell);
			vec2 f = fract(cell) - 0.5;
			float rnd = h21(id + 37.0);
			vec2 jitter = (vec2(h21(id + 5.1), h21(id + 13.7)) - 0.5) * 0.55;
			float pin = 1.0 - smoothstep(0.08, 0.28, length(f - jitter));
			float lit = step(0.58, rnd) * pin;
			vec3 lcol = mix(vec3(1.0, 0.72, 0.38), vec3(0.86, 0.92, 1.0), step(0.86, fract(rnd * 17.3)));
			float night_k = smoothstep(0.15, 0.65, night);
			float far_fade = exp(-dist / 12000.0);
			// Soft ambient town-glow wash under each settlement + discrete pinpricks.
			emit += (vec3(0.95, 0.66, 0.34) * 0.045 + lcol * lit * (0.45 + 0.75 * fract(rnd * 9.1)))
				* cluster * elev_band * gentle * night_k * far_fade;
		}
	}
	ALBEDO = c * (1.0 - haze);
	EMISSION = emit;
	ROUGHNESS = mix(0.95, 0.6, snowy);
}
