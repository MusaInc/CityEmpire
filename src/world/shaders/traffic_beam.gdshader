// The headlight beam on a car drawn by traffic.gdshader: those are the
// parked cars (chunks, IslandTraffic's CPU-placed cars) – lamps off, so the
// beam collapses to nothing. Moving traffic draws its beams with
// traffic_path_beam.gdshader (the same surface, swapped by Traffic).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_instance_color = false;
uniform float emission = 0.0;
uniform float roughness = 0.4;

void vertex() {
	VERTEX = vec3(0.0);
}

void fragment() {
	ALBEDO = vec3(0.0);
}
