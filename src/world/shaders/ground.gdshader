// Streets, pavements, lawns. COLOR.rgb tint; UV = world XZ metres on the
// flat surfaces (kerb faces keep their own UVs).
// With the road field (CityRoads.bake_field: per texel the nearest road's
// signed offset, half width (negative = boulevard), distance along it and the
// distance to the nearest other road's kerb) the asphalt gets its lane paint
// (following curves), zebra crossings and stop lines at every junction
// mouth, tyre wear, gutters, drains, manholes and patch repairs; pavements
// get a kerb edge, flagstones by the road and larger paving / brick in the
// courtyards behind; lawns get mowing stripes and a gravel path round the
// edge. All of it is maths on one 2-D lookup – no extra geometry.
shader_type spatial;
render_mode cull_back, diffuse_burley;
#include "res://src/world/shaders/grass.gdshaderinc"

uniform sampler2D road_field : filter_nearest, repeat_disable;
uniform vec4 road_rect = vec4(0.0, 0.0, 1.0, 1.0);  // x, z origin, x, z size (m)
uniform bool has_streets = false;
uniform sampler2D asph_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D pave_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform bool pbr_on = false;
uniform vec4 wet_road_lamps[4];
#include "res://src/world/shaders/pbr_detail.gdshaderinc"
global uniform float night;
global uniform float wetness;
global uniform vec3 sky_horizon;

#include "res://src/world/shaders/rock.gdshaderinc"
varying float v_up;
varying vec3 v_world;
varying vec3 v_wn;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

// 1 inside a band of half-width h around 0, antialiased by aa.
float band(float d, float h, float aa) {
	return 1.0 - smoothstep(h - aa, h + aa, abs(d));
}

// The road field at p, blended by hand (texelFetch) so the blend can't
// invent road between texels: the half width and kind come from the nearest
// texel (constant per road – blended across two roads it read as a third,
// narrower one); the offset is signed near a centre line but blended as a
// magnitude once any texel lies beyond its kerb (the sign flips where the
// nearest road changes, and a signed blend passed through 0: a false lane a
// few metres behind every kerb); the distance along is unwrapped (mod 64)
// before blending and keeps the nearest texel's roundabout flag (+64/+128).
vec4 road_sample(vec2 p) {
	ivec2 sz = textureSize(road_field, 0);
	vec2 uv = (p - road_rect.xy) / road_rect.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec4(100.0, 0.0, 0.0, 100.0);   // off the network
	}
	vec2 tc = uv * vec2(sz) - 0.5;
	vec2 f = fract(tc);
	ivec2 i0 = ivec2(floor(tc));
	ivec2 mx = sz - 1;
	vec4 t00 = texelFetch(road_field, clamp(i0, ivec2(0), mx), 0);
	vec4 t10 = texelFetch(road_field, clamp(i0 + ivec2(1, 0), ivec2(0), mx), 0);
	vec4 t01 = texelFetch(road_field, clamp(i0 + ivec2(0, 1), ivec2(0), mx), 0);
	vec4 t11 = texelFetch(road_field, clamp(i0 + ivec2(1, 1), ivec2(0), mx), 0);
	vec4 wt = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	vec4 tn = f.x < 0.5 ? (f.y < 0.5 ? t00 : t01) : (f.y < 0.5 ? t10 : t11);
	vec4 xs = vec4(t00.x, t10.x, t01.x, t11.x);
	vec4 hws = abs(vec4(t00.y, t10.y, t01.y, t11.y));
	if (any(greaterThan(abs(xs), hws + 1.0))) {
		xs = abs(xs);
	}
	// Texels of another road (a jump bigger than a cell) take the nearest
	// texel's offset: blended across two roads, 'across' swept through 0 and
	// every line value along a junction box's edge – squiggles of centre and
	// edge line round the bridge approaches' boxes (2026-11-18).
	float xn = f.x < 0.5 ? (f.y < 0.5 ? xs.x : xs.z) : (f.y < 0.5 ? xs.y : xs.w);
	float lim = 1.6 * road_rect.z / float(sz.x);
	xs = mix(xs, vec4(xn), vec4(greaterThan(abs(xs - xn), vec4(lim))));
	vec4 zs = vec4(t00.z, t10.z, t01.z, t11.z);
	vec4 zl = zs - floor(zs / 64.0) * 64.0;
	zl += 64.0 * vec4(lessThan(zl - zl.x, vec4(-32.0))) - 64.0 * vec4(greaterThan(zl - zl.x, vec4(32.0)));
	float z = mod(dot(zl, wt), 64.0) + floor(tn.z / 64.0) * 64.0;
	return vec4(dot(xs, wt), tn.y, z, dot(vec4(t00.w, t10.w, t01.w, t11.w), wt));
}

