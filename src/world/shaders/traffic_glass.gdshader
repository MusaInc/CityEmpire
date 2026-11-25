// Transparent automotive glazing for parked cars and Skyport Island traffic.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley;

global uniform sampler2D ground_height : filter_linear, repeat_disable;
global uniform vec4 ground_rect;
global uniform float night;
global uniform float wetness;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"
uniform vec3 tint : source_color = vec3(0.035, 0.045, 0.06);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.12;
uniform int finish = 2;

void vertex() {
	float spd = INSTANCE_CUSTOM.x;
	float len = INSTANCE_CUSTOM.z;
	float d = mod(INSTANCE_CUSTOM.y + TIME * spd, len);
	float s = smoothstep(0.0, 4.0, d) * smoothstep(len, len - 4.0, d);
	VERTEX *= s;
	VERTEX.z -= d;
	if (spd > 0.0) {  // parked cars are placed on the ground by the CPU
		// Rigid on the road: height from under the front and rear axles
		// (half a wheelbase either side of the car's centre), pitch from
		// their difference – the body no longer bends to every vertex's
		// own ground height over crests and dips.
		vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, -d, 1.0)).xyz;
		vec3 fz = normalize(MODEL_MATRIX[2].xyz);
		bool ns = abs(MODEL_MATRIX[2].z) > 0.7;   // (north-south traffic rides road decks: R; east-west passes under: G)
		vec2 hf2 = texture(ground_height, ((c - fz * 1.35).xz - ground_rect.xy) / ground_rect.zw).rg;
		vec2 hr2 = texture(ground_height, ((c + fz * 1.35).xz - ground_rect.xy) / ground_rect.zw).rg;
		float hf = ns ? hf2.r : hf2.g;
		float hr = ns ? hr2.r : hr2.g;
		float grade = clamp((hf - hr) / 2.7, -0.6, 0.6);
		VERTEX.y += 0.5 * (hf + hr) - (VERTEX.z + d) * grade;
	}
}

void fragment() {
	ALBEDO = vec3(0.035, 0.045, 0.06);
	METALLIC = 0.04;
	ROUGHNESS = mix(0.09, 0.14, wetness);
	SPECULAR = 0.5;
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 rw = reflect(-vw, nw);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 env = city_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.8);
	float glint = pow(max(dot(rw, normalize(sun_dir)), 0.0), 240.0) * 0.62;
	EMISSION = (env * mix(0.11, 0.56, fres) + vec3(glint) * (1.0 - night)) * (1.0 - 0.50 * night);
	ALPHA = mix(0.32, 0.84, fres);
}
