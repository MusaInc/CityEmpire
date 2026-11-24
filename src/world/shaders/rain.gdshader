// Rain streaks (RainFx): each instance's origin is a fixed point in a box;
// the box scrolls down and with the wind, and wraps round the camera, so the
// same drops fall forever. Streaks face the camera about their own axis.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 box = vec3(42.0, 22.0, 42.0);
uniform float amount = 1.0;
uniform vec3 tint = vec3(0.82, 0.88, 0.95);
const float FALL = 21.0;
const vec2 WIND = vec2(3.4, 1.6);

varying float v_fade;

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 o = MODEL_MATRIX[3].xyz;  // (MultiMesh: instance transform folded into MODEL_MATRIX)
	float h = fract(o.x * 12.9898 + o.z * 78.233);
	float speed_k = 0.82 + 0.38 * fract(h * 17.3);
	vec3 drift = vec3(WIND.x, -FALL, WIND.y) * (TIME * speed_k);
	vec3 p = mod(o + drift - cam + box * 0.5, box) - box * 0.5 + cam;
	// Thin out with amount: drops past the share simply vanish.
	float keep = step(h, amount);
	vec3 fall_dir = normalize(vec3(WIND.x, -FALL, WIND.y));
	vec3 to_cam = normalize(cam - p);
	vec3 facing_side = cross(fall_dir, to_cam);
	vec3 side = facing_side * inversesqrt(max(dot(facing_side, facing_side), 0.0001));
	float d = length(cam - p);
	float width_k = mix(0.85, 1.45, smoothstep(4.0, 18.0, d));
	vec3 wv = p + side * VERTEX.x * width_k - fall_dir * VERTEX.y * (0.65 + 0.65 * amount) * speed_k;
	v_fade = keep * smoothstep(1.1, 3.2, d) * (1.0 - smoothstep(box.x * 0.28, box.x * 0.5, d));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wv, 1.0);
}

void fragment() {
	ALBEDO = tint;
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	edge = edge * edge;
	float trail = smoothstep(0.0, 0.16, UV.y) * (1.0 - smoothstep(0.22, 1.0, UV.y));
	ALPHA = v_fade * edge * (0.18 + 0.32 * amount) * trail;
}
