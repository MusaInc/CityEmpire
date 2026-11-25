shader_type spatial;
// Textured vehicle finishes (VehicleTex): the base look of a material name
// (colour, roughness, metal, clear coat) over a shared tileable detail
// family on UV (1 UV unit = 1 m, real Blender unwrap) and the model's own
// Blender bake on UV2 (R ambient occlusion, G convex edges, B cavity).
render_mode blend_mix, cull_back, diffuse_burley;

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness = 0.5;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float clearcoat = 0.0;
uniform float clearcoat_roughness = 0.1;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

uniform sampler2D detail_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_m : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 10.0;   // repeats per metre
uniform float normal_depth = 1.0;
uniform float albedo_var = 0.3;
uniform float rough_mix = 0.6;
uniform float stitch = 0.0;          // seat/dash stitching along convex seams
uniform vec3 stitch_color : source_color = vec3(0.30, 0.29, 0.27);

uniform sampler2D bake_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float ao_strength = 1.0;
global uniform float wetness;

void fragment() {
	float dist = length(VERTEX);
	// Fine detail fades out before it can shimmer (and costs nothing far off).
	float near = 1.0 - smoothstep(7.0, 30.0, dist);
	vec2 uv = UV * detail_scale;
	vec4 m = texture(detail_m, uv);
	vec3 bk = texture(bake_tex, UV2).rgb;
	float ao = mix(1.0, bk.r, ao_strength);
	float cav = mix(1.0, bk.b, ao_strength);

	vec3 col = albedo * mix(1.0, 0.55 + 0.9 * m.a, albedo_var * near);
	col *= mix(1.0, m.r, 0.35 * near);
	// Grime settles in the baked cavities.
	col *= mix(1.0, 0.72 + 0.28 * cav, ao_strength);
	if (stitch > 0.0) {
		// Twin-needle stitching along convex seams (bake G), a dashed thread.
		float seam = smoothstep(0.35, 0.8, bk.g) * near * stitch;
		float dash = step(0.45, fract((UV.x + UV.y) * 260.0));
		col = mix(col, stitch_color, seam * dash * 0.8);
	}
	ALBEDO = col;
	float r = clamp(roughness + (m.g - 0.5) * rough_mix * near, 0.03, 1.0);
	ROUGHNESS = mix(r, r * 0.55, wetness * smoothstep(0.4, 0.9, NORMAL.y + 0.5) * cav);
	METALLIC = metallic * mix(1.0, m.b, near);
	SPECULAR = specular;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	NORMAL_MAP = texture(detail_n, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * near;
	AO = ao;
	AO_LIGHT_AFFECT = 0.45;
	EMISSION = emission_color * emission_energy;
}
