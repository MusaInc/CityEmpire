// Sunglass lenses (tools/blender/accessories.py): a dark tint you can just
// see the eyes through head-on, turning to a mirror at grazing angles. The
// reflection is a two-tone sky/ground gradient from the reflected view
// direction: no screen-space or probe cost, one small alpha surface.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;
uniform vec3 tint : source_color = vec3(0.025, 0.03, 0.035);
uniform float opacity = 0.86;
global uniform float night;
void fragment() {
    float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
    vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
    float up = smoothstep(-0.1, 0.45, r.y);
    vec3 sky = mix(vec3(0.5, 0.62, 0.78), vec3(0.06, 0.08, 0.14), night);
    vec3 env = mix(vec3(0.09, 0.085, 0.08), sky, up);
    ALBEDO = tint;
    ROUGHNESS = 0.05;
    SPECULAR = 0.65;
    EMISSION = env * (0.05 + 0.45 * f);
    ALPHA = mix(opacity, 0.97, f);
}
