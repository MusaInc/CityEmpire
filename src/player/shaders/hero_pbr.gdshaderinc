// Shared body of the hero PBR shaders (hero_pbr / hero_pbr_plain).
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec3 tint = vec3(1.0);
uniform vec3 sole_tint = vec3(1.0);
uniform bool has_sole = false;
uniform bool has_roughness_map = false;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D ao_map : filter_linear_mipmap, hint_default_white;
uniform sampler2D roughness_map : filter_linear_mipmap, hint_default_white;
uniform float roughness = 0.8;
uniform float hair_fibres = 0.0;
uniform float surface_definition = 0.0;
#ifdef HAIR_SCALP
uniform vec3 scalp_tint = vec3(0.09, 0.035, 0.02);
#endif
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
global uniform float wetness;
global uniform float night;
// Separation from dark streets: a light rim from every light (stronger at
// night), and at night a faint cool edge where the body turns away from the
// camera. Edges only – the hero never glows.
uniform float rim_strength = 0.3;
uniform float night_edge = 0.07;
void vertex() {
    float freedom = UV2.x;
    if (freedom > 0.0) {
        mat3 world = mat3(MODEL_MATRIX);
        vec3 normal_world = normalize(world * NORMAL);
        vec3 offset = cloth_drag * freedom;
        // Keep free panels outside the body, including when the player brakes.
        offset -= normal_world * min(dot(offset, normal_world), 0.0);
        float ripple = sin(cloth_time * 9.0 + VERTEX.y * 14.0 + VERTEX.x * 13.0);
        offset += normal_world * (ripple + 1.0) * cloth_flutter * freedom * 0.005;
        VERTEX += transpose(world) * offset;
    }
}
void fragment() {
    // glTF converts the Blender V coordinate to a top-left origin.
    float mask = clamp(1.0 - UV2.y, 0.0, 1.0);
    vec3 outfit_tint = has_sole ? mix(tint, sole_tint, mask) : tint;
    vec4 sample_color = texture(albedo_map, UV);
#ifdef EYE
    float radius = length(UV * 2.0 - 1.0);
    float iris = 1.0 - smoothstep(0.474, 0.505, radius);
    outfit_tint = mix(vec3(1.0), tint, iris);
#endif
    ALBEDO = sample_color.rgb * base_color.rgb * outfit_tint;
#ifdef HAIR_SCALP
#ifdef HAIR_FADE
    // Blend the short roots over the real scalp. The opaque crown writes
    // depth in the prepass, while the thin fade uses one blended surface.
    float coverage = clamp((mask - 0.018) / 0.925, 0.0, 1.0);
    ALPHA = coverage;
    ALBEDO = mix(ALBEDO, scalp_tint * vec3(0.94, 0.90, 0.86), (1.0 - coverage) * 0.20);
#else
    ALBEDO = mix(scalp_tint * vec3(0.94, 0.90, 0.86), ALBEDO, smoothstep(0.025, 0.57, mask));
#endif
#endif
#ifdef HAIR_CARDS
    ALPHA = sample_color.a * mask;
    ALPHA_SCISSOR_THRESHOLD = mix(0.35, 0.26, surface_definition);
#else
    if (!FRONT_FACING) {
        ALBEDO *= inside_shade;  // the inside of the cloth, in its own shadow
    }
#endif
    float surface_roughness = has_roughness_map ? texture(roughness_map, UV).g : roughness;
    ROUGHNESS = mix(surface_roughness, max(0.3, surface_roughness - 0.18), wetness);
    EMISSION = surface_emission;
#if defined(SKIN)
    // Diffuse wrap and a low skin-coloured bounce keep detail in shadow.
    SPECULAR = mix(0.23, 0.27, surface_definition);
    ALBEDO *= vec3(1.04, 1.0, 0.97);
    EMISSION += ALBEDO * mix(mix(0.082, 0.029, surface_definition), 0.023, night);
#elif defined(EYE)
    SPECULAR = mix(0.26, 0.46, iris);
    RIM = 0.0;
    ROUGHNESS = mix(0.40, 0.22, iris);
#elif defined(HAIR_CARDS)
    SPECULAR = 0.22;
    EMISSION += ALBEDO * 0.035;
    ANISOTROPY = 0.55;
    ANISOTROPY_FLOW = vec2(0.0, 1.0);
#elif defined(HAIR_SCALP)
    SPECULAR = 0.23;
#else
    SPECULAR = 0.32;
#endif
#ifndef EYE
    RIM = rim_strength * (1.0 + night);
#endif
    RIM_TINT = 0.4;
    if (FRONT_FACING) {
        float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
        EMISSION += vec3(0.55, 0.68, 0.9) * edge * night_edge * night;
    }
#ifdef SKIN
    AO = mix(0.42, 1.0, texture(ao_map, UV).r);
    AO_LIGHT_AFFECT = mix(0.05, 0.24, surface_definition);
#elif !defined(HAIR_CARDS)
    AO = FRONT_FACING ? mix(0.18, 1.0, texture(ao_map, UV).r) : 0.55;
    AO_LIGHT_AFFECT = 0.12;
#endif
#ifndef NO_NORMAL_MAP
    vec3 n = texture(normal_map, UV).rgb * 2.0 - 1.0;
    n.xy *= normal_strength;
#ifdef HAIR_SCALP
    n.xy *= mix(0.18, mix(0.86, 1.04, surface_definition), smoothstep(0.0, 0.78, mask));
#endif
    if (detail_strength > 0.0) {
        vec2 d = texture(detail_normal_map, UV * detail_scale).rg * 2.0 - 1.0;
        n.xy += d * detail_strength;
    }
    if (hair_fibres > 0.0) {
        // The authored strand normals break up a broad highlight along the flow.
        ANISOTROPY = hair_fibres;
        ANISOTROPY_FLOW = vec2(0.0, 1.0);
        ROUGHNESS = clamp(ROUGHNESS + n.x * 0.08, 0.36, 0.78);
    }
    NORMAL_MAP = normalize(n) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;
#endif
}
