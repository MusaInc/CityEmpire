// Headlight beam on the road ahead of a traffic car after dark (additive,
// no real light: mobile budget). Same placement as traffic.gdshader; parked
// cars (speed 0) keep theirs off.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

global uniform sampler2D ground_height : filter_linear, repeat_disable;
global uniform vec4 ground_rect;
global uniform float night;
global uniform float wetness;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.4;
uniform float beam = 0.85;
varying float moving;

void vertex() {
	float spd = INSTANCE_CUSTOM.x;
	moving = spd > 0.0 ? 1.0 : 0.0;
	float len = INSTANCE_CUSTOM.z;
	float d = mod(INSTANCE_CUSTOM.y + TIME * spd, len);
	// Shrink over the first/last metres so wrapping at the segment ends isn't a pop.
	float s = smoothstep(0.0, 4.0, d) * smoothstep(len, len - 4.0, d);
	VERTEX *= s;
	VERTEX.z -= d;
	if (spd > 0.0) {  // parked cars are placed on the ground by the CPU
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 hh = texture(ground_height, (w.xz - ground_rect.xy) / ground_rect.zw).rg;
		// North-south traffic rides road decks (R); east-west passes under (G).
		VERTEX.y += abs(MODEL_MATRIX[2].z) > 0.7 ? hh.r : hh.g;
	}
}

void fragment() {
	// UV.y 0 at the bumper .. 1 at the far end, UV.x across.
	float along = 1.0 - UV.y;
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float a = pow(along, 1.4) * pow(max(across, 0.0), 1.6) * (0.55 + 0.35 * wetness);
	ALBEDO = vec3(1.0, 0.9, 0.72) * a * beam * smoothstep(0.25, 0.7, night) * moving;
}
