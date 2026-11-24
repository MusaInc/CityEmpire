shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D foliage : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 species_tint = vec3(1.0);
global uniform float wetness;
global uniform float rain;

varying vec3 crown_normal;
varying float crown_height;
varying flat float tree_tone;

void vertex() {
	// The cards have crown normals baked in Blender. Keep their light
	// direction consistent on either side of a card.
	crown_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec2 root = MODEL_MATRIX[3].xz;
	float phase = dot(root, vec2(0.14, 0.19));
	tree_tone = fract(sin(dot(root, vec2(0.319, 0.471))) * 437.58);
	crown_height = smoothstep(2.2, 8.5, VERTEX.y);
	// Taper sway cleanly near trunk base and inner limbs so leaves never
	// detach from bark twigs, with rain-wind gust boost on outer tips.
	float height_t = smoothstep(2.4, 8.8, VERTEX.y);
	float radial_t = smoothstep(0.35, 2.2, length(VERTEX.xz));
	float gust = 1.0 + clamp(rain, 0.0, 1.0) * 1.45;
	float bend = height_t * (0.30 + 0.70 * radial_t) * 0.056 * gust;
	float flutter = height_t * radial_t * 0.014 * gust;
	float t_main = TIME * (1.25 + 0.45 * clamp(rain, 0.0, 1.0)) + phase;
	VERTEX.xz += vec2(sin(t_main), cos(t_main * 0.73)) * bend
		+ vec2(sin(TIME * 3.1 + phase * 3.7 + VERTEX.y), cos(TIME * 2.6 + phase * 2.9 + VERTEX.x)) * flutter;
}

void fragment() {
	vec4 leaf = texture(foliage, UV);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.28;
	vec3 normal = normalize(crown_normal);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normal);
	// Lower boughs receive less open sky. Preserve the card texture detail
	// while varying the warmth of neighbouring trees.
	float sky = crown_height * 0.64 + smoothstep(-0.35, 0.72, normal.y) * 0.36;
	float grey = dot(leaf.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 foliage_colour = mix(leaf.rgb, vec3(grey), 0.15);
	vec3 tint = mix(vec3(0.86, 0.94, 0.88), vec3(1.04, 0.96, 0.82), tree_tone) * species_tint;
	vec3 col = foliage_colour * tint * mix(0.70, 1.0, sky);
	float wet = clamp(wetness, 0.0, 1.0);
	ALBEDO = col * (1.0 - 0.22 * wet);
	BACKLIGHT = ALBEDO * mix(0.09, 0.20, sky) * (1.0 - 0.35 * wet);
	ROUGHNESS = mix(0.91, 0.34, wet * 0.85);
	SPECULAR = mix(0.18, 0.56, wet);
}
