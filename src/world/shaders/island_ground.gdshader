// Skyport Island surfaces in one material (SkyportIsland): the kind of
// surface in COLOR.a (×8), metres in UV (x across from the centreline for
// strips, y along; world x/z for areas). No textures.
//   0 pavement / plaza slabs     1 grass          2 road (lane markings)
//   3 runway (threshold piano keys, centreline, edge lines, touchdown bars)
//   4 taxiway (yellow centreline, edge lines)    5 apron / yard concrete
//   6 helipad (H in a circle)    7 bridge deck road (as 2, no kerb wear)
shader_type spatial;
render_mode diffuse_burley;
#include "res://src/world/shaders/grass.gdshaderinc"
#include "res://src/world/shaders/rock.gdshaderinc"

global uniform float wetness;
global uniform float night;
uniform sampler2D asph_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D pave_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool pbr_on = false;
uniform bool skyport_grass = false;
uniform vec3 airfield_edge = vec3(1.0, 0.0, 0.0);
#include "res://src/world/shaders/pbr_detail.gdshaderinc"
uniform float strip_w = 20.0;   // (per-strip half widths come in UV2.x)

varying flat float v_kind;
varying vec3 v_world;
varying vec3 v_wn;
varying float v_dist;

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

float band(float d, float h, float aa) {
	return 1.0 - smoothstep(h - aa, h + aa, abs(d));
}

// Shore surfaces: sand, rock or quay concrete, chosen by colour c.
vec3 shore_look(vec3 c, vec2 p, float y, float fp, float near, float tone, vec3 wp, vec3 wn, inout float rough) {
	vec3 albedo = c;
	float wet = 1.0 - smoothstep(-0.2, 0.9, y);
	if (c.r > c.b + 0.1) {
		// (Wet only in the swash band: under the water the sea's own tint
		// does the darkening – doubled up it ringed every beach brown.)
		float under = 1.0 - smoothstep(-1.4, -0.5, y);
		wet *= 1.0 - under;
		float rip = sin(p.x * 1.7 + p.y * 1.1 + vnoise(p * 0.3) * 4.0) * 0.5 + 0.5;
		albedo = c * (0.9 + 0.12 * vnoise(p * 2.3) * near + 0.05 * rip * near);
		albedo *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.02, abs(y - 0.45)));   // tide line
		// Wrack line: a broken band of dried weed and shells above the tide.
		float wrack = band(y - 1.25 - 0.25 * vnoise(p * 0.07), 0.12, 0.08) * smoothstep(0.35, 0.6, vnoise(p * 0.9 + 4.0));
		albedo = mix(albedo, vec3(0.2, 0.17, 0.11), wrack * 0.55 * near);
		albedo = mix(albedo, albedo * 0.62, wet);
		albedo *= mix(1.0, 0.7, under);   // (under water: a little darker, the sea tints the rest)
		rough = mix(0.95, 0.4, max(wet, under));
		// The top of the beach grows into the island's turf through dune
		// grass along a ragged line (Skyport's beaches met the lawn on a
		// hard mesh edge: a pasted-on sand blob from the air).
		float rag = vnoise(p * 0.11) * 0.9 + vnoise(p * 0.5) * 0.35 * near;
		float topk = smoothstep(3.3, 4.35, y + rag - 0.45);
		if (topk > 0.0) {
			vec3 turf = grass_shade(pow(vec3(0.33, 0.47, 0.26), vec3(2.2)), p, near, fp * 0.5, 2.0);
			vec3 marram = mix(turf, vec3(0.42, 0.42, 0.24), 0.55) * (0.85 + 0.3 * vnoise(p * 1.3));
			float tuft = smoothstep(0.42, 0.5, vnoise(p * 0.8 + 3.0) + topk * 0.25);
			albedo = mix(albedo, mix(albedo * 0.96, marram, tuft), smoothstep(0.0, 0.6, topk));
			albedo = mix(albedo, turf, smoothstep(0.7, 1.0, topk));
			rough = mix(rough, 0.97, topk);
		}
	} else if (c.r < 0.2) {
		// Natural rock: rock.gdshaderinc (the cities' cliffs and armour share it).
		albedo = rock_look(c * 1.55, wp, wn, fp, near, rough);
	} else {
		albedo = c * tone * (1.0 - 0.3 * wet);
		if (abs(wn.y) < 0.6) {
			// Quay wall faces: cast-concrete panels (6 m joints, 1.2 m pour
			// lines), rust and rain streaks from the coping, a pale salt band
			// and dark weed at the waterline (they were one flat dark slab).
			vec2 tg = normalize(vec2(-wn.z, wn.x) + vec2(1e-4, 0.0));
			float s = dot(wp.xz, tg);
			float joint = band(fract(s / 6.0 + 0.5) - 0.5, 0.012, fp / 6.0 + 0.002);
			float pour = band(fract(wp.y / 1.2) - 0.5, 0.02, fp / 1.2 + 0.004) * 0.5;
			float panel = hash12(vec2(floor(s / 6.0), 3.0));
			albedo *= (0.9 + 0.16 * panel) * (1.0 - 0.3 * joint - 0.12 * pour);
			float streak = smoothstep(0.55, 0.85, vnoise(vec2(s * 1.7, wp.y * 0.08))) * smoothstep(-0.5, 3.0, y);
			albedo = mix(albedo, albedo * vec3(0.75, 0.62, 0.5), streak * 0.5);
			albedo = mix(albedo, albedo * 1.25 + 0.04, band(y - 1.3, 0.35, 0.3) * 0.5);   // salt bloom
			albedo = mix(albedo, vec3(0.05, 0.08, 0.05), (1.0 - smoothstep(0.2, 1.0, y + 0.3 * vnoise(vec2(s * 0.8, 1.0)))) * 0.8);
			albedo = mix(albedo, vec3(0.62, 0.6, 0.56), smoothstep(4.35, 4.5, y));   // coping
		} else {
			albedo = mix(albedo, vec3(0.14, 0.17, 0.12), wet * 0.7);
		}
	}
	return albedo;
}

