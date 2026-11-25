// Skyport kit props (tools/blender/build_skyport.py): one vertex-coloured
// surface per prop. COLOR.a: 1 matte, 0.6 gloss, 0 lamp / light box /
// screen (emissive: soft by day, bright at night). Rain gloss like the
// street furniture; contact darkening near the prop's base.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/shaders/terminal_light.gdshaderinc"

uniform bool terminal = false;
uniform vec2 terminal_anchor;
global uniform float wetness;
global uniform float night;

uniform float lamp_day = 0.12;
uniform float lamp_night = 3.2;

varying float v_y;
varying vec3 v_wp;

void vertex() {
	v_y = VERTEX.y;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i), n100 = hash3(i + vec3(1, 0, 0)), n010 = hash3(i + vec3(0, 1, 0)), n110 = hash3(i + vec3(1, 1, 0));
	float n001 = hash3(i + vec3(0, 0, 1)), n101 = hash3(i + vec3(1, 0, 1)), n011 = hash3(i + vec3(0, 1, 1)), n111 = hash3(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void fragment() {
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float lamp = 1.0 - step(0.3, COLOR.a);
	float gloss = step(0.3, COLOR.a) * (1.0 - step(0.8, COLOR.a));
	float up = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), 0.0, 1.0);
	float ao = mix(0.72, 1.0, smoothstep(0.0, 0.5, v_y));
	float wet = (terminal ? 0.0 : clamp(wetness, 0.0, 1.0)) * mix(0.4, 1.0, up);
	// Weathering on matte surfaces (concrete, paint): broad blotches, and
	// faint vertical rain streaks on walls; none on lamps and gloss.
	float matte = step(0.8, COLOR.a);
	float blot = vnoise(v_wp * 0.35) * 0.6 + vnoise(v_wp * 1.7) * 0.4;
	float streak = vnoise(vec3(v_wp.x * 2.3, v_wp.y * 0.12, v_wp.z * 2.3));
	col *= mix(1.0, 0.86 + 0.2 * blot - 0.07 * streak * (1.0 - up), matte);
	ALBEDO = col * ao * (1.0 - 0.22 * wet) * (1.0 - lamp * 0.72);
	ROUGHNESS = mix(mix(0.72, 0.28, gloss), 0.18, wet * 0.8);
	METALLIC = gloss * 0.45;
	EMISSION = col * lamp * (terminal ? 2.0 : mix(lamp_day, lamp_night, clamp(night, 0.0, 1.0)));
	if (terminal) {
		EMISSION += col * ao * terminal_irradiance(terminal_axes(v_wp, terminal_anchor), up) * (1.0 - lamp);
	}
}
