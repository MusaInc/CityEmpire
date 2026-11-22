shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D foliage : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 crown_normal;

void vertex() {
	// The cards have crown normals baked in Blender. Keep their light
	// direction consistent on either side of a card.
	crown_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float phase = dot(MODEL_MATRIX[3].xz, vec2(0.14, 0.19));
	float bend = clamp((VERTEX.y - 2.0) * 0.008, 0.0, 0.065);
	VERTEX.xz += vec2(sin(TIME * 1.25 + phase), cos(TIME * 0.91 + phase)) * bend;
}

void fragment() {
	vec4 leaf = texture(foliage, UV);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.28;
	vec3 normal = normalize(crown_normal);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normal);
	ALBEDO = leaf.rgb;
	BACKLIGHT = leaf.rgb * 0.24;
	ROUGHNESS = 0.88;
	SPECULAR = 0.23;
}
