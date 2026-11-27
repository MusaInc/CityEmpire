shader_type canvas_item;
render_mode blend_add;
// The splash W's breathing glow (2026-11-27): a soft gold halo drawn from
// the W's own mask (blurred via its mipmaps), on a rect grown round the mark
// (the mask has no margin of its own). Additive, so it only ever lightens
// the navy; `k` is the whole layer's strength (boot.gd breathes it).
uniform float k = 0.0;
uniform vec2 pad = vec2(0.25, 0.25);   // this rect's margin round the mark, in UV
uniform vec3 col = vec3(1.0, 0.70, 0.28);    // saturated warm gold (additive on navy)
uniform float radius = 0.11;           // blur radius in mark-UV (a soft aura, not an outline)
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_disable;

float mask_at(vec2 uv, float lod) {
	// (The W touches the texture's edges, so a coarse mip is still bright
	// there: fade softly past the edge instead of cutting – a hard cut drew
	// the rect's outline.)
	vec2 out_d = max(max(-uv, uv - 1.0), vec2(0.0));
	float fade = 1.0 - smoothstep(0.0, 0.16, length(out_d * vec2(1.0, 1.28)));
	return textureLod(mask_tex, clamp(uv, 0.0, 1.0), lod).r * fade;
}

void fragment() {
	vec2 uv = (UV - pad) / (1.0 - 2.0 * pad);
	// The blur is the mip chain itself: at LOD 5.5 the whole W is ~22×17
	// texels, which trilinear filtering spreads into a smooth aura; a 3×3 of
	// close taps only smooths the texel grid (a wide tap spiral drew ghost
	// copies of the W instead of a glow).
	float sum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			sum += mask_at(uv + vec2(float(x), float(y) * 1.28) * radius * 0.5, 5.5);
		}
	}
	float g = sqrt(sum / 9.0);   // (a long, soft tail rather than a rim)
	COLOR = vec4(col * g * k, 1.0);
}
