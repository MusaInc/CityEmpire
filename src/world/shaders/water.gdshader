// Sea, strait and dock water. Still no screen-space reads (cheap on mobile):
//  * swell: four travelling sine wave trains in different directions with
//    analytic slopes (crisp, coherent waves instead of blurry noise), plus
//    two scrolling noise octaves of chop up close; all fade with distance so
//    the far sea doesn't shimmer;
//  * colour: a deep blue-green body, lighter turquoise where the light comes
//    through wave crests facing the sun, darker in the troughs;
//  * reflection: the sky gradient (sky_top / sky_horizon) by Schlick fresnel,
//    emitted so it reads at any sun angle, plus a tight sun highlight and a
//    wider glitter path that sparkles on the wave facets;
//  * whitecaps on the steepest crests when it blows (rain/storm), and a pock
//    of fine ripples in the rain;
//  * night: the body goes inky and the reflection follows the dark sky.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.03, 0.12, 0.17);
uniform vec3 shallow : source_color = vec3(0.07, 0.34, 0.38);
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
	float sw = (1.0 + 0.8 * blow) * patchy;
	vec3 w = wave(p, normalize(vec2(1.0, 0.35)), 23.0, 0.55 * sw, 2.4);
	w += wave(p, normalize(vec2(0.6, -1.0)), 13.0, 0.32 * sw, 1.9);
	w += wave(p, normalize(vec2(-0.85, 0.5)), 7.3, 0.18 * sw, 1.5);
	w += wave(p, normalize(vec2(0.2, 1.0)), 3.9, 0.09 * sw, 1.1) * near;
	// Chop up close (and rain pock-marks).
	float e = 0.35;
	vec2 q = p * 0.55 + vec2(TIME * 0.21, TIME * 0.13);
	float c0 = vnoise(q);
	vec2 chop = vec2(vnoise(q + vec2(e, 0.0)) - c0, vnoise(q + vec2(0.0, e)) - c0) / e * 0.22;
	vec2 q2 = p * 2.3 - vec2(TIME * 1.4, -TIME * 1.1);
	float r0 = vnoise(q2);
	vec2 pock = vec2(vnoise(q2 + vec2(0.3, 0.0)) - r0, vnoise(q2 + vec2(0.0, 0.3)) - r0) * 0.5 * blow;
	// (Far off the swell's slopes fade more: seen from height the trains
	// interfere into a regular ripple grid.)
	vec2 slope = w.yz * mix(0.12, 1.0, mid * mid) + (chop + pock) * near;
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
	float glint = pow(sd, 900.0) * 30.0 + pow(sd, 90.0) * 1.6 * (0.4 + 0.6 * vnoise(p * 1.7 + TIME * 0.8)) * near;
	vec3 sun_col = mix(vec3(1.0, 0.72, 0.45), vec3(1.0, 0.96, 0.88), clamp(sun_dir.y * 2.5, 0.0, 1.0));

	// Whitecaps on the steepest crests when it blows (and a few on a calm day).
	float foam = smoothstep(0.8, 0.96, crest) * smoothstep(0.55, 0.85, vnoise(p * 0.9 + TIME * 0.3)) * smoothstep(0.4, 0.8, vnoise(p0 * 0.02))
		* (0.04 + 0.96 * blow) * mid * near;

	ALBEDO = mix(body * (1.0 - fres), vec3(0.9), foam);
	EMISSION = (sky * fres * (1.0 - foam) * mix(1.0, 0.6, night) + sun_col * glint * day) * (1.0 - foam * 0.7);
	ROUGHNESS = mix(0.06, 0.6, foam) + 0.08 * blow;
	SPECULAR = 0.25;
}
