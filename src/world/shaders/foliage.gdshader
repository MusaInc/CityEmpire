// Card foliage (tools/blender/build_foliage_cards.py): bushes, hedges,
// shrubs, flower beds and grass tufts on one 512² atlas, alpha-tested.
// COLOR.r = height in the plant (wind sway grows with it), COLOR.gb = the
// card's own 0..1 coordinates (its edge is frayed into a leafy outline so no
// card reads as a square). Per-plant tint variation from world position;
// leaf translucency against the sun; rain darkens and glosses.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float wetness;
global uniform float night;
global uniform vec3 sky_horizon;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.42;
uniform float wind = 1.0;

varying vec3 v_wp;
varying float v_h;
varying vec2 v_card;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.3))) * 43758.5453);
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = COLOR.r;
	// Gentle, slow sway: the whole plant, plus a quicker leaf flutter.
	float t = TIME * 1.3 + dot(wp.xz, vec2(0.21, 0.17));
	vec2 sway = vec2(sin(t), cos(t * 0.83)) * 0.045 * h * h * wind;
	sway += vec2(sin(TIME * 4.1 + wp.x * 3.1), cos(TIME * 3.7 + wp.z * 2.9)) * 0.012 * h * wind;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * vec3(sway.x, 0.0, sway.y));
	v_wp = wp;
	v_h = h;
	v_card = COLOR.gb;
}

void fragment() {
	vec4 a = texture(atlas, UV);
	// Fray the card's border: leafy noise eats the outer 30 %.
	vec2 c = v_card * 2.0 - 1.0;
	float edge = max(abs(c.x), abs(c.y));
	float n = hash2(floor(UV * 180.0));
	float keep = 1.0 - smoothstep(0.62, 1.0, edge + (n - 0.5) * 0.35);
	if (a.a * keep < alpha_cut) {
		discard;
	}
	vec3 col = a.rgb;
	// Plant-to-plant variation: hue/brightness drift by position.
	float v = hash2(floor(v_wp.xz * 0.5));
	col *= mix(vec3(0.92, 0.97, 0.9), vec3(1.08, 1.04, 0.92), v);
	// Inner leaves darker (self-shadowing), tips lighter.
	col *= mix(0.68, 1.06, smoothstep(0.0, 0.9, v_h));
	float wet = clamp(wetness, 0.0, 1.0);
	ALBEDO = col * (1.0 - 0.2 * wet);
	ROUGHNESS = mix(0.78, 0.35, wet);
	SPECULAR = mix(0.25, 0.5, wet);
	BACKLIGHT = col * 0.55;
	EMISSION = col * max(sky_horizon * 0.04, vec3(0.005, 0.006, 0.008)) * night;
}
