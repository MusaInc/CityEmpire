shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform float night;

void fragment() {
	// The real room stays visible behind the glass. A cheap sky gradient
	// gives the glazing weight at oblique angles.
	vec3 n = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);
	float grazing = 1.0 - abs(dot(n, view_dir));
	float fresnel = grazing * grazing * grazing;
	vec3 reflected = (INV_VIEW_MATRIX * vec4(reflect(-view_dir, n), 0.0)).xyz;
	float skyline = smoothstep(-0.09, 0.27, reflected.y);
	vec3 street = mix(vec3(0.039, 0.045, 0.044), sky_horizon * 0.27, skyline);
	vec3 reflection = mix(street, sky_top * 0.39, smoothstep(0.04, 0.86, reflected.y));
	ALBEDO = mix(COLOR.rgb * 0.35, reflection, 0.35 + 0.5 * fresnel);
	EMISSION = reflection * (0.24 + 0.64 * fresnel) * (1.0 - 0.38 * night);
	ALPHA = clamp(COLOR.a * 0.76 + 0.41 * fresnel, 0.085, 0.65);
	ROUGHNESS = 0.22;
	SPECULAR = 0.36;
}
