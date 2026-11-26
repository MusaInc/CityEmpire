// Distant tree cards (TreeImpostors): alpha-tested, lit as a rounded crown
// (normals bent up and towards the viewer) so the two crossed cards never
// read as flat planes; a little per-tree tint variation.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

global uniform float night;
#include "res://src/world/shaders/lod_fade.gdshaderinc"
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;

varying float v_tint;

void vertex() {
	v_lod_d = lod_fade_dist(MODEL_MATRIX, INV_VIEW_MATRIX);
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_tint = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453);
	NORMAL = normalize(NORMAL * 0.35 + vec3(0.0, 0.75, 0.0));
}

void fragment() {
	if (lod_fade_discard(FRAGCOORD.xy)) {
		discard;
	}
	vec4 c = texture(atlas, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * mix(vec3(0.9, 0.95, 0.88), vec3(1.06, 1.04, 0.94), v_tint);
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = c.rgb * 0.3;
}
