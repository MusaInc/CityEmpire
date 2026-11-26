// Tree bark (TreeKit trunks and limbs): the Blender bark material, plus the
// dithered LOD cross-fade the canopy uses (lod_fade.gdshaderinc).
shader_type spatial;
render_mode cull_back, diffuse_burley;
#include "res://src/world/shaders/lod_fade.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform float roughness = 0.9;

void vertex() {
	v_lod_d = lod_fade_dist(MODEL_MATRIX, INV_VIEW_MATRIX);
}

void fragment() {
	if (lod_fade_discard(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
