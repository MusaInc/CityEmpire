shader_type spatial;
// Expanding concentric water-surface ripple & foam ring for character/vehicle
// water entry and wading wakes (VehicleFx).
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	// Two concentric foam/ripple rings + soft frothy inner core.
	float ring1 = exp(-pow((r - 0.84) / 0.09, 2.0));
	float ring2 = exp(-pow((r - 0.56) / 0.11, 2.0)) * 0.65;
	float foam = (1.0 - smoothstep(0.15, 0.72, r)) * 0.35;
	float mask = clamp(ring1 + ring2 + foam, 0.0, 1.0) * (1.0 - smoothstep(0.92, 1.0, r));
	ALBEDO = COLOR.rgb;
	ALPHA = mask * COLOR.a;
}
