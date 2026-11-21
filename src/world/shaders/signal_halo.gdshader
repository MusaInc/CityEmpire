// Halo variant of signal_glow.gdshader (additive). Traffic signal aspects (2026-11-21): lens discs over the modelled lenses
// (mode 0) and a soft halo round the lit one (mode 1, additive), cycling
// green -> amber -> red. INSTANCE_CUSTOM.r = aspect (0 red, 1 amber,
// 2 green), .g = this approach's phase offset (a junction's lights work
// together; the cross street is half a cycle off). Instanced per chunk.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float night;
uniform int mode = 1;   // (halo variant: additive)
const float CYCLE = 26.0;

varying flat float v_lit;
varying flat float v_aspect;

float state(float off) {
	float t = fract(TIME / CYCLE + off);
	return t < 0.38 ? 2.0 : (t < 0.5 ? 1.0 : 0.0);   // green 10 s, amber 3 s, red 13 s
}

void vertex() {
	v_aspect = floor(INSTANCE_CUSTOM.r * 3.0 + 0.5);
	v_lit = abs(state(INSTANCE_CUSTOM.g) - v_aspect) < 0.5 ? 1.0 : 0.0;
	if (mode == 1) {
		// Halo: a camera-facing quad at the lens, only for the lit aspect.
		vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float sz = mix(0.9, 2.2, night) * v_lit;
		VERTEX = (inverse(MODELVIEW_MATRIX) * vec4(c + vec3(VERTEX.xy * sz, 0.05), 1.0)).xyz;
	}
}

void fragment() {
	vec3 col = v_aspect < 0.5 ? vec3(1.0, 0.08, 0.04) : (v_aspect < 1.5 ? vec3(1.0, 0.55, 0.05) : vec3(0.1, 1.0, 0.45));
	if (mode == 0) {
		float r = length(UV - 0.5) * 2.0;
		if (r > 1.0) { discard; }
		ALBEDO = col * mix(0.06, 0.3, v_lit);
		EMISSION = col * v_lit * mix(3.0, 7.0, night) * (1.0 - 0.35 * r);
	} else {
		float r = length(UV - 0.5) * 2.0;
		ALBEDO = vec3(0.0);
		EMISSION = col * pow(max(1.0 - r, 0.0), 2.2) * mix(0.6, 2.4, night) * v_lit;
	}
}
