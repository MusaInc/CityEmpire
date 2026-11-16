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

global uniform float wetness;
global uniform float night;
uniform float strip_w = 20.0;   // (per-strip half widths come in UV2.x)

varying flat float v_kind;
varying vec3 v_world;
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

void vertex() {
	v_kind = floor(COLOR.a * 8.0);   // (kinds stored as (k + 0.5) / 8: an alpha of 0 is dropped)
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	} else if (v_kind == 1.0) {
		albedo = grass_shade(c, p, near, (fwidth(p.x) + fwidth(p.y)) * 0.5);
		rough = 0.97;
	} else if (v_kind == 2.0 || v_kind == 7.0) {
		albedo = c * tone;
		// Centre line, lane dashes, edge lines.
		float lanes = floor(hw / 3.5 + 0.01);
		float centre = band(uv.x, 0.1, aa) * step(fract(uv.y / 9.0), 0.6);
		float edge = band(abs(uv.x) - (hw - 0.6), 0.08, aa);
		float dash = 0.0;
		if (lanes >= 2.0) {
			dash = band(abs(uv.x) - 3.5, 0.07, aa) * step(fract(uv.y / 8.0), 0.35);
		}
		albedo = mix(albedo, white, max(edge, dash) * 0.95);
		albedo = mix(albedo, v_kind == 7.0 ? white : yellow, centre * 0.95);
		float tracks = band(abs(fract(abs(uv.x) / 3.5) - 0.5) * 3.5 - 0.9, 0.3, 0.2) * near;
		albedo *= 1.0 - 0.06 * tracks;
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
	if (UV2.y < -0.5) {
		// Shore (SkyportIsland._shore_bands): sand, rock or quay concrete by
		// colour. Sand: fine grain, ripples and a tide line; rock: boulders
		// (cells), dark gaps, weed and wet below the waterline.
		float y = v_world.y;
		float wet = 1.0 - smoothstep(-0.2, 0.9, y);
		if (c.r > c.b + 0.1) {
			float rip = sin(p.x * 1.7 + p.y * 1.1 + vnoise(p * 0.3) * 4.0) * 0.5 + 0.5;
			albedo = c * (0.9 + 0.12 * vnoise(p * 2.3) * near + 0.05 * rip * near);
			albedo *= 1.0 - 0.12 * smoothstep(0.02, 0.0, abs(y - 0.45));   // tide line
			albedo = mix(albedo, albedo * 0.62, wet);
			rough = mix(0.95, 0.4, wet);
		} else if (c.r < 0.2) {
			vec2 cell = floor(p / 1.6 + vec2(0.0, floor(y * 0.6)));
			float hb = hash12(cell);
			vec2 fc = fract(p / 1.6) - 0.5;
			float gap = smoothstep(0.32, 0.5, max(abs(fc.x), abs(fc.y)));
			albedo = c * (0.75 + 0.5 * hb) * (1.0 - 0.45 * gap * near);
			albedo = mix(albedo, vec3(0.12, 0.16, 0.1), wet * 0.6 * step(0.4, vnoise(p * 0.8)));
			albedo = mix(albedo, albedo * 0.6, wet);
			rough = mix(0.9, 0.5, wet);
		} else {
			albedo = c * tone * (1.0 - 0.3 * wet);
			albedo = mix(albedo, vec3(0.14, 0.17, 0.12), wet * 0.7);
		}
	}
	ALBEDO = albedo * (1.0 - 0.22 * wetness);
	ROUGHNESS = mix(rough, 0.35, wetness * 0.7);
}
