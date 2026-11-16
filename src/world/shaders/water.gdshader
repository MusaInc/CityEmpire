// Sea, strait and dock water. Still no screen-space reads (cheap on mobile):
//  * swell: ten wave trains spread round a veering wind, wavelengths with
//    no common ratios and deep-water speeds (so they never settle into a
//    grid), each rising and falling in drifting groups; gradient-noise chop
//    up close; all fade with distance so the far sea doesn't shimmer;
//  * colour: a deep blue-green body, lighter turquoise where the light comes
//    through wave crests facing the sun, darker in the troughs;
//  * reflection: the sky gradient (sky_top / sky_horizon) by Schlick fresnel,
//    emitted so it reads at any sun angle, plus a tight sun highlight and a
//    wider glitter path that sparkles on the wave facets;
//  * whitecaps on the steepest crests when it blows (rain/storm), and a pock
//    of fine ripples in the rain;
//  * night: the body goes inky and the reflection follows the dark sky;
//  * depth (a baked seabed): light is absorbed by depth, red first, so sand
//    shelves read turquoise, rock darker, channels deep blue; the bottom –
//    sand ripples or rock – shows through with a little parallax; the swell
//    calms in the shallows and a line of surf runs in to the shore; a storm
//    stirs the water up (less clear).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;

uniform vec3 deep : source_color = vec3(0.03, 0.12, 0.17);
uniform vec3 shallow : source_color = vec3(0.07, 0.34, 0.38);
// The seabed (tools/bake_seabed.gd): L = depth / seabed_max, A = how rocky
// the nearest shore is. Outside seabed_rect the sea is deep.
uniform sampler2D seabed : filter_linear, repeat_disable;
uniform vec4 seabed_rect = vec4(-2400.0, -1800.0, 4800.0, 4800.0);
uniform float seabed_max = 32.0;
uniform bool has_seabed = false;
uniform float shallow_visibility = 0.78;
uniform float clear_depth_start = 0.5;
uniform float clear_depth_end = 10.0;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
global uniform float rain;
global uniform float night;

varying vec3 v_world;

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