void vertex() {
	v_up = NORMAL.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// Street age by quarter (mirrors building.gdshader's quarter()): newer,
// well-kept streets in the financial core, the most worn in the docks and
// on Westbank; broad patches vary it (a resurfaced stretch, a neglected
// corner) so whole quarters aren't uniform.
float street_age(vec2 p) {
	float a = 0.35;
	if (p.x < 30.0) a = 0.65;
	else if (p.x < 250.0 && p.y > -330.0 && p.y < 260.0) a = 0.3;
	else if (p.y >= 260.0 && p.x < 560.0) a = 0.85;
	else if (p.x > 780.0 || p.y < -540.0 || p.y > 520.0) a = 0.55;
	else if (distance(p, vec2(560.0, -170.0)) < 330.0) a = mix(0.1, 0.35, smoothstep(240.0, 330.0, distance(p, vec2(560.0, -170.0))));
	return clamp(a + (vnoise(p / 70.0) - 0.5) * 0.5, 0.0, 1.0);
}

// The closest real lamp heads supply a small rough reflection. Locate
// the mirror point on the local road plane and broaden it along the line
// of sight for the wet aggregate. The material's ordinary lighting stays
// in use for diffuse light and for all other surfaces.
float wet_lamp_reflection(vec4 lamp, vec3 road, vec3 cam, float puddle, float aggregate) {
	float lamp_height = lamp.y - road.y;
	float eye_height = cam.y - road.y;
	if (lamp.w == 0.0 || lamp_height < 1.0 || eye_height < 0.35) {
		return 0.0;
	}
	vec2 ray = lamp.xz - cam.xz;
	float separation = length(ray);
	vec2 axis = ray / max(separation, 0.1);
	vec2 mirror = cam.xz + ray * eye_height / (eye_height + lamp_height);
	vec2 delta = road.xz - mirror;
	float across = dot(delta, vec2(-axis.y, axis.x));
	float along = dot(delta, axis);
	float length_scale = 0.9 + 0.061 * separation;
	float core_width = mix(0.44, 0.21, puddle);
	across += (aggregate - 0.5) * (0.14 - 0.10 * puddle);
	vec2 ellipse = vec2(across / core_width, along / length_scale);
	float fade = 1.0 - smoothstep(27.0, 59.0, separation);
	float core = exp2(-1.65 * dot(ellipse, ellipse));
	float fringe = exp2(-1.8 * dot(ellipse * vec2(0.58, 0.74), ellipse * vec2(0.58, 0.74)));
	return (core + 0.15 * fringe) * fade;
}

void fragment() {
	float camera_distance = length(VERTEX);
	vec3 c = COLOR.rgb;
	vec2 p = UV;
	float n = vnoise(p * 0.35) * 0.6 + vnoise(p * 2.1) * 0.4;
	float near = 1.0 - smoothstep(70.0, 240.0, camera_distance);  // fine detail fades out (no shimmer)
	float aa = max(fwidth(p.x) + fwidth(p.y), 0.004) * 0.6;
	vec3 albedo = c * (0.88 + 0.2 * n);
	float rough = 0.92;
	float wheel_tracks = 0.0;
	float shoulder_depression = 0.0;
	float paint_coverage = 0.0;
	float kerb_dist = 0.0;
	bool flat_top = v_up > 0.5;
	bool asphalt = c.r < 0.3 && c.g < 0.3;
	bool grass = c.g > c.r + 0.08;
	bool pave = c.r > 0.5 && c.g > 0.5 && c.r < 0.85;

	bool shore = abs(COLOR.a * 8.0 - 5.0) < 0.3;  // BuildingMesher.KIND_SHORE

	if (shore) {
		// Rock (rock.gdshaderinc: the same look on every shore) or sand on
		// the beaches, blended by the vertex colour so a beach fades into
		// rock along the coast instead of switching on a line.
		float sk = smoothstep(0.35, 0.65, c.r);
		vec3 rk = vec3(0.0);
		float rr = 0.9;
		if (sk < 0.999) {
			float fp = fwidth(p.x) + fwidth(p.y);
			rk = rock_look(vec3(0.23, 0.225, 0.225) * mix(1.0, c.r / 0.23, step(c.r, 0.34)), v_world, normalize(v_wn), fp, near, rr);
		}
		vec3 sd = vec3(0.0);
		if (sk > 0.001) {
			sd = vec3(0.78, 0.7, 0.52) * (0.93 + 0.08 * vnoise(p * 0.45) + 0.04 * vnoise(p * 3.1));
			float rip = sin(p.x * 1.7 + p.y * 1.1 + vnoise(p * 0.3) * 4.0) * 0.5 + 0.5;
			sd *= 0.97 + 0.05 * rip * near;
			sd *= 1.0 - 0.1 * (1.0 - smoothstep(0.0, 0.03, abs(v_world.y + 1.15)));   // tide line (sea at -1.6)
			float wet = 1.0 - smoothstep(-1.7, -1.0, v_world.y);
			sd *= 1.0 - 0.38 * wet;
		}
		albedo = mix(rk, sd, sk);
		rough = mix(rr, mix(0.97, 0.4, 1.0 - smoothstep(-1.7, -1.0, v_world.y)), sk);
	} else if (c.r > 0.85) {
		albedo = c * (0.9 + 0.1 * n);  // old painted geometry (prototype world)
	} else if (has_streets && flat_top) {
		vec4 rf = road_sample(p);
		// Screen derivatives of 'along' (mod-64 wrap skipped) and of the
		// distance to the junction, taken here (not inside the paint branches,
		// where neighbouring pixels can take other paths): their angle says
		// whether the junction lies straight ahead along the road (stop lines,
		// crossings, arrows) or off to one side round a corner.
		float along_d = mod(rf.z, 64.0);
		vec2 g_al = vec2(dFdx(along_d), dFdy(along_d));
		g_al *= step(abs(g_al), vec2(8.0));
		vec2 g_fj = vec2(dFdx(rf.w), dFdy(rf.w));
		float fj_cos = dot(g_al, g_fj) / (length(g_al) * length(g_fj) + 1e-5);
		float j_aligned = smoothstep(0.72, 0.82, abs(fj_cos));
		float hw = abs(rf.y);
		// (A roundabout's ring carries +0.25 on its half width: see CityRoads.bake_field.)
		float ring = step(0.3, fract(hw * 2.0)) * step(fract(hw * 2.0), 0.7);
		hw -= 0.25 * ring;
		float a = abs(rf.x);
		bool on = a < hw;
		float other = rf.w;                     // metres from the nearest other road's kerb (< 0: junction)
		// Metres from the nearest kerb line (negative on the road).
		float kerb = min(a - hw, other);
		kerb_dist = kerb;
		if (asphalt) {
			// Aged tarmac: neutral grey (not blue), with a broad tone drift
			// (resurfaced stretches, sun-bleached runs) and fine aggregate
			// mottling up close, so shaded streets still read as a surface.
			float drift = vnoise(p * 0.022 + 31.0) * 0.6 + vnoise(p * 0.09) * 0.4;
			float grain = (vnoise(p * 3.1) - 0.5) * near;
			// (2026-11-21 cinematic pass) Darker, real-asphalt albedo (~0.08-0.12
			// linear: it read chalky in full sun) with a faint warm/cool drift,
			// and aggregate: stones at two scales, faded with their pixel size so
			// they never shimmer.
			albedo = vec3(0.080, 0.078, 0.075) * (0.82 + 0.36 * drift) * (1.0 + 0.12 * grain);
			float fpx = fwidth(p.x) + fwidth(p.y);
			float st1 = hash12(floor(p * 9.0));
			float st2 = hash12(floor(p * 23.0) + 5.0);
			float agg = (st1 - 0.5) * (1.0 - smoothstep(0.03, 0.12, fpx)) + (st2 - 0.5) * 0.7 * (1.0 - smoothstep(0.01, 0.05, fpx));
			agg *= pbr_on ? 0.26 : 1.0;  // Subtle grain under the photo's finer aggregate.
			albedo *= 1.0 + 0.32 * agg;
			rough = 0.86 - 0.08 * agg;
			float sa = street_age(p);
			// Broken surfacing, where water has widened existing cracks.
			float cn = vnoise(p * 0.45 + vnoise(p * 0.11) * 2.5);
			// (Hairlines: as a line shrinks below a pixel it fades instead of
			// widening – widened with distance they read as big dark loops.)
			float cfw = fwidth(cn);
			float crack = (1.0 - smoothstep(0.0, 0.01 + cfw, abs(cn - 0.5))) * (0.01 / (0.01 + cfw))
				* smoothstep(0.55, 0.75, vnoise(p * 0.035 + 7.0));
			albedo *= 1.0 - 0.3 * crack * sa * near;
			if (on) {
				// Smooth blend into junction boxes so tyre wear/gutter never
				// cut a hard polygonal seam across intersections (Westbank fix).
				// Inside intersections (other <= 0), keep continuous cross-traffic
				// wear and pooling so junctions match straight carriageways seamlessly.
				float j_smooth = smoothstep(-0.6, 2.6, other);
				float j_in = 1.0 - j_smooth;
				float across = rf.x;
				float avenue = rf.y < 0.0 ? 1.0 : 0.0;
				// rf.z = metres along the road (mod 64) + a roundabout flag: +64 or
				// +128 = on a ring (+64: the + side of its centre line is the
				// island side) or on an arm meeting one (+64: the lanes entering
				// the ring are on the + side) – see CityRoads._sample.
				float zf = floor(rf.z / 64.0);
				float along = rf.z - zf * 64.0;
				float flag_side = zf < 1.5 ? 1.0 : -1.0;
				float arm = (1.0 - ring) * step(0.5, zf);
				float from_j = other;               // metres past the junction mouth
				// Tyre tracks: two polished bands per 3.5 m lane, transitioning
				// smoothly into broad cross-traffic polish inside junctions.
				float lane_d = abs(fract(a / 3.5) - 0.5) * 3.5;
				float tracks = band(lane_d - 0.85, 0.32, 0.3) * step(0.9, hw - a) * mix(0.6, 1.0, near) * j_smooth;
				float j_wear = j_in * (0.48 + 0.52 * vnoise(p * 0.16 + 9.0)) * mix(0.65, 1.0, near);
				float polish = max(tracks, j_wear * 0.85);
				// Tyre-polished: darker, smoother, a little oil (a sun sheen runs
				// along the lanes like on a real road).
				albedo *= 1.0 - 0.16 * polish;
				rough -= 0.11 * polish;
				wheel_tracks = polish;
				// Subtle rubber/oil darkening inside intersections matching queued lanes.
				float j_oil = j_in * smoothstep(0.45, 0.82, vnoise(p * 0.42 + 13.0) * 0.6 + n * 0.4) * near;
				albedo *= 1.0 - j_oil * (0.14 + 0.18 * sa);
				rough -= j_oil * 0.10;
				// The wheel paths stay relatively clean. Sediment collects
				// beside the kerb and thickens where runoff reaches the drains.
				float kerb_in = hw - a;
				float gutter_fade = smoothstep(0.5, 3.5, other);
				float gutter = (1.0 - smoothstep(0.07, 0.77 + 0.52 * n, kerb_in)) * gutter_fade;
				float silt = gutter * (0.25 + 0.75 * smoothstep(0.25, 0.79, n));
				float grit = (0.69 + 0.31 * st1) * (1.0 - smoothstep(0.045, 0.23, fpx));
				albedo = mix(albedo, albedo * vec3(0.52, 0.48, 0.43), silt * (0.36 + 0.48 * sa));
				albedo = mix(albedo, vec3(0.092, 0.080, 0.066), gutter * grit * (0.08 + 0.18 * sa));
				shoulder_depression = band(a - (hw - 0.75), 0.67, max(0.18, aa))
					* smoothstep(0.0, 4.0, from_j)
					+ j_in * 0.55 * vnoise(p * 0.14 + 23.0);
			if (other > 0.0) {
				float drain_along = fract(along / 16.0 + 0.5) * 16.0 - 8.0;
				float grate = band(drain_along, 0.45, aa) * band(kerb_in - 0.45, 0.25, aa);
				float drain_runoff = (1.0 - smoothstep(0.06, 1.0, abs(drain_along) * 0.46 + abs(kerb_in - 0.24) * 0.56));
				albedo *= 1.0 - 0.27 * drain_runoff * (0.45 + 0.55 * sa) * near;
				float slot_gap = abs(fract(drain_along / 0.12) - 0.5);
				float slots = (1.0 - smoothstep(0.13, 0.26, slot_gap)) * (1.0 - smoothstep(0.025, 0.075, aa));
				albedo = mix(albedo, mix(vec3(0.10, 0.095, 0.085), vec3(0.024), slots), grate * near);
				// Asphalt trenches follow a lane instead of a world-axis grid.
				// Each segment has its own length, width and tar seam.
				if (near > 0.02 && kerb_in > 0.47 && from_j > 4.5) {
					float section = floor(along / 8.0);
					float job = hash12(vec2(section + sign(across) * 18.0, hw * 2.31));
					float run = fract(along / 8.0) * 8.0 - 4.0;
					float length_m = mix(1.2, 3.1, fract(job * 13.1));
					float shoulder = mix(0.92, min(hw - 0.28, 2.65), fract(job * 7.7));
					float half_width = mix(0.38, 0.74, fract(job * 19.0));
					float joint = max(abs(run) - length_m, abs(kerb_in - shoulder) - half_width);
					joint += (n - 0.5) * 0.13;
					float core = 1.0 - smoothstep(-aa - 0.04, aa + 0.08, joint);
					float bead = (1.0 - smoothstep(0.025, 0.065 + aa, abs(joint))) * (0.07 / (0.07 + aa));
					float repair = step(0.86 - sa * 0.44, job) * near;
					albedo *= 1.0 - repair * (core * (0.14 + 0.16 * sa) + bead * 0.19);
					rough = mix(rough, 0.72, repair * core * 0.5);
				}
				// Older oil marks concentrate down the lane centre. The
				// buildup gets heavier where cars slow for a junction.
				float queued = (1.0 - smoothstep(15.0, 36.0, from_j)) * j_aligned;
				float oil = smoothstep(0.52, 0.81, vnoise(p * 0.78 + 13.0) * 0.64 + n * 0.36);
				oil *= (1.0 - smoothstep(0.22, 0.69, lane_d)) * mix(0.49, 1.0, queued);
				albedo *= 1.0 - oil * (0.21 + 0.26 * sa) * near;
				rough -= oil * 0.14 * near;
				// Manholes in the lanes now and then.
				float cell = floor(along / 32.0);
				float mh_on = step(0.55, hash12(vec2(cell, hw + sign(across))));
				vec2 mh = vec2(fract(along / 32.0) * 32.0 - 16.0, a - min(1.9, hw * 0.5));
				float mh_r = length(mh);
				albedo *= 1.0 - 0.25 * band(mh_r, 0.38, aa) * mh_on * near;
				albedo *= 1.0 - 0.35 * band(mh_r - 0.38, 0.04, aa) * mh_on * near;
				// Paint: centre line (double yellow on boulevards, dashed white on
				// streets), zebra crossings and stop lines at every junction mouth.
				vec3 white = vec3(0.69, 0.67, 0.61);
				vec3 yellow = vec3(0.72, 0.52, 0.14);
				float wear = 0.81 + 0.19 * vnoise(p * 1.7);
				// Faded paint on older streets: it greys and breaks up.
				wear *= mix(1.0, 0.55 + 0.45 * vnoise(p * 0.9 + 3.0), sa);
				// One standard everywhere (traffic keeps right): boulevards a
				// double yellow centre line, a dashed divider between their two
				// lanes each way and a solid edge line 2.5 m off the kerb;
				// streets a dashed yellow centre line; every junction mouth a zebra
				// and a stop line; roundabouts give way to the ring (below). Paint
				// stops where the road meets another (from_j < the mouth's setback)
				// and never runs through a junction box (other < 0).
				float lines_from = arm > 0.5 ? 10.0 : (avenue > 0.5 ? 6.0 : 5.6);
				// (Yellow parts opposing traffic – solid double on boulevards,
				// dashed on streets; white runs with it: a ring's lane divider,
				// lane dividers, edge lines, stop lines. Dashes 3 m in every 9 m,
				// as on Skyport.)
				float centre = avenue > 0.5 && ring < 0.5
					? band(a - 0.22, 0.07, aa) * step(lines_from, from_j)
					: band(across, 0.07, aa) * step(lines_from, from_j) * step(fract(along / 9.0), 0.333);
				albedo = mix(albedo, (ring < 0.5 ? yellow : white) * wear, centre);
				float divider = avenue * (1.0 - ring) * step(10.0, hw) * band(a - 5.1, 0.07, aa) * step(lines_from, from_j)
					* step(fract(along / 9.0), 0.333);
				float edge = avenue * (1.0 - ring) * band(a - (hw - 2.5), 0.07, aa) * step(lines_from, from_j);
				albedo = mix(albedo, white * wear, max(divider, edge));
				// Lane arrows on the boulevards' approaches, pointing at the
				// junction, in the lanes heading for it (keep right: the + side
				// travels with 'along'). Which way the junction lies comes from
				// how from_j changes along the road (screen derivatives; the
				// mod-64 wrap of 'along' is skipped).
				float j_ahead = -sign(fj_cos) * step(0.5, j_aligned);   // + : the junction is towards +along
				float arr_from = lines_from + 3.0;
				float arr_u = arr_from + 5.0 - from_j;          // 0 at the tail, 5 at the head
				float lane_c = a < 5.1 ? 2.66 : 5.1 + (hw - 2.5 - 5.1) * 0.5;
				float arr_v = abs(a - lane_c);
				float shaft = step(0.0, arr_u) * step(arr_u, 3.2) * step(arr_v, 0.15);
				float head = step(3.2, arr_u) * step(arr_u, 5.0) * step(arr_v, 0.62 * (5.0 - arr_u) / 1.8);
				float arrow = avenue * (1.0 - ring) * max(shaft, head) * step(0.5, j_ahead * sign(across)) * near;
				albedo = mix(albedo, white * wear, arrow);
				// Crossings: at the mouth (1–4 m), or set back one car length on
				// a roundabout's arms (5.5–8.5 m) behind its give-way line.
				float z_lo = arm > 0.5 ? 5.5 : 1.0;
				float zebra_u = fract((across + hw - 1.5) / 1.2);
				float zebra = band(zebra_u - 0.5, 0.25, aa / 1.2) * step(from_j, z_lo + 3.0) * step(z_lo, from_j)
					* step(a, hw - 1.0);
				float stop = band(from_j - 4.8, 0.15, aa) * step(0.3, a) * step(a, hw - 0.3) * (1.0 - arm);
				// Roundabout arms: a double dashed give-way line across the lanes
				// entering the ring and a hatched ghost island between the entry
				// and exit lanes up to the crossing.
				float entry = arm * step(0.0, across * flag_side) * step(1.4, a) * step(a, hw - 0.3);
				float giveway = entry * max(band(from_j - 0.45, 0.15, aa), band(from_j - 1.05, 0.15, aa))
					* step(fract(a / 1.0), 0.6);
				float ghost = arm * step(0.3, from_j) * step(from_j, z_lo - 0.7) * step(a, 1.25)
					* max(band(a - 1.15, 0.07, aa), band(fract((along + a) / 1.4) - 0.5, 0.12, aa / 1.4));
				// (Only where the junction is ahead: round a corner of a
				// multi-road junction the from_j contour bent them into Ls.)
				zebra *= (1.0 - ring) * j_aligned;
				stop *= (1.0 - ring) * j_aligned;
				giveway *= j_aligned;
				ghost *= j_aligned;
				albedo = mix(albedo, white * wear, max(max(zebra, stop), max(giveway, ghost)));
				// The ring: a dashed lane divider (the centre line above), an edge
				// line along the outer kerb broken at every entry, and a truck
				// apron of granite setts round the island behind a white line.
				float ring_in = ring * step(0.0, across * flag_side);
				float ring_edge = ring * (1.0 - ring_in) * band(a - (hw - 0.45), 0.07, aa) * step(1.5, from_j);
				float apron = ring_in * step(hw - 3.0, a);
				vec2 sett = fract(p / 0.24);
				vec3 setts = vec3(0.47, 0.43, 0.4) * (0.86 + 0.2 * hash12(floor(p / 0.24)))
					* (1.0 - 0.3 * max(band(sett.x, 0.06, aa / 0.24), band(sett.y, 0.06, aa / 0.24)) * near);
				albedo = mix(albedo, setts, apron);
				float apron_line = ring_in * band(a - (hw - 3.15), 0.1, aa);
				albedo = mix(albedo, white * wear, max(ring_edge, apron_line));
				// Kerbside parking on the wider side streets (CityWorld parks
				// cars 1.5 m in from the kerb on minor roads ≥ 14 m): the bay
				// edge line, broken at junctions, and a bay mark every 13.5 m.
				float bays = (1.0 - avenue) * (1.0 - ring) * (1.0 - arm) * step(6.9, hw) * step(8.0, from_j);
				float bay_edge = band(a - (hw - 2.55), 0.05, aa) * bays;
				float bay_tick = band(fract(along / 13.5) * 13.5 - 6.75, 0.05, aa) * step(hw - 2.55, a) * step(a, hw - 0.45) * bays;
				albedo = mix(albedo, white * wear, max(bay_edge, bay_tick) * 0.9);
				paint_coverage = max(max(max(centre, divider), max(edge, arrow)),
					max(max(max(zebra, stop), max(giveway, ghost)), max(max(ring_edge, apron_line), max(bay_edge, bay_tick))));
				rough = mix(rough, 0.7, max(max(centre, edge), max(max(zebra, stop), max(giveway, ring_edge))));
			}
			}
		} else if (pave) {
			c *= vec3(0.76, 0.77, 0.77);
			// Pavement the field calls carriageway (a junction box reaching over
			// a block corner at a skewed or staggered junction): paving, not a
			// slab of kerb stone – the kerb is only where the surface ends.
			if (kerb < -0.4) {
				kerb = 1.0;
			}
			if (kerb < 0.32) {
				// Kerb stones: lighter granite, 0.9 m long, the joints square
				// across the kerb (they ran diagonally whichever way it faced),
				// each stone its own tone; a darker arris along the road edge.
				float ka_along = mod(rf.z, 64.0) / 0.9;
				float j = band(fract(ka_along) - 0.5, 0.47, fwidth(ka_along) + 0.01);
				j = 1.0 - j;
				albedo = c * 1.12 * (0.95 + 0.1 * hash12(vec2(floor(ka_along), hw))) * (1.0 - 0.2 * j * near);
				albedo *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.06, kerb));
				// Worn kerbs: chipped, scuffed and darker on older streets.
				float ka = street_age(p);
				albedo *= 1.0 - 0.22 * ka * step(0.72, hash12(floor(p / 0.9) + 5.0)) * near;
				albedo *= 1.0 - 0.1 * ka * vnoise(p * 2.3);
			} else if (kerb < 3.15) {
				// Pavement flagstones by the road, each a slightly different tone.
				vec2 slab_size = vec2(0.72, 0.48);
				vec2 courses = p / slab_size;
				courses.x += mod(floor(courses.y), 2.0) * 0.5;
				vec2 f = fract(courses);
				vec2 id = floor(courses);
				vec2 seam = min(f, 1.0 - f) * slab_size;
				float joint = (1.0 - smoothstep(0.006, 0.018 + aa, min(seam.x, seam.y))) * (0.021 / (0.021 + aa));
				float grout_dark = 0.28 + 0.10 * wetness;
				albedo = c * mix(0.83, 1.02, hash12(id)) * (1.0 - grout_dark * joint * near);
				rough = mix(0.81, 0.95, hash12(id + 11.0));
				albedo *= 1.0 - 0.08 * step(0.97, hash12(id + 3.0)) * near;  // the odd stained slab
				float pa = street_age(p);
				// Chewing gum spots, drip stains and (older streets) weeds in
				// the joints and a cracked slab here and there.
				vec2 gq = floor(p / 0.3);
				float gum = step(1.0 - 0.05 * (0.3 + pa), hash12(gq + 9.0)) * (1.0 - smoothstep(0.05, 0.11, length(fract(p / 0.3) - 0.5)));
				albedo *= 1.0 - 0.3 * gum * near;
				albedo *= 1.0 - 0.12 * smoothstep(0.7, 0.9, vnoise(p * 0.5 + 21.0)) * pa * near;
				// (Clumps where joints meet, not lines along them.)
				float corner = 1.0 - smoothstep(0.06, 0.16, length(seam));
				float weeds = corner * step(1.0 - 0.35 * smoothstep(0.45, 0.85, pa), hash12(floor(p / 0.8 + 0.5) + 31.0))
					* step(0.35, hash12(floor(p * 14.0)));
				albedo = mix(albedo, vec3(0.17, 0.25, 0.1) * (0.8 + 0.4 * hash12(floor(p * 9.0))), weeds * 0.85 * near);
				float slab_crack = step(1.0 - 0.06 * pa, hash12(id + 17.0)) * (1.0 - smoothstep(0.0, 0.02 + aa, abs(f.x - f.y)));
				albedo *= 1.0 - 0.3 * slab_crack * near;
				// Tactile paving where a zebra meets the kerb: a buff strip of
				// raised blisters (the crossings stopped dead at grey slabs).
				float arm_p = (1.0 - ring) * step(1.0, floor(rf.z / 64.0));
				float z_lo_p = arm_p > 0.5 ? 5.5 : 1.0;
				float tact = step(a - hw, 1.15) * step(z_lo_p, other) * step(other, z_lo_p + 3.0);
				if (tact > 0.0) {
					vec2 bl = fract(p / 0.066) - 0.5;
					float blister = 1.0 - smoothstep(0.18, 0.3, length(bl));
					albedo = vec3(0.74, 0.62, 0.42) * (0.92 + 0.08 * vnoise(p * 2.0)) * (1.0 - 0.18 * blister * near);
					rough = 0.85;
				}
			} else {
				// Courtyards, forecourts and gaps behind the pavement: big
				// concrete slabs or warm brick paving, by area. Skip unused math.
				float zone = vnoise(p / 45.0);
				float bmix = smoothstep(0.6, 0.68, zone);
				vec3 bricks = vec3(0.0);
				if (bmix > 0.001) {
					vec3 brick = vec3(0.5, 0.41, 0.37);
					vec2 b = p * vec2(4.0, 8.0);
					b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
					vec2 bf = fract(b);
					// Mortar anti-aliased and faded out once a brick is only a few
					// pixels across (a hard step shimmered into blotchy moire
					// across big dock aprons); each brick's own tone fades the same way.
					float bfine = 1.0 - smoothstep(0.012, 0.035, aa);
					float mortar = max(band(min(bf.x, 1.0 - bf.x), 0.04, aa * 4.0), band(min(bf.y, 1.0 - bf.y), 0.06, aa * 8.0)) * bfine;
					bricks = brick * (1.0 + (0.12 * hash12(floor(b)) - 0.06) * bfine) * (0.95 - 0.16 * mortar);
					// Soldier courses: a darker band of bricks on a 9.6 m grid.
					vec2 sb = abs(fract(p / 9.6 + 0.5) - 0.5) * 9.6;
					bricks *= 1.0 - 0.16 * (1.0 - smoothstep(0.22, 0.22 + aa * 2.0, min(sb.x, sb.y)));
					bricks *= 0.94 + 0.1 * vnoise(p / 11.0);
				}
				vec3 slabs = vec3(0.0);
				if (bmix < 0.999) {
					// Big squares and promenades (2026-11-20): staggered 1.5 x 0.75 m
					// flags, each its own tone, framed by darker granite bands on a
					// 9.6 m grid and worn by foot traffic (a plain 3 m slab grid
					// read as one flat sheet of beige across a whole square).
					vec2 fq = p / vec2(1.5, 0.75);
					fq.x += 0.5 * mod(floor(fq.y), 2.0);
					vec2 ff = fract(fq);
					float fj = max(band(min(ff.x, 1.0 - ff.x), 0.012, aa / 1.5), band(min(ff.y, 1.0 - ff.y), 0.02, aa / 0.75));
					float ftone = hash12(floor(fq) + 41.0);
					float ffine = 1.0 - smoothstep(0.05, 0.16, aa);  // (no per-flag speckle far off)
					slabs = c * 0.84 * mix(0.98, 0.9 + 0.16 * ftone, ffine) * (1.0 - 0.16 * fj * ffine);
					vec2 gb = abs(fract(p / 9.6 + 0.5) - 0.5) * 9.6;           // m from a band line
					float gband = 1.0 - smoothstep(0.32, 0.32 + aa * 2.0, min(gb.x, gb.y));
					vec3 granite = vec3(0.4, 0.4, 0.42) * (0.88 + 0.14 * hash12(floor(p / 0.6) + 3.0));
					slabs = mix(slabs, granite, gband * 0.85);
					float wear = vnoise(p / 14.0) * 0.6 + vnoise(p / 3.7) * 0.4;
					slabs *= 0.93 + 0.12 * wear;
					slabs *= 1.0 - 0.1 * smoothstep(0.72, 0.9, vnoise(p * 0.35 + 7.0)) * near;  // stains
				}
				albedo = mix(slabs, bricks, bmix);
			}
			// Foot traffic cleans the middle of the pavement. Rain leaves a
			// patchy skirt of dust near the kerb, with isolated darker stains.
			// The kerbside furnishing strip and the frontage apron read as
			// separate surfaces, even on the city's broad pedestrian blocks.
			float furnishing = smoothstep(0.30, 0.43, kerb) * (1.0 - smoothstep(0.97, 1.08, kerb));
			float boundary = band(kerb - 3.11, 0.043, aa) * (1.0 - smoothstep(0.07, 0.29, aa));
			albedo *= (1.0 - 0.22 * furnishing - 0.19 * boundary);
			float foot_age = street_age(p);
			float edge_dust = (1.0 - smoothstep(0.26, 1.27, kerb)) * (0.28 + n * 0.72);
			float drip_stains = smoothstep(0.61, 0.84, n * 0.46 + vnoise(p * 0.57 + 97.0) * 0.54);
			albedo = mix(albedo, albedo * vec3(0.69, 0.63, 0.57), edge_dust * (0.34 + 0.66 * foot_age) * near);
			albedo *= 1.0 - drip_stains * (0.09 + 0.22 * foot_age) * near;
		} else if (grass) {
			float verge = 1.0 - smoothstep(0.1, 2.8, kerb + 0.9 * n);
			albedo = grass_shade(c, v_world.xz, near, (fwidth(v_world.x) + fwidth(v_world.z)) * 0.5, verge * 0.58);
			float path = band(kerb - 4.8 + 0.36 * (n - 0.5), 0.8, aa + 0.09);
			albedo = mix(albedo, vec3(0.29, 0.24, 0.17) * (0.87 + 0.23 * n), path * 0.86);
		}
	} else if (asphalt && flat_top) {
		float drift = vnoise(p * 0.022 + 31.0) * 0.6 + vnoise(p * 0.09) * 0.4;
		albedo = vec3(0.080, 0.078, 0.075) * (0.82 + 0.36 * drift);
		rough = 0.86;
	} else if (pave && flat_top) {
		vec2 f = fract(p / 1.8);
		albedo *= 1.0 - 0.1 * (step(f.x, 0.03) + step(f.y, 0.03));
	}
	if (!shore && v_up < 0.3 && COLOR.a < 0.06) {
		// Retaining walls (BuildingMesher._skirt, KIND_WALL; UV = metres along,
		// world y): coursed dressed stone instead of a flat grey slab – 0.6 m
		// courses of 1.2 m blocks, alternate courses half offset, recessed
		// joints, a little tone per block and faint rain streaks running down.
		float yy = v_world.y;
		float row = floor(yy / 0.6);
		float bx = p.x / 1.2 + 0.5 * mod(row, 2.0);
		vec2 blk = vec2(floor(bx), row);
		float tone = hash12(blk + 7.0);
		float jx = abs(fract(bx) - 0.5) * 1.2;          // m from the block's centre (along)
		float jy = abs(fract(yy / 0.6) - 0.5) * 0.6;    // (up)
		float joint = max(band(jx - 0.6, 0.025, aa), band(jy - 0.3, 0.022, aa)) * near;
		albedo = c * (0.9 + 0.16 * tone) * (0.93 + 0.1 * vnoise(vec2(p.x, yy) * 1.7));
		albedo *= 1.0 - 0.3 * joint;
		float streak = smoothstep(0.55, 0.9, vnoise(vec2(p.x * 1.8, yy * 0.08))) * 0.12;
		albedo *= 1.0 - streak;
		rough = 0.88;
	}
	float puddle = 0.0;
	float surface_wet = 0.0;
	if (wetness > 0.001 && !shore && flat_top && (asphalt || pave)) {
		// Porous asphalt darkens before any standing water forms. A road
		// crown drains toward its edges; wheel tracks break up the water.
		surface_wet = wetness * (asphalt ? 1.0 : 0.72);
		// Allow wet pooling across Westbank's gentle hills & sloped junctions
		// while still draining steep embankments (> ~22 deg).
		float flatness = smoothstep(0.925, 0.985, normalize(v_wn).y);
		float basin = n * 0.18 + vnoise(p * vec2(0.21, 0.18) + 46.0) * 0.62;
		basin += 0.32 * shoulder_depression - 0.11 * wheel_tracks;
		float threshold = mix(0.83, 0.58, surface_wet);
		puddle = smoothstep(threshold, threshold + max(0.085, aa * 0.14), basin)
			* flatness * smoothstep(0.24, 0.86, surface_wet);
		puddle *= 1.0 - smoothstep(115.0, 250.0, camera_distance);
		albedo *= (1.0 - (asphalt ? 0.24 : 0.12) * surface_wet) * (1.0 - 0.025 * puddle);
		rough = mix(rough, asphalt ? 0.36 : 0.51, surface_wet);
		rough = mix(rough, 0.10, puddle);
	} else if (!shore && flat_top && grass) {
		albedo *= 1.0 - wetness * 0.11;
	}
	// Photographic detail (2026-11-21): real asphalt / paving up close.
	if (pbr_on && !shore && flat_top && (asphalt || pave)) {
		float kd = pbr_fade(camera_distance);
		vec4 d = asphalt ? texture(asph_tex, p / 1.5) : texture(pave_tex, p / 1.2);
		float substrate = kd * (1.0 - 0.75 * paint_coverage);
		albedo *= mix(1.0, d.r * 2.0, (asphalt ? 0.86 : 0.73) * substrate);
		rough = mix(rough, d.a, 0.48 * substrate * (1.0 - surface_wet));
		// Water fills the rough aggregate. Residual normal variation comes
		// from the stone sticking out around shallow puddle edges.
		vec3 nw = pbr_flat_normal(d, normalize(v_wn),
			(asphalt ? 0.79 : 0.57) * substrate * (1.0 - 0.86 * puddle));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
	// Low, diffuse city-sky bounce fills the gaps between streetlamps.
	// Limit it to road tops so vegetation, retaining walls and sand stay dark.
	if (asphalt && has_streets && flat_top && !shore) {
		EMISSION = albedo * vec3(0.13, 0.16, 0.20) * night;
		if (puddle > 0.02) {
			// Water sheets reflect the sky along the local road grade.
			// Only the shallow, resolved foreground picks up rain ripples.
			vec3 plane_normal = normalize(v_wn);
			vec3 to_eye = normalize(CAMERA_POSITION_WORLD - v_world);
			float facing = clamp(dot(plane_normal, to_eye), 0.0, 1.0);
			float grazing = (1.0 - facing) * (1.0 - facing);
			vec3 reflected = reflect(-to_eye, plane_normal);
			float ripple = 1.0;
			if (camera_distance < 19.0 && aa < 0.12) {
				float rip = sin(dot(p, vec2(11.0, 8.3)) + TIME * 9.0 + n * 9.0);
				ripple += rip * 0.11 * (1.0 - smoothstep(7.0, 19.0, camera_distance)) * (1.0 - smoothstep(0.025, 0.12, aa));
			}
			vec3 rain_sky = mix(sky_horizon * 0.18, max(sky_horizon * 0.33, vec3(0.040, 0.047, 0.060)), night);
			float hemisphere = mix(0.42, 1.0, smoothstep(-0.04, 0.22, reflected.y));
			EMISSION += rain_sky * puddle * grazing * hemisphere * ripple;
		}
		if (surface_wet > 0.18 && night > 0.24 && camera_distance < 55.0) {
			vec3 glint = vec3(0.0);
			for (int i = 0; i < 4; i++) {
				vec4 lamp = wet_road_lamps[i];
				vec3 light_colour = mix(vec3(1.0, 0.61, 0.29), vec3(0.78, 0.87, 1.0), lamp.w);
				glint += light_colour * wet_lamp_reflection(lamp, v_world, CAMERA_POSITION_WORLD, puddle, n);
			}
			float coat = smoothstep(0.18, 0.9, surface_wet);
			float texture_breakup = mix(0.23 + 0.75 * n, 1.0, puddle);
			float fade = 1.0 - smoothstep(32.0, 55.0, camera_distance);
			EMISSION += min(glint, vec3(1.25)) * coat * fade
				* texture_breakup * (0.08 + 0.28 * puddle) * smoothstep(0.24, 0.7, night);
		}
	} else if (pave && has_streets && flat_top && !shore) {
		// Subtle warm pavement light spill near building frontages at night,
		// modulated by world noise so it reads like lit shop windows/entrances,
		// plus crisp wet puddle reflections of shopfront warmth and sky.
		if (night > 0.08 && kerb_dist > 2.4 && camera_distance < 180.0) {
			float frontage = smoothstep(2.4, 4.1, kerb_dist) * (1.0 - smoothstep(6.8, 12.5, kerb_dist));
			float win_pool = smoothstep(0.30, 0.74, vnoise(p * 0.19 + 19.3) * 0.65 + vnoise(p * 0.52 - 7.1) * 0.35);
			vec3 shop_warm = mix(vec3(1.0, 0.73, 0.42), vec3(0.96, 0.86, 0.68), vnoise(p * 0.07 + 5.0));
			float dist_fade = 1.0 - smoothstep(90.0, 180.0, camera_distance);
			float night_k = smoothstep(0.08, 0.65, night);
			EMISSION += albedo * shop_warm * frontage * win_pool * night_k * dist_fade * 0.30;
			if (surface_wet > 0.12 || puddle > 0.02) {
				vec3 plane_normal = normalize(v_wn);
				vec3 to_eye = normalize(CAMERA_POSITION_WORLD - v_world);
				float facing = clamp(dot(plane_normal, to_eye), 0.0, 1.0);
				float grazing = (1.0 - facing) * (1.0 - facing);
				float wet_boost = (0.05 * surface_wet + 0.26 * puddle) * (0.45 + 0.55 * grazing);
				EMISSION += shop_warm * frontage * win_pool * wet_boost * night_k * dist_fade;
			}
		}
		if (puddle > 0.02) {
			vec3 plane_normal = normalize(v_wn);
			vec3 to_eye = normalize(CAMERA_POSITION_WORLD - v_world);
			float facing = clamp(dot(plane_normal, to_eye), 0.0, 1.0);
			float grazing = (1.0 - facing) * (1.0 - facing);
			vec3 reflected = reflect(-to_eye, plane_normal);
			vec3 rain_sky = mix(sky_horizon * 0.16, max(sky_horizon * 0.28, vec3(0.036, 0.042, 0.054)), night);
			float hemisphere = mix(0.42, 1.0, smoothstep(-0.04, 0.22, reflected.y));
			EMISSION += rain_sky * puddle * grazing * hemisphere * 0.75;
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.12, 1.0);
	SPECULAR = 0.25 + 0.18 * surface_wet + 0.33 * puddle + 0.09 * wheel_tracks;
}
