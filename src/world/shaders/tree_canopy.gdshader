shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D foliage : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
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
	float bend = clamp((VERTEX.y - 2.0) * 0.008, 0.0, 0.065);
	VERTEX.xz += vec2(sin(TIME * 1.25 + phase), cos(TIME * 0.91 + phase)) * bend;
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
	vec3 tint = mix(vec3(0.86, 0.94, 0.88), vec3(1.04, 0.96, 0.82), tree_tone);
	ALBEDO = foliage_colour * tint * mix(0.70, 1.0, sky);
	BACKLIGHT = ALBEDO * mix(0.09, 0.20, sky);
	ROUGHNESS = 0.91;
	SPECULAR = 0.18;
}