// Gradient noise (smooth, no value-noise blockiness), in [-1, 1]-ish.
vec2 grad2(vec2 i) {
	// (No trig: two hashes, roughly unit length – cheap on mobile.)
	return vec2(hash12(i), hash12(i + 19.19)) * 2.0 - 1.0;
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad2(i), f);
	float b = dot(grad2(i + vec2(1, 0)), f - vec2(1, 0));
	float c = dot(grad2(i + vec2(0, 1)), f - vec2(0, 1));
	float d = dot(grad2(i + vec2(1, 1)), f - vec2(1, 1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.6;
}

// One wave train: height and its slope (d/dx, d/dz).
vec3 wave(vec2 p, vec2 dir, float len, float amp, float speed) {
	float k = 6.28318 / len;
	float ph = dot(dir, p) * k - TIME * speed * k;
	float s = sin(ph);
	float c = cos(ph);
	// Sharpened crests (a cheap trochoid look): narrow peaks, wide troughs.
	float h = amp * (s * 0.5 + 0.5);
	h = h * h / amp;
	float dh = amp * k * c * (s * 0.5 + 0.5);
	return vec3(h, dir * dh);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Warp the plane a little and vary the swell's strength in broad
	// patches, so the wave trains never read as a regular grid.
	vec2 p0 = v_world.xz;
	vec2 p = p0 + vec2(vnoise(p0 * 0.018), vnoise(p0 * 0.018 + 17.3)) * 9.0;
	float patchy = 0.55 + 0.9 * vnoise(p0 * 0.009 + TIME * 0.01);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(60.0, 420.0, dist);
	float mid = 1.0 - smoothstep(250.0, 1600.0, dist);
	float blow = clamp(rain, 0.0, 1.0);
	float depth = seabed_max;
	float rocky = 1.0;
	if (has_seabed) {
		vec2 suv = (p0 - seabed_rect.xy) / seabed_rect.zw;
		if (suv.x > 0.0 && suv.y > 0.0 && suv.x < 1.0 && suv.y < 1.0) {
			vec4 sb = texture(seabed, suv);
			depth = max(sb.r * seabed_max, 0.25);
			rocky = sb.a;
		}
	}
	// Shallow water: the swell shortens and calms (and it can't be taller
	// than the water is deep).
	float calm = mix(0.2, 1.0, smoothstep(0.8, 9.0, depth));
	float sw = (1.0 + 0.8 * blow) * patchy * calm;
	// The swell: ten trains spread round a slowly veering wind (golden-angle
	// spread, so no two line up), wavelengths 41 m → 2 m in steps of ×0.74
	// (no common ratios: the trains never fall into a grid), each moving at
	// its own deep-water speed (√(gL/2π) – slower in the shallows), and each
	// rising and falling in slow-drifting groups. A train fades out once a
	// pixel covers a good part of its wavelength (no moiré from altitude).
	float fp = length(fwidth(p0)) + 0.001;
	float wind = 0.62 + 0.25 * sin(TIME * 0.011) + 0.35 * (gnoise(p0 * 0.0007) );
	vec3 w = vec3(0.0);
	float amp_sum = 0.0;
	float L = 41.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float ang = wind + (fract(fi * 0.618034) - 0.5) * mix(1.6, 2.4, fi / 9.0);
		vec2 dir = vec2(cos(ang), sin(ang));
		float c = sqrt(9.81 * L / 6.28318);
		c = min(c, sqrt(9.81 * max(depth, 0.4)));            // (shallow water slows it)
		// (Groups are 150 m+ across: the cheap value noise is smooth enough.)
		float group = 0.45 + 0.9 * vnoise(p0 * (0.004 + 0.0013 * fi) + dir * TIME * 0.02 + fi * 7.3);
		float a = L * 0.021 * sw * group * (i < 3 ? 1.0 : 0.85);
		float fade = 1.0 - smoothstep(L * 0.05, L * 0.2, fp);
		if (i >= 7) {
			fade *= near;
		}
		w += wave(p, dir, L, a, c) * fade;
		amp_sum += a * fade;
		L *= 0.74;
	}
	// Normalise the crest height for colour and foam (≈ the old 0–1.1 range).
	w.x *= 1.1 / max(amp_sum, 0.01) * min(amp_sum, 1.2);
	// Chop up close (smooth gradient noise, two octaves drifting with the
	// wind) and rain pock-marks.
	vec2 wd = vec2(cos(wind), sin(wind));
	float e = 0.3;
	vec2 q = p * 0.5 + wd * TIME * 0.35;
	vec2 q3 = p * 1.3 + vec2(-wd.y, wd.x) * TIME * 0.22 + 31.0;
	float c0 = gnoise(q) + 0.5 * gnoise(q3);
	vec2 chop = vec2(gnoise(q + vec2(e, 0.0)) + 0.5 * gnoise(q3 + vec2(e, 0.0)) - c0,
		gnoise(q + vec2(0.0, e)) + 0.5 * gnoise(q3 + vec2(0.0, e)) - c0) / e * 0.09 * (1.0 + 0.8 * blow);
	vec2 q2 = p * 2.3 - vec2(TIME * 1.4, -TIME * 1.1);
	float r0 = vnoise(q2);
	vec2 pock = vec2(vnoise(q2 + vec2(0.3, 0.0)) - r0, vnoise(q2 + vec2(0.0, 0.3)) - r0) * 0.5 * blow;
	// (Far off the swell's slopes fade more: seen from height the trains
	// interfere into a regular ripple grid.)
	vec2 slope = w.yz * mix(0.12, 1.0, mid * mid) + (chop + pock) * near * (1.0 - smoothstep(0.15, 0.6, fp));
	// (Over the shallows the surface is glassier still: no swell grid over
	// a bright sandy floor.)
	slope *= mix(0.35, 1.0, smoothstep(1.0, 10.0, depth));
	// (At grazing angles a pixel spans metres along the view: the slopes
	// alias into streaks along the horizon – soften them there.)
	float graze = normalize(CAMERA_POSITION_WORLD - v_world).y;
	slope *= mix(0.4, 1.0, smoothstep(0.04, 0.3, graze));
	// (Far off only the longest trains survive their fade and cross into a
	// diamond lattice: calm them there and let broad wind patches – cat's
	// paws and slicks – shape the reflection instead.)
	float farw = smoothstep(180.0, 800.0, dist);
	slope *= mix(1.0, 0.5, farw);
	slope += vec2(gnoise(p0 * 0.011 + wd * TIME * 0.05), gnoise(p0 * 0.011 + 17.3 - wd * TIME * 0.04)) * 0.07 * farw * (1.0 + blow);
	vec3 nw = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	vec3 view_w = normalize(CAMERA_POSITION_WORLD - v_world);
	float ndv = clamp(dot(view_w, nw), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	fres = mix(fres, 0.85, smoothstep(900.0, 3500.0, dist) * 0.6);  // far sea: mostly sky
	vec3 r = reflect(-view_w, nw);
	r.y = abs(r.y);
	vec3 sky = mix(sky_horizon, sky_top, pow(clamp(r.y, 0.0, 1.0), 0.6));

	// Body: crests the light shines through go turquoise, troughs deep.
	float crest = clamp(w.x / (1.1 * (1.0 + 0.8 * blow)), 0.0, 1.0);
	float through = clamp(dot(normalize(vec3(sun_dir.x, 0.0, sun_dir.z)), -view_w) * 0.5 + 0.5, 0.0, 1.0);
	vec3 body = mix(deep, shallow, crest * (0.45 + 0.55 * through) * (1.0 - night * 0.8));
	body *= mix(1.0, 0.25, night);
	body *= mix(vec3(1.0), vec3(0.75, 0.82, 0.85), blow);  // grey under a storm sky

	// Sun: a tight highlight and a wider glitter path on the facets.
	float sd = max(dot(r, sun_dir), 0.0);
	float day = clamp(sun_dir.y * 4.0, 0.0, 1.0) * (1.0 - night) * (1.0 - 0.85 * blow);
	float glint = pow(sd, 900.0) * 30.0 + pow(sd, 90.0) * 1.6 * (0.4 + 0.6 * clamp(gnoise(p * 1.7 + TIME * 0.8) * 0.5 + 0.5, 0.0, 1.0)) * near;
	vec3 sun_col = mix(vec3(1.0, 0.72, 0.45), vec3(1.0, 0.96, 0.88), clamp(sun_dir.y * 2.5, 0.0, 1.0));

	// Whitecaps on the steepest crests when it blows (and a few on a calm day).
	float foam = smoothstep(0.8, 0.96, crest) * smoothstep(0.55, 0.85, vnoise(p * 0.9 + TIME * 0.3)) * smoothstep(0.4, 0.8, vnoise(p0 * 0.02))
		* (0.04 + 0.96 * blow) * mid * near;
	// Surf: lines along the depth contours running in to the shore over the
	// sand shelves (rocks get a ragged wash), broken up along their length;
	// higher seas, bigger surf.
	float surf_zone = smoothstep(2.2, 0.5, depth);
	float lines = sin(depth * 7.5 + TIME * 2.2 + vnoise(p0 * 0.08) * 3.0) * 0.5 + 0.5;
	float surf = surf_zone * smoothstep(0.62, 0.92, lines) * smoothstep(0.3, 0.7, vnoise(p0 * 0.12 + vec2(TIME * 0.15, 0.0)))
		* mix(0.75, 1.0, rocky) * (0.65 + 0.6 * blow) * mid;
	foam = max(foam, surf);

	// The seabed seen through the water. Absorption per metre (red first),
	// over a path that lengthens at grazing angles; a storm stirs it up.
	vec3 kd = vec3(0.34, 0.088, 0.064) * (1.0 + 1.6 * blow);
	float path = depth * (1.0 + 1.0 / max(ndv, 0.25));
	vec3 tr = exp(-kd * path);
	// (Parallax: the bottom sits below the surface, offset along the view.)
	vec2 bp = p0 - view_w.xz / max(view_w.y, 0.25) * depth * 0.55;
	float ripple = sin(dot(bp, vec2(0.83, 0.55)) * 2.6 + vnoise(bp * 0.35) * 4.0) * 0.5 + 0.5;
	vec3 sand_c = vec3(0.86, 0.79, 0.62) * (0.86 + 0.14 * ripple) * (0.9 + 0.2 * vnoise(bp * 0.05));
	float stones = vnoise(bp * 0.45) * 0.6 + vnoise(bp * 1.7) * 0.4;
	vec3 rock_c = mix(vec3(0.16, 0.17, 0.14), vec3(0.34, 0.33, 0.27), stones) * (0.8 + 0.4 * vnoise(bp * 0.06 + 3.0));
	vec3 floor_c = mix(sand_c, rock_c, smoothstep(0.25, 0.75, rocky));
	// Caustics flicker on a shallow sunlit floor.
	float caus = pow(vnoise(bp * 0.9 + vec2(TIME * 0.4, TIME * 0.25)) * vnoise(bp * 1.3 - vec2(TIME * 0.3, 0.0)), 2.0) * 2.4;
	floor_c *= 1.0 + caus * day * exp(-depth * 0.35) * (1.0 - blow);
	floor_c *= mix(1.0, 0.12, night) * mix(1.0, 0.7, blow);
	// Far off the bottom's detail aliases: fade it to its mean.
	float fdet = 1.0 - smoothstep(0.3, 2.5, fp);
	floor_c = mix(mix(vec3(0.78, 0.72, 0.56), vec3(0.24, 0.24, 0.2), smoothstep(0.25, 0.75, rocky)) * mix(1.0, 0.12, night), floor_c, fdet);
	vec3 water_c = body;
	body = floor_c * tr + body * (vec3(1.0) - tr);

	// See-through shallows: where the baked seabed says it's shallow there
	// is real floor geometry under the surface (SeabedMesh, the beaches and
	// rock armour), so the water thins out and shows it – opaque again by
	// ~6 m, wherever the surface reflects (grazing views, fresnel), on foam
	// and glints, in a storm, at night and far off (where the painted floor
	// takes over). Its colour there is the turquoise tint the light picks
	// up through a metre or two of water, not the painted floor.
	float see = has_seabed
                ? 1.0 - smoothstep(clear_depth_start, clear_depth_end, depth)
                : 0.0;
	see *= (1.0 - fres) * (1.0 - foam) * (1.0 - clamp(glint * day, 0.0, 1.0));
	see *= (1.0 - 0.75 * blow) * (1.0 - 0.6 * night) * (1.0 - smoothstep(900.0, 1800.0, dist));
	vec3 tint = mix(shallow * vec3(1.0, 1.8, 1.62), water_c, smoothstep(1.5, 7.0, depth));
	body = mix(body, tint, see);
	ALPHA = 1.0 - see * shallow_visibility;

	ALBEDO = mix(body * (1.0 - fres), vec3(0.9), foam);
	EMISSION = (sky * fres * (1.0 - foam) * mix(1.0, 0.6, night) + sun_col * glint * day) * (1.0 - foam * 0.7);
	// (Caustics dance on the real floor too: a faint dapple in the surface.)
	EMISSION += vec3(0.9, 1.0, 0.95) * caus * day * see * exp(-depth * 0.45) * 0.06 * (1.0 - blow);
	ROUGHNESS = mix(0.06, 0.6, foam) + 0.08 * blow;
	SPECULAR = 0.25;
}
