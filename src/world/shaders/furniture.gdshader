// Lightweight spatial shader for CityWorld street furniture (benches, bins,
// bollards, planters, shelters, utility boxes, crates, banners, tree grates).
// Vertex colours are sRGB; global wetness darkens and glosses upward surfaces
// in rain; vertical contact AO grounds bases against the pavement.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float wetness;
global uniform float night;
global uniform vec3 sky_horizon;
global uniform sampler2D ground_height : filter_linear, repeat_disable;
global uniform vec4 ground_rect;

uniform float base_roughness = 0.75;
uniform float ao_strength = 0.32;

varying float v_local_y;
varying vec3 v_wn;
varying vec3 v_wpos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wpos = wp;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 guv = (wp.xz - ground_rect.xy) / max(ground_rect.zw, vec2(1.0));
	if (ground_rect.z > 2.0 && guv.x > 0.0 && guv.y > 0.0 && guv.x < 1.0 && guv.y < 1.0) {
		float gy = texture(ground_height, guv).g;
		v_local_y = max(wp.y - gy, 0.0);
	} else {
		v_local_y = max(VERTEX.y, 0.0);
	}
}

void fragment() {
	// Vertex colours from StreetClutter / flattened glTF meshes are sRGB.
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	vec3 wn = normalize(v_wn);
	float up = clamp(wn.y, 0.0, 1.0);
	// Vertical contact AO where furniture meets the pavement, plus gentle
	// underside darkening on overhanging seats, lids and shelter roofs.
	float base_ao = mix(1.0 - ao_strength, 1.0, smoothstep(0.0, 0.42, v_local_y));
	float under_ao = mix(0.76, 1.0, smoothstep(-0.45, 0.35, wn.y));
	col *= base_ao * under_ao;
	// Rain response: rain-exposed tops darken & gloss strongly, vertical sides
	// pick up a subtle damp sheen; low matte surfaces stay realistic.
	float wet = clamp(wetness, 0.0, 1.0);
	float rain_coat = wet * mix(0.45, 1.0, smoothstep(0.2, 0.85, up));
	col *= 1.0 - 0.24 * rain_coat;
	float rough = mix(base_roughness, mix(0.32, 0.16, up), rain_coat * 0.85);
	// Subtle specular metal hint on dark ironwork (bollards, grates, brackets).
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float iron_k = (1.0 - smoothstep(0.04, 0.14, luma)) * 0.22;
	ALBEDO = col;
	ROUGHNESS = clamp(rough - iron_k * 0.25, 0.14, 1.0);
	METALLIC = iron_k;
	SPECULAR = mix(0.28, 0.62, rain_coat) + iron_k * 0.15;
	// Subtle ambient city-bounce fill at night so silhouettes remain readable.
	EMISSION = col * max(sky_horizon * 0.08, vec3(0.014, 0.016, 0.022)) * night;
}
