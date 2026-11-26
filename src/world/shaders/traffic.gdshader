// Cars driven entirely on the GPU: each MultiMesh instance sits at the start
// of a lane segment facing along it; INSTANCE_CUSTOM = (speed m/s, phase m,
// segment length m, unused). The car slides along local -Z and wraps.
// One material per car surface: paint takes the instance colour, others keep
// their own tint; lamps emit.
shader_type spatial;
render_mode cull_back, diffuse_burley;

// Road surface height (CityWorld bakes CityTerrain.road_y): moving cars ride
// the terrain vertex by vertex, so they pitch with the street's grade.
global uniform sampler2D ground_height : filter_linear, repeat_disable;
global uniform vec4 ground_rect;
global uniform float night;
global uniform float wetness;
global uniform vec3 sky_top;
global uniform vec3 sky_horizon;
global uniform vec3 sun_dir;
#include "res://src/world/shaders/fake_reflect.gdshaderinc"
uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.4;
// The kind's Blender bake on UV2 (VehicleTex: R ambient occlusion, B cavity).
uniform sampler2D bake_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform bool has_bake = false;
// 0 plain, 1 paint (clearcoat), 2 glass (sky reflections), 3 chrome.
uniform int finish = 0;
// Sealed shells (panes on the paint, no cabin): the glass shows a traced
// cabin (fake_cabin.gdshaderinc). body_min/max: the shell's bounds.
#include "res://src/world/shaders/fake_cabin.gdshaderinc"
uniform bool sealed = false;
uniform vec3 body_min = vec3(-0.9, 0.0, -2.2);
uniform vec3 body_max = vec3(0.9, 1.5, 2.2);
varying vec3 v_local;
varying vec3 v_cam;

void vertex() {
	float spd = INSTANCE_CUSTOM.x;
	v_local = VERTEX;
	{
		float d0 = mod(INSTANCE_CUSTOM.y + TIME * spd, INSTANCE_CUSTOM.z);
		v_cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz + vec3(0.0, 0.0, d0);
	}
	float len = INSTANCE_CUSTOM.z;
	float d = mod(INSTANCE_CUSTOM.y + TIME * spd, len);
	// Shrink over the first/last metres so wrapping at the segment ends isn't a pop.
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
	vec3 c = use_instance_color ? COLOR.rgb : tint;
	vec3 bk = has_bake ? texture(bake_tex, UV2).rgb : vec3(1.0);
	ALBEDO = c * (0.7 + 0.3 * bk.b);
	AO = bk.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = mix(roughness, roughness * 0.5, wetness);
	METALLIC = use_instance_color ? 0.35 : 0.0;
	if (finish == 1) {
		// Lacquered paint: a glossy clear coat over a slightly metallic base.
		METALLIC = 0.33;
		ROUGHNESS = mix(0.36, 0.23, wetness);
		CLEARCOAT = 0.58;
		CLEARCOAT_ROUGHNESS = 0.18;
	} else if (finish == 2) {
		// Glass as on your own car (car_glass.gdshader): dark tint, smooth,
		// the city reflected strongest at grazing angles (below). It was a
		// near-mirror metal and read oddly next to the player's car.
		ALBEDO = vec3(0.037, 0.043, 0.046);
		METALLIC = 0.02;
		ROUGHNESS = 0.18;
		SPECULAR = 0.5;
		if (sealed) {
			vec3 bmin, bmax;
			cabin_box(body_min, body_max, bmin, bmax);
			vec3 dl = normalize(v_local - v_cam);
			vec3 dw = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
			float through;
			vec3 inside = fake_cabin(v_local, dl, bmin, bmax, cabin_outside(dw, sky_horizon, sky_top, night), through);
			// The cabin in the light that gets into it (sky level, dimmer at night),
			// seen through a light tint; the outside world at its own level.
			float amb = dot(sky_horizon, vec3(0.3, 0.55, 0.15)) * 1.15 + 0.02;
			ALBEDO = vec3(0.012);
			EMISSION = mix(inside * amb, inside, through) * vec3(0.80, 0.86, 0.88);
		}
	} else if (finish == 3) {
		METALLIC = 1.0;
		ROUGHNESS = 0.16;
		ALBEDO = max(c, vec3(0.55));
	}
	EMISSION += tint * emission * (1.0 + 3.5 * night);  // headlights and tail lights after dark
	if (finish > 0) {
		// The city in paint, glass and chrome (fake_reflect.gdshaderinc).
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 rw = reflect(-vw, nw);
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 env = finish == 1 ? paint_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night)
			: city_reflection(rw, wp, sky_top, sky_horizon, sun_dir, night);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), finish == 2 ? 3.0 : 4.0);
		float k = finish == 1 ? mix(0.09, 0.36, fres) : (finish == 2 ? mix(0.11, 0.48, fres) : 0.65);
		float glint = pow(max(dot(rw, normalize(sun_dir)), 0.0), finish == 1 ? 220.0 : 300.0) * (finish == 1 ? 0.9 : 0.75);
		EMISSION += (env * k * fake_keep() + vec3(glint) * (1.0 - night)) * (1.0 - 0.55 * night) * bk.r;
	}
}
