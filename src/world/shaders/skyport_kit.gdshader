// Skyport kit props (tools/blender/build_skyport.py): one vertex-coloured
// surface per prop. COLOR.a: 1 matte, 0.6 gloss, 0 lamp / light box /
// screen (emissive: soft by day, bright at night). Rain gloss like the
// street furniture; contact darkening near the prop's base.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float wetness;
global uniform float night;

uniform float lamp_day = 0.35;
uniform float lamp_night = 3.2;

varying float v_y;

void vertex() {
	v_y = VERTEX.y;
}

void fragment() {
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float lamp = 1.0 - step(0.3, COLOR.a);
	float gloss = step(0.3, COLOR.a) * (1.0 - step(0.8, COLOR.a));
	float up = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), 0.0, 1.0);
	float ao = mix(0.72, 1.0, smoothstep(0.0, 0.5, v_y));
	float wet = clamp(wetness, 0.0, 1.0) * mix(0.4, 1.0, up);
	ALBEDO = col * ao * (1.0 - 0.22 * wet) * (1.0 - lamp * 0.6);
	ROUGHNESS = mix(mix(0.72, 0.28, gloss), 0.18, wet * 0.8);
	METALLIC = gloss * 0.45;
	EMISSION = col * lamp * mix(lamp_day, lamp_night, clamp(night, 0.0, 1.0));
}
