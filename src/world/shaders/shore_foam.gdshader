// Foam where the sea meets a sea wall or quay (Shoreline): UV.x = metres
// out from the wall (0..width), UV.y = metres along it. A bright lace right
// at the wall, breaking into patches further out, washing in and out with
// the swell; fades with distance so far coasts don't shimmer. Transparent,
// no depth reads.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

global uniform float night;
global uniform float rain;
uniform float width = 6.0;

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

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float out_m = UV.x;
	float along = UV.y;
	// The wash: the foam line moves in and out with a slow swell.
	float wash = 0.8 + 0.6 * sin(TIME * 0.7 + along * 0.05) + 0.4 * sin(TIME * 1.3 + along * 0.13);
	float edge = 1.0 - smoothstep(0.0, wash, out_m);
	float n = vnoise(vec2(along * 0.6, out_m * 1.4 - TIME * 0.4)) * 0.6 + vnoise(vec2(along * 2.1, out_m * 3.0 + TIME * 0.7)) * 0.4;
	float lace = smoothstep(0.45, 0.7, n) * (1.0 - smoothstep(0.0, width, out_m));
	float a = max(edge * 0.85, lace * 0.55) * (1.0 + 0.4 * rain);
	a *= 1.0 - smoothstep(250.0, 900.0, v_dist);
	ALBEDO = vec3(0.86, 0.9, 0.92) * mix(1.0, 0.2, night);
	ALPHA = clamp(a, 0.0, 0.9);
}
