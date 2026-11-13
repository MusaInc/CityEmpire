// A soft cinematic vignette over the 3-D view (under the HUD): darkens the
// corners a touch and warms the edge, so the frame reads like a graded shot.
shader_type canvas_item;

uniform float strength = 0.32;
uniform vec3 tint : source_color = vec3(0.05, 0.04, 0.03);

void fragment() {
	vec2 p = UV - 0.5;
	p.x *= 1.25;
	float v = smoothstep(0.42, 0.92, length(p));
	COLOR = vec4(tint, v * strength);
}
