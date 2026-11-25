shader_type spatial;
render_mode cull_back, diffuse_burley;
// Tyre rubber. The wheels carry a real Blender unwrap (ws_texture.py
// unwrap_wheel): tread faces a cylindrical UV (U = 8 pitches per turn,
// V across the width), sidewalls a planar UV whose circle is the tyre.
// Tread relief, sidewall lettering and rim bands are baked maps
// (assets/vehicles/tex/tread_*, sidewall_*); the model's own AO bake is on UV2.

uniform bool sidewall = false;
uniform bool offroad = false;
uniform sampler2D tread_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tread_m : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D wall_m : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bake_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float ao_strength = 0.0;
uniform bool textured = false;
global uniform float wetness;
varying vec3 wheel_point;

void vertex() {
	wheel_point = VERTEX;
}

void fragment() {
	vec2 radial = wheel_point.yz;
	float radius = length(radial);
	float angle = atan(radial.y, radial.x) / 6.2831853;
	float detail = 1.0 - smoothstep(2.0, 12.0, length(VERTEX));
	float px = max(length(dFdx(radial)), length(dFdy(radial)));
	float ao = mix(1.0, texture(bake_tex, UV2).r, ao_strength);
	float rubber = 0.017;
	float raised = 0.0;
	float cuts = 0.0;
	float rough_t = 0.84;
	if (textured) {
		vec4 m;
		if (sidewall) {
			m = texture(wall_m, UV);
			NORMAL_MAP = texture(wall_n, UV).rgb;
			NORMAL_MAP_DEPTH = 1.0 * detail;
		} else {
			// (Off-road tyres: chunkier blocks - the same pitch at half the count.)
			vec2 tuv = offroad ? vec2(UV.x * 0.5, UV.y) : UV;
			m = texture(tread_m, tuv);
			NORMAL_MAP = texture(tread_n, tuv).rgb;
			NORMAL_MAP_DEPTH = (offroad ? 1.6 : 1.1) * detail;
		}
		raised = (m.a - 0.5) * 2.0;
		cuts = 1.0 - m.r;
		rough_t = m.g;
	} else if (sidewall) {
		float bands = max(1.0 - smoothstep(0.004, 0.009 + px, abs(radius - 0.914)),
			1.0 - smoothstep(0.004, 0.008 + px, abs(radius - 0.893)));
		raised = bands * 0.26 * (1.0 - smoothstep(0.03, 0.095, px));
		rubber = 0.018;
	} else {
		float pattern = angle * (offroad ? 24.0 : 58.0) + abs(wheel_point.x) * 5.5;
		float cell = abs(fract(pattern + 0.5) - 0.5);
		cuts = (1.0 - smoothstep(0.034, 0.112 + px * 2.0, cell)) *
			(1.0 - smoothstep(0.026, 0.10, px)) * smoothstep(0.91, 0.97, radius);
	}
	// Scrubbed tread surface: a touch lighter and smoother than the grooves.
	float wear = 0.065 * sin(angle * 427.2566) * (1.0 - smoothstep(0.018, 0.060, px));
	ALBEDO = vec3(rubber * (1.0 + detail * (raised * 1.25 + wear - cuts * 0.62)));
	SPECULAR = mix(0.28, 0.46, wetness);
	ROUGHNESS = clamp(rough_t - wetness * 0.26 * (1.0 - cuts) - raised * 0.1 * detail, 0.42, 0.96);
	AO = ao * mix(1.0, 1.0 - cuts * 0.5, detail);
	AO_LIGHT_AFFECT = 0.5;
}