void vertex() {
	v_kind = floor(COLOR.a * 8.0);   // (kinds stored as (k + 0.5) / 8: an alpha of 0 is dropped)
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 uv = UV;
	float hw = UV2.x;          // strip half-width (m)
	float near = 1.0 - smoothstep(80.0, 260.0, v_dist);
	float aa = max(fwidth(uv.x) + fwidth(uv.y), 0.004) * 0.6;
	vec3 c = pow(COLOR.rgb, vec3(2.2));   // (vertex colours are sRGB)
	vec3 albedo = c;
	float rough = 0.9;
	float sheen = 0.0;
	vec3 pbr_n = vec3(0.0);
	vec3 white = vec3(0.78, 0.78, 0.74);
	vec3 yellow = vec3(0.78, 0.52, 0.06);
	float tone = 0.9 + 0.12 * vnoise(p / 30.0) + 0.06 * vnoise(p * 0.7) * near;
	if (v_kind == 0.0) {
		vec2 f = fract(p / 1.5);
		float joint = max(band(f.x, 0.03, aa / 1.5), band(f.y, 0.03, aa / 1.5));
		albedo = c * tone * (0.94 + 0.08 * hash12(floor(p / 1.5))) * (1.0 - 0.12 * joint * near);
		// Darker granite bands every 12 m (paving laid in bays), weathered
		// patches and drip stains, so large paved areas read as built.
		vec2 g = abs(fract(p / 12.0 + 0.5) - 0.5) * 12.0;
		float granite = 1.0 - smoothstep(0.2, 0.2 + aa * 2.0, min(g.x, g.y));
		albedo = mix(albedo, c * vec3(0.62, 0.62, 0.64), granite * 0.8);
		albedo *= 1.0 - 0.1 * smoothstep(0.6, 0.85, vnoise(p * 0.12 + 5.0));
		albedo *= 1.0 - 0.08 * smoothstep(0.7, 0.9, vnoise(p * 0.7 + 11.0)) * near;
		if (pbr_on) {
			float kd = pbr_fade(v_dist);
			vec4 detail = texture(pave_tex, p / 1.2);
			albedo *= mix(1.0, 2.0 * detail.r, kd * 0.48);
			rough = mix(0.83, detail.a, 0.45 * kd);
			pbr_n = pbr_flat_normal(detail, normalize(v_wn), 0.65 * kd);
		}
	} else if (v_kind == 1.0) {
		float terrain = skyport_grass ? smoothstep(-28.0, 82.0, dot(airfield_edge.xy, p) + airfield_edge.z) : 2.0;
		albedo = grass_shade(c, p, near, (fwidth(p.x) + fwidth(p.y)) * 0.5, terrain);
		rough = 0.97;
		if (hw < -0.5) {
			// Landform tops near a beach (Landforms: UV2.x = -(metres to the
			// beach + 1)): dry sand, then dune grass in tufts, then turf,
			// along a ragged line – not a hard edge.
			float d = -hw - 1.0;
			float rag = vnoise(p * 0.09) * 6.0 + vnoise(p * 0.45) * 2.0 * near;
			float sandk = 1.0 - smoothstep(3.0, 8.0, d + rag - 3.0);
			float dune = (1.0 - smoothstep(7.0, 14.0, d + rag - 3.0)) * (1.0 - sandk);
			vec3 sand = vec3(0.6, 0.51, 0.33) * (0.92 + 0.12 * vnoise(p * 1.9));
			vec3 marram = mix(albedo, vec3(0.42, 0.42, 0.24), 0.55) * (0.85 + 0.3 * vnoise(p * 1.3));
			albedo = mix(albedo, mix(sand, marram, step(0.45, vnoise(p * 0.8))), dune);
			albedo = mix(albedo, sand, sandk);
		}
	} else if (v_kind == 2.0 || v_kind == 7.0) {
		// Asphalt as the cities' (ground.gdshader, 2026-11-21): darker, stone
		// aggregate faded by pixel size, tyre-polished tracks with a sheen.
		float fpx = fwidth(p.x) + fwidth(p.y);
		float agg = (hash12(floor(p * 9.0)) - 0.5) * (1.0 - smoothstep(0.03, 0.12, fpx))
			+ (hash12(floor(p * 23.0) + 5.0) - 0.5) * 0.7 * (1.0 - smoothstep(0.01, 0.05, fpx));
		agg *= pbr_on ? 0.0 : 1.0;
		albedo = c * tone * 0.66 * (1.0 + 0.32 * agg);
		rough = 0.86 - 0.08 * agg;
		if (pbr_on) {
			float kd = pbr_fade(v_dist);
			vec4 d = texture(asph_tex, p / 1.5);
			albedo *= mix(1.0, d.r * 2.0, 0.85 * kd);
			rough = mix(rough, d.a, 0.55 * kd * (1.0 - wetness));
			pbr_n = pbr_flat_normal(d, normalize(v_wn), 0.9 * kd);
		}
		// Centre line, lane dashes, edge lines.
		// The same standard as the cities (ground.gdshader): yellow parts
		// opposing traffic – a double solid line on multi-lane roads, dashed
		// (3 m in 9 m) on two-lane ones; white runs with it (lane dividers,
		// edge lines). Kind 7 (bridge decks) the same: they carry two-way
		// traffic (their old white centre line read as a one-way road).
		// Roads 20 m and wider (Skyport Avenue, the approaches, the bridge
		// decks) are laid out exactly like the cities' 22–26 m roads, so the
		// lines run straight on across every bridge joint: lanes divided at
		// 5.1 m (the island's traffic keeps 3.4 m off the centre: inside the
		// first lane – the old 3.5 m divider had cars driving on it), an edge
		// line 2.5 m off the kerb. Narrower roads: one lane each way, the
		// edge line clear of the traffic.
		bool wide = hw >= 10.0;
		float centre = wide
			? band(abs(uv.x) - 0.22, 0.07, aa)
			: band(uv.x, 0.08, aa) * step(fract(uv.y / 9.0), 0.333);
		float edge = band(abs(uv.x) - (wide ? hw - 2.5 : max(hw - 1.8, min(4.6, hw - 0.5))), 0.08, aa);
		float dash = 0.0;
		if (wide) {
			dash = band(abs(uv.x) - 5.1, 0.07, aa) * step(fract(uv.y / 9.0), 0.333);
		}
		albedo = mix(albedo, white, max(edge, dash) * 0.95);
		albedo = mix(albedo, yellow, centre * 0.95);
		float tracks = band(abs(fract(abs(uv.x) / 3.5) - 0.5) * 3.5 - 0.9, 0.32, 0.3) * mix(0.6, 1.0, near);
		albedo *= 1.0 - 0.16 * tracks;
		rough -= 0.3 * tracks;
		sheen = tracks;
		// Patch repairs, the odd oil stain and a darker gutter by the kerb.
		vec2 pc = floor(p / vec2(4.0, 2.6) + 7.0);
		albedo *= 1.0 - 0.08 * step(0.9, hash12(pc)) * near;
		albedo *= 1.0 - 0.15 * smoothstep(0.75, 0.88, vnoise(p * 0.55 + 3.0)) * near;
		albedo *= 1.0 - 0.18 * smoothstep(hw - 1.0, hw - 0.2, abs(uv.x));
	} else if (v_kind == 3.0) {
		albedo = c * tone * (1.0 - 0.05 * step(0.5, fract(uv.y / 40.0)));
		float len = UV2.y;
		float ends = min(uv.y, len - uv.y);
		float keys = step(6.0, ends) * step(ends, 36.0) * step(abs(uv.x), hw - 3.0)
			* band(fract(abs(uv.x) / 1.8) - 0.5, 0.28, aa / 1.8);
		float centre = band(uv.x, 0.45, aa) * step(fract(uv.y / 50.0), 0.6) * step(60.0, ends);
		float edge = band(abs(uv.x) - (hw - 1.2), 0.45, aa);
		float tdz = step(150.0, ends) * step(ends, 200.0) * step(abs(abs(uv.x) - 8.0), 4.0) * band(fract(ends / 25.0) - 0.5, 0.4, 0.02);
		float aim = step(290.0, ends) * step(ends, 340.0) * step(abs(abs(uv.x) - 9.0), 2.5);
		albedo = mix(albedo, white, max(max(keys, centre), max(edge, max(tdz, aim))) * 0.95);
		// Rubber deposits at the touchdown zones.
		albedo *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 120.0, abs(ends - 260.0))) * step(abs(uv.x), 12.0) * vnoise(p * 0.5);
		rough = 0.85;
	} else if (v_kind == 4.0) {
		albedo = c * tone;
		float centre = band(uv.x, 0.15, aa);
		float edge = band(abs(uv.x) - (hw - 0.8), 0.12, aa);
		albedo = mix(albedo, yellow, max(centre, edge) * 0.95);
	} else if (v_kind == 5.0) {
		vec2 f = fract(p / 7.5);
		float joint = max(band(f.x, 0.008, aa / 7.5), band(f.y, 0.008, aa / 7.5));
		albedo = c * tone * (0.95 + 0.06 * hash12(floor(p / 7.5))) * (1.0 - 0.18 * joint * near);
		albedo *= 1.0 - 0.15 * smoothstep(0.75, 0.9, vnoise(p * 0.25)) * near;   // oil and tyre marks
	} else if (v_kind == 6.0) {
		albedo = c * tone;
		vec2 q = uv;   // metres from the pad's centre
		float r = length(q);
		float ring = band(r - 7.0, 0.45, aa);
		float hbar = step(abs(q.y), 0.45) * step(abs(q.x), 2.6);
		float hleg = step(abs(abs(q.x) - 2.6), 0.5) * step(abs(q.y), 3.2);
		albedo = mix(albedo, white, max(ring, max(hbar, hleg)) * 0.95);
		albedo = mix(albedo, yellow, band(r - 8.6, 0.25, aa));
	}
	if ((v_kind == 0.0 || v_kind == 5.0) && hw > 2.5 && hw < 3.5) {
		// A car park (SkyportIsland areas flagged "bays", UV = island-local
		// metres): rows of 2.6 m bays from x 1965, 5 m deep either side of a
		// 7 m aisle in 17 m modules from z 59 (SkyportAirport.build_apron_kit
		// parks its cars on the same grid), white lines, oil drips mid-bay.
		float mod_z = fract((uv.y - 59.0) / 17.0) * 17.0;
		float in_bay = step(mod_z, 5.0) + step(12.0, mod_z);
		float bx = fract((uv.x - 1965.0) / 2.6) * 2.6;
		float line = band(min(bx, 2.6 - bx), 0.06, aa) * in_bay;
		float ends = band(mod_z - 5.0, 0.06, aa) + band(mod_z - 12.0, 0.06, aa);
		albedo = mix(albedo, vec3(0.86, 0.86, 0.82), clamp(max(line, ends), 0.0, 1.0) * 0.9);
		albedo *= 1.0 - 0.15 * in_bay * smoothstep(0.55, 0.85, vnoise(p * 0.6)) * near;
	}
	if (UV2.y < -0.5) {
		// Shore (SkyportIsland._shore_bands, Landforms, SeabedMesh): sand,
		// rock or quay concrete by colour. The sea floor (SeabedMesh) passes
		// its rock share in UV2.x (1 + share, +2 for the cities' darker
		// stone) and is blended between both looks: its vertex colours used
		// to mix and flip between the branches pixel by pixel – blotches.
		float sfp = fwidth(p.x) + fwidth(p.y);
		if (UV2.x > 0.5) {
			float code = UV2.x - 1.0;
			float dark = step(1.5, code);
			float rk = smoothstep(0.3, 0.8, clamp(code - 2.0 * dark, 0.0, 1.0));
			vec3 rockc = mix(pow(vec3(0.42, 0.4, 0.37), vec3(2.2)), pow(vec3(0.23, 0.225, 0.225), vec3(2.2)), dark);
			float r1 = rough;
			float r2 = rough;
			vec3 sa = shore_look(pow(vec3(0.8, 0.72, 0.55), vec3(2.2)), p, v_world.y + 1.6, sfp, near, tone, v_world, normalize(v_wn), r1);
			vec3 ro = shore_look(rockc, p, v_world.y + 1.6, sfp, near, tone, v_world, normalize(v_wn), r2);
			albedo = mix(sa, ro, rk);
			rough = mix(r1, r2, rk);
		} else {
			albedo = shore_look(c, p, v_world.y + 1.6, sfp, near, tone, v_world, normalize(v_wn), rough);
		}
	}
	if (pbr_n.y > 0.0) {
		NORMAL = normalize((VIEW_MATRIX * vec4(pbr_n, 0.0)).xyz);
	}
	ALBEDO = albedo * (1.0 - 0.22 * wetness);
	ROUGHNESS = mix(clamp(rough, 0.3, 1.0), 0.35, wetness * 0.7);
	SPECULAR = 0.5 + 0.2 * sheen;
}
