// Shared body of the hero PBR shaders (hero_pbr / hero_pbr_plain).
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec3 tint = vec3(1.0);
uniform vec3 sole_tint = vec3(1.0);
uniform bool has_sole = false;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D ao_map : filter_linear_mipmap, hint_default_white;
uniform sampler2D roughness_map : filter_linear_mipmap, hint_default_white;
uniform float roughness = 0.8;
uniform float normal_strength = 0.0;
// How dark the inside (back faces) of the cloth is: deep inside a garment
// opening 0.32; thin trims (collars, cuffs) show their edges, so lighter.
uniform float inside_shade = 0.32;
// Shared tiling fabric weave (garment_kit.weave_normal): fine cloth tooth on
// top of the garment's own baked seams/folds. 0 strength = off.
uniform sampler2D detail_normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 60.0;
uniform float detail_strength = 0.0;
uniform vec3 surface_emission = vec3(0.0);
uniform vec3 cloth_drag = vec3(0.0);
uniform float cloth_flutter = 0.0;
uniform float cloth_time = 0.0;
uniform vec3 cloth_wind_dir = vec3(0.0, 0.0, 1.0);
global uniform float wetness;
global uniform float night;
// Separation from dark streets: a light rim from every light (stronger at
// night), and at night a faint cool edge where the body turns away from the
// camera. Edges only – the hero never glows.
uniform float rim_strength = 0.3;
uniform float night_edge = 0.07;
void vertex() {
    float freedom = UV2.x;
    mat3 world = mat3(MODEL_MATRIX);
    vec3 normal_world = normalize(world * NORMAL);
    vec3 offset = cloth_drag * freedom;
    offset -= normal_world * min(dot(offset, normal_world), 0.0);
    float ripple = sin(cloth_time * 11.0 + VERTEX.y * 16.0 + VERTEX.x * 7.0);
    offset += normal_world * ripple * cloth_flutter * freedom * 0.004;
    VERTEX += inverse(world) * offset;
}
void fragment() {
    vec3 outfit_tint = has_sole ? mix(tint, sole_tint, clamp(UV2.y, 0.0, 1.0)) : tint;
    ALBEDO = texture(albedo_map, UV).rgb * base_color.rgb * outfit_tint;
    if (!FRONT_FACING) {
        ALBEDO *= inside_shade;  // the inside of the cloth, in its own shadow
    }
    float surface_roughness = roughness * texture(roughness_map, UV).g;
    ROUGHNESS = mix(surface_roughness, max(0.3, surface_roughness - 0.18), wetness);
#ifdef SKIN
    // Skin: lower, broader specular; a touch of warmth where light scatters
    // under the surface (cheap stand-in for SSS, which the mobile renderer lacks).
    SPECULAR = 0.28;
    ALBEDO *= vec3(1.03, 0.99, 0.96);
#else
    SPECULAR = 0.35;
#endif
    EMISSION = surface_emission;
    RIM = rim_strength * (1.0 + night);
    RIM_TINT = 0.4;
    if (FRONT_FACING) {
        float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
        EMISSION += vec3(0.55, 0.68, 0.9) * edge * night_edge * night;
    }
    AO = FRONT_FACING ? texture(ao_map, UV).r : 0.35;
    AO_LIGHT_AFFECT = 0.15;
#ifndef NO_NORMAL_MAP
    vec3 n = texture(normal_map, UV).rgb * 2.0 - 1.0;
    n.xy *= normal_strength;
    if (detail_strength > 0.0) {
        vec2 d = texture(detail_normal_map, UV * detail_scale).rg * 2.0 - 1.0;
        n.xy += d * detail_strength;
    }
    NORMAL_MAP = normalize(n) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;
#endif
}
