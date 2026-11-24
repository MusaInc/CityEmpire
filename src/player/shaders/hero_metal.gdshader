// Jewellery and fine metallic hardware (18k gold hoops, necklaces, brass buckles, zippers).
// Single-sided (cull_back) with crisp analytical studio/sky specular reflection and safe Fresnel
// so thin closed metal geometry gleams richly with zero backface z-fighting or black-speckle artefacts.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.92, 0.72, 0.28, 1.0);
uniform vec3 tint = vec3(1.0);
uniform float roughness = 0.20;
uniform float metallic = 0.88;
uniform vec3 surface_emission = vec3(0.0);
uniform float rim_strength = 0.16;
global uniform float night;
global uniform float wetness;

void fragment() {
    vec3 col = base_color.rgb * tint;
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(VIEW);
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(max(1.0 - ndv, 0.0001), 2.4);
    vec3 refl_v = reflect(-v, n);
    vec3 refl_w = normalize((INV_VIEW_MATRIX * vec4(refl_v, 0.0)).xyz);
    // High-contrast warm-ground / bright-sky / studio-key highlight for authentic polished 18k gold & silver.
    float sky_t = smoothstep(-0.22, 0.65, refl_w.y);
    float key_glint = pow(max(dot(refl_w, normalize(vec3(0.45, 0.74, 0.50))), 0.0), 20.0);
    float rim_glint = pow(max(dot(refl_w, normalize(vec3(-0.55, 0.45, -0.60))), 0.0), 10.0) * 0.45;
    float fill_band = exp(-pow((refl_w.y - 0.16) * 4.2, 2.0));
    vec3 env_col = mix(vec3(0.14, 0.09, 0.05), vec3(1.08, 0.98, 0.84), sky_t)
                 + vec3(0.32, 0.24, 0.14) * fill_band
                 + vec3(1.65, 1.48, 1.15) * (key_glint + rim_glint);
    ALBEDO = col;
    METALLIC = metallic * 0.80;
    ROUGHNESS = clamp(mix(roughness, max(0.10, roughness - 0.06), wetness), 0.10, 0.52);
    SPECULAR = 0.88;
    RIM = rim_strength;
    RIM_TINT = 0.72;
    EMISSION = surface_emission + col * env_col * (0.14 + 0.52 * fres) * metallic * (1.0 - night * 0.48);
}
