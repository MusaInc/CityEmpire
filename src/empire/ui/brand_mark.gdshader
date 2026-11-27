shader_type canvas_item;
// WorldState's gold W: the alpha mask (assets/brand/w_mask.png) filled with
// brushed gold, plus an optional metallic light sweep (boot / title).
uniform float sweep = -1.0;        // band centre along the diagonal (-0.4 … 1.4)
uniform float sweep_k = 0.0;       // 0 = no sweep
uniform float sweep_w = 0.14;
uniform float lift = 1.0;          // brightness (the splash's breathing)
uniform vec3 g0 = vec3(0.965, 0.886, 0.659);
uniform vec3 g1 = vec3(0.882, 0.741, 0.416);
uniform vec3 g2 = vec3(0.769, 0.596, 0.282);
uniform vec3 g3 = vec3(0.627, 0.455, 0.180);

vec3 gold(float t) {
	if (t < 0.38) return mix(g0, g1, t / 0.38);
	if (t < 0.70) return mix(g1, g2, (t - 0.38) / 0.32);
	return mix(g2, g3, (t - 0.70) / 0.30);
}

void fragment() {
	float a = texture(TEXTURE, UV).r;
	vec3 c = gold(clamp(UV.y * 0.85 + UV.x * 0.15, 0.0, 1.0));
	float d = (UV.x * 0.62 + UV.y * 0.38) - sweep;
	float band = exp(-(d * d) / (sweep_w * sweep_w));
	c = min(c * lift, vec3(1.0));
	c = mix(c, vec3(1.0, 0.975, 0.90), clamp(band * sweep_k, 0.0, 1.0));
	COLOR = vec4(c, a * COLOR.a);
}
