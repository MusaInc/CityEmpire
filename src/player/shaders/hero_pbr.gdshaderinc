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
uniform float metallic = 0.0;
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
#ifdef SKIN
global uniform float lab_skin_sss;
#endif

void fragment() {
    // glTF converts the Blender V coordinate to a top-left origin.
    float mask = clamp(1.0 - UV2.y, 0.0, 1.0);
    vec3 outfit_tint = has_sole ? mix(tint, sole_tint, mask) : tint;
    vec4 sample_color = texture(albedo_map, UV);
#ifdef EYE
    // Subtle corneal refraction parallax: recesses the iris plane behind the curved wet cornea.
    vec2 eye_uv_raw = UV * 2.0 - 1.0;
    float r_raw = length(eye_uv_raw);
    float cornea_mask = 1.0 - smoothstep(0.42, 0.52, r_raw);
    vec2 view_ts = vec2(dot(VIEW, TANGENT), -dot(VIEW, BINORMAL));
    vec2 eye_uv = eye_uv_raw - view_ts * (0.048 * cornea_mask);
    float radius = length(eye_uv);
    float iris = 1.0 - smoothstep(0.450, 0.495, radius);
    // Deep, lifelike iris: soft dark limbal ring, warm lower-iris refraction caustic, deep jet-black pupil.
    float limbal = smoothstep(0.32, 0.475, radius) * iris;
    float pupil = 1.0 - smoothstep(0.178, 0.215, radius);
    float corner_ao = mix(1.0, 0.68, smoothstep(0.54, 0.94, r_raw));
    float caustic = smoothstep(-0.02, 0.38, eye_uv.y) * smoothstep(0.20, 0.33, radius) * (1.0 - smoothstep(0.35, 0.47, radius)) * iris;
    vec2 sample_uv = clamp(eye_uv * 0.5 + 0.5, vec2(0.002), vec2(0.998));
    vec3 iris_tex = texture(albedo_map, sample_uv).rgb;
    vec3 iris_base = iris_tex * base_color.rgb * tint * 1.32;
    iris_base *= mix(1.0, 1.08 - 0.54 * limbal, iris * (1.0 - pupil));
    iris_base += tint * vec3(0.42, 0.24, 0.09) * caustic * (1.0 - pupil);
    vec3 sclera_base = sample_color.rgb * base_color.rgb * vec3(0.99, 0.96, 0.935);
    vec3 eye_albedo = mix(sclera_base, iris_base, iris);
    // Deep recessed jet-black pupil.
    eye_albedo = mix(eye_albedo, vec3(0.003, 0.003, 0.004), pupil);
    // Natural upper-eyelid cast shadow grounding the eyeball inside the socket without dimming the iris.
    float lid_ao = mix(0.46, 1.0, smoothstep(0.16, 0.54, UV.y));
    ALBEDO = eye_albedo * lid_ao * corner_ao;
#else
    ALBEDO = sample_color.rgb * base_color.rgb * outfit_tint;
#endif
#ifdef HAIR_SCALP
#ifdef HAIR_FADE
    // Blend roots smoothly over the real scalp with soft organic hairline feathering.
    float coverage = smoothstep(0.015, 0.76, mask);
    ALPHA = coverage;
    ALBEDO = mix(scalp_tint * vec3(0.96, 0.92, 0.88), ALBEDO, smoothstep(0.0, 0.56, coverage));
#else
    ALBEDO = mix(scalp_tint * vec3(0.96, 0.92, 0.88), ALBEDO, smoothstep(0.03, 0.64, mask));
#endif
#endif
#ifdef HAIR_CARDS
    ALPHA = sample_color.a * mask;
    ALPHA_SCISSOR_THRESHOLD = mix(0.30, 0.24, surface_definition);
    // Subtle natural root-to-tip dimensional warmth (never over-bright grey plastic strips!).
    ALBEDO *= mix(vec3(0.82, 0.78, 0.74), vec3(1.10, 1.04, 0.98), smoothstep(0.08, 0.86, UV.y));
#else
    if (!FRONT_FACING) {
        ALBEDO *= inside_shade;  // the inside of the cloth, in its own shadow
    }
#endif
    float surface_roughness = has_roughness_map ? texture(roughness_map, UV).g : roughness;
    ROUGHNESS = mix(surface_roughness, max(0.3, surface_roughness - 0.18), wetness);
    METALLIC = metallic;
    EMISSION = surface_emission;
#if defined(SKIN)
    // Realistic human skin: warm dermal subsurface scatter, soft peach-fuzz grazing lift, natural satin-matte response.
    float skin_ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float skin_fres = pow(max(1.0 - skin_ndv, 0.0001), 3.6);
    SPECULAR = mix(0.24, 0.28, surface_definition);
    ALBEDO = ALBEDO * vec3(1.01, 0.995, 0.98) + ALBEDO * vec3(0.052, 0.038, 0.030) * skin_fres;
    BACKLIGHT = ALBEDO * vec3(0.40, 0.135, 0.060);
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
    SSS_STRENGTH = lab_skin_sss;
#endif
    EMISSION += ALBEDO * mix(mix(0.020, 0.012, surface_definition), 0.010, night);
#elif defined(EYE)
    // Wet dome cornea with crisp twin catchlights + subtle lower-meniscus moisture sheen.
    SPECULAR = mix(0.36, 0.72, iris);
    RIM = 0.0;
    ROUGHNESS = mix(0.11, 0.032, iris);
    CLEARCOAT = 0.75;
    CLEARCOAT_ROUGHNESS = 0.025;
    float catch_primary = exp(-dot(eye_uv_raw - vec2(-0.16, -0.14), eye_uv_raw - vec2(-0.16, -0.14)) / 0.0014);
    float catch_soft = exp(-dot(eye_uv_raw - vec2(0.15, 0.15), eye_uv_raw - vec2(0.15, 0.15)) / 0.0042) * 0.20;
    float catch_mask = smoothstep(0.18, 0.36, UV.y) * (1.0 - night * 0.55);
    EMISSION += vec3(1.0, 0.98, 0.95) * (catch_primary * 0.72 + catch_soft * 0.22) * catch_mask;
#elif defined(HAIR_CARDS)
    float hair_ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float hair_fres = pow(max(1.0 - hair_ndv, 0.0001), 3.2);
    SPECULAR = mix(0.12, 0.19, hair_fibres);
    ROUGHNESS = mix(0.68, clamp(mix(0.60, 0.50, UV.y), 0.48, 0.66), hair_fibres);
    // Warm subtle backlit strand glow (no flat plastic glare on top of crown!).
    BACKLIGHT = ALBEDO * vec3(0.28, 0.20, 0.14);
    EMISSION += ALBEDO * (0.014 + 0.024 * hair_fres) * (1.0 - night * 0.5);
    ANISOTROPY = max(0.32, hair_fibres * 0.55);
    ANISOTROPY_FLOW = vec2(0.0, 1.0);
#elif defined(HAIR_SCALP)
    float scalp_ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float scalp_fres = pow(max(1.0 - scalp_ndv, 0.0001), 3.4);
    SPECULAR = 0.12;
    ROUGHNESS = max(ROUGHNESS, 0.62);
    BACKLIGHT = ALBEDO * vec3(0.20, 0.14, 0.10);
    EMISSION += ALBEDO * (0.012 + 0.020 * scalp_fres) * (1.0 - night * 0.5);
#else
    // Realistic woven cloth micro-velvet sheen or silk satin lustre.
    float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float cloth_sheen = pow(max(1.0 - ndv, 0.0001), 3.8) * (1.0 - wetness * 0.55) * (1.0 - metallic);
    float is_silk = (1.0 - smoothstep(0.46, 0.60, surface_roughness)) * (1.0 - metallic);
    ALBEDO += vec3(0.032) * cloth_sheen + ALBEDO * 0.08 * cloth_sheen * is_silk;
    SPECULAR = mix(mix(0.20, 0.38, is_silk), 0.72, metallic);
    if (is_silk > 0.05) {
        ANISOTROPY = 0.25 * is_silk;
        ANISOTROPY_FLOW = vec2(0.0, 1.0);
    }
    if (metallic > 0.15) {
        vec3 refl_w = normalize((INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz);
        float sky_band = smoothstep(-0.35, 0.65, refl_w.y);
        float metal_fres = pow(max(1.0 - ndv, 0.0001), 2.2);
        vec3 env_grad = mix(vec3(0.38, 0.30, 0.22), vec3(1.10, 1.04, 0.96), sky_band);
        EMISSION += ALBEDO * env_grad * (0.28 + 0.36 * metal_fres) * metallic * (1.0 - night * 0.45);
        METALLIC = metallic * 0.70;
    }
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
