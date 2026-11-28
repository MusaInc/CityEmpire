shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D foliage : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 species_tint = vec3(1.0);
global uniform float wetness;
global uniform float rain;
global uniform vec3 sun_dir;
global uniform float night;
#include "res://src/world/shaders/lod_fade.gdshaderinc"

varying vec3 crown_normal;
varying float crown_height;
varying float radial_out;
varying flat float tree_tone;

void vertex() {
	v_lod_d = lod_fade_dist(MODEL_MATRIX, MAIN_CAM_INV_VIEW_MATRIX);
	// The cards have crown normals baked in Blender. Keep their light
	// direction consistent on either side of a card.
	crown_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec2 root = MODEL_MATRIX[3].xz;
	float phase = dot(root, vec2(0.14, 0.19));
	tree_tone = fract(sin(dot(root, vec2(0.319, 0.471))) * 437.58);
	crown_height = smoothstep(2.0, 8.6, VERTEX.y);
	// Taper sway cleanly near trunk base and inner limbs so leaves never
	// detach from bark twigs, with rain-wind gust boost on outer tips.
	float height_t = smoothstep(2.3, 8.8, VERTEX.y);
	float radial_t = smoothstep(0.35, 2.2, length(VERTEX.xz));
	radial_out = radial_t;
	float gust_wave = 0.72 + 0.28 * sin(TIME * 0.55 + phase * 0.6);
	float gust = (1.0 + clamp(rain, 0.0, 1.0) * 1.55) * gust_wave;
	float bend = height_t * (0.30 + 0.70 * radial_t) * 0.068 * gust;
	float flutter = height_t * radial_t * 0.018 * gust;
	float t_main = TIME * (1.35 + 0.50 * clamp(rain, 0.0, 1.0)) + phase;
	VERTEX.xz += vec2(sin(t_main), cos(t_main * 0.73)) * bend
		+ vec2(sin(TIME * 3.4 + phase * 3.7 + VERTEX.y), cos(TIME * 2.8 + phase * 2.9 + VERTEX.x)) * flutter;
}

void fragment() {
	if (lod_fade_discard(FRAGCOORD.xy)) {
		discard;
	}
	vec4 leaf = texture(foliage, UV);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.34;
	vec3 normal = normalize(crown_normal);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normal);
	// Deep canopy self-shadowing (interior/lower boughs cool-shaded, sunlit
	// outer crown tips warmer & brighter) for volumetric leaf-cluster depth.
	float sky = clamp(crown_height * 0.54 + smoothstep(-0.35, 0.75, normal.y) * 0.32 + radial_out * 0.14, 0.0, 1.0);
	float grey = dot(leaf.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 foliage_colour = mix(leaf.rgb, vec3(grey), 0.14);
	// Per-tree organic hue variation: cool deep emerald to warm sunlit olive-gold.
	vec3 tint = mix(vec3(0.76, 0.91, 0.81), vec3(1.06, 0.95, 0.72), tree_tone) * species_tint;
	vec3 depth_tint = mix(vec3(0.76, 0.84, 0.92), vec3(1.06, 1.03, 0.94), sky);
	vec3 col = foliage_colour * tint * depth_tint * mix(0.48, 1.06, sky);
	float wet = clamp(wetness, 0.0, 1.0);
	ALBEDO = col * (1.0 - 0.24 * wet);
	// Subsurface translucent leaf glow when sunlight filters through outer boughs.
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float sun_through = pow(max(dot(-view_w, normalize(sun_dir)), 0.0), 3.0) * (1.0 - night);
	BACKLIGHT = ALBEDO * (mix(0.16, 0.36, sky) + sun_through * 0.35 * radial_out) * (1.0 - 0.35 * wet);
	ROUGHNESS = mix(0.86, 0.28, wet * 0.88);
	SPECULAR = mix(0.24, 0.62, wet);
}
