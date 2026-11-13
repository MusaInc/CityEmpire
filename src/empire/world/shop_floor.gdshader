// Shop / warehouse floor: square tiles with grout, gentle per-tile tone and
// scuffs; matte (no mirror sky in a closed room). style 0 vinyl, 1 marble
// (the Flooring upgrade), 2 sealed concrete (warehouse).
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 base_col : source_color = vec3(0.78, 0.77, 0.74);
uniform vec2 room_size = vec2(10.0);
uniform int style = 0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * room_size;
	vec3 c = base_col;
	float rough = 0.62;
	if (style == 2) {
		float n = vn(p * 0.6) * 0.6 + vn(p * 3.0) * 0.4;
		c *= 0.88 + n * 0.18;
		float joint = 1.0 - smoothstep(0.0, 0.02, min(fract(p.x / 4.0), fract(p.y / 4.0)) * 4.0);
		c *= 1.0 - joint * 0.25;
		rough = 0.8;
	} else {
		float t = style == 1 ? 0.8 : 0.5;
		vec2 cell = floor(p / t);
		vec2 f = fract(p / t);
		float grout = 1.0 - smoothstep(0.0, 0.035, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		float tone = h21(cell) * 0.08 - 0.04;
		if (style == 0 && mod(cell.x + cell.y, 2.0) > 0.5) { tone -= 0.05; }
		c *= 1.0 + tone;
		if (style == 1) {
			float vein = abs(sin((p.x + vn(p * 1.3) * 2.5) * 2.1 + p.y * 0.7));
			c = mix(c, c * 0.82, (1.0 - smoothstep(0.0, 0.06, vein)) * 0.4);
			rough = 0.3;
		}
		c = mix(c, c * 0.55, grout * 0.8);
		c *= 0.94 + vn(p * 2.2) * 0.08;  // scuffs
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
