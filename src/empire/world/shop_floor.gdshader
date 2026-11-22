// Shop / warehouse floor: square tiles with grout, gentle per-tile tone and
// scuffs; matte (no mirror sky in a closed room). style 0 vinyl, 1 marble
// (the Flooring upgrade), 2 sealed concrete (warehouse).
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 base_col : source_color = vec3(0.78, 0.77, 0.74);
uniform vec2 room_size = vec2(10.0);
uniform int style = 0;
uniform sampler2D surface_detail : filter_linear_mipmap_anisotropic, repeat_enable;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * room_size;
	vec3 c = base_col;
	float rough = 0.62;
	float grout = 0.0;
	vec2 detail_uv = p / 0.86;
	if (style == 3) {
		// Individual boards share the grain but sample different areas of it.
		vec2 board = p / vec2(0.19, 1.48);
		board.y += h21(vec2(floor(board.x), 11.0));
		vec2 id = floor(board);
		vec2 f = fract(board);
		vec2 seam = min(f, 1.0 - f) * vec2(0.19, 1.48);
		vec2 aa = fwidth(p) * 0.65;
		vec2 cut = 1.0 - smoothstep(vec2(0.001), vec2(0.003, 0.005) + aa, seam);
		grout = max(cut.x, cut.y) * (1.0 - smoothstep(0.014, 0.12, aa.x + aa.y));
		detail_uv = (id + vec2(h21(id + 7.2), h21(id + 31.2))) + f * vec2(0.43, 0.82);
		c *= (0.89 + 0.22 * h21(id + 2.0)) * (1.0 - 0.28 * grout);
		rough = 0.43;
	} else if (style == 4) {
		// Ground terrazzo spans the installation with subtle divider strips.
		detail_uv = p / 0.78;
		vec2 strip = abs(fract(p / 3.2 + 0.5) - 0.5) * 3.2;
		grout = 1.0 - smoothstep(0.004, 0.012 + length(fwidth(p)), min(strip.x, strip.y));
		c *= 1.0 - 0.12 * grout;
		rough = 0.33;
	} else if (style == 2) {
		float n = vn(p * 0.6) * 0.6 + vn(p * 3.0) * 0.4;
		c *= 0.88 + n * 0.18;
		float joint = 1.0 - smoothstep(0.0, 0.02, min(fract(p.x / 4.0), fract(p.y / 4.0)) * 4.0);
		c *= 1.0 - joint * 0.25;
		grout = joint;
		rough = 0.8;
	} else {
		float t = style == 1 ? 0.8 : 0.5;
		vec2 cell = floor(p / t);
		vec2 f = fract(p / t);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		grout = (1.0 - smoothstep(0.003, 0.012 + length(fwidth(p)) * 0.52, edge * t))
			* (1.0 - smoothstep(0.018, 0.18, length(fwidth(p))));
		float tone = h21(cell) * 0.08 - 0.04;
		if (style == 0 && mod(cell.x + cell.y, 2.0) > 0.5) { tone -= 0.05; }
		c *= 1.0 + tone;
		if (style == 1) {
			rough = 0.34;
		}
		c = mix(c, c * 0.55, grout * 0.8);
		c *= 0.94 + vn(p * 2.2) * 0.08;  // scuffs
	}
	// Explicit gradients keep the oak grain sharp where the per-board UV jumps.
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	vec2 tile_grad = style == 3 ? vec2(0.43 / 0.19, 0.82 / 1.48) : vec2(style == 4 ? 1.0 / 0.78 : 1.0 / 0.86);
	vec4 detail_texel = textureGrad(surface_detail, detail_uv, dx * tile_grad, dy * tile_grad);
	float detail = (1.0 - smoothstep(10.0, 44.0, length(VERTEX))) * (1.0 - 0.85 * grout);
	c *= mix(1.0, detail_texel.r * 2.0, detail * (style == 3 || style == 4 ? 0.76 : 0.60));
	rough = mix(rough, detail_texel.a, detail * 0.45);
	vec2 slope = detail_texel.gb * 2.0 - 1.0;
	NORMAL_MAP = vec3(detail_texel.gb, 0.5 + 0.5 * sqrt(max(0.0, 1.0 - dot(slope, slope))));
	NORMAL_MAP_DEPTH = detail * 0.55;
	float side_edge = min(p.x, room_size.x - p.x);
	float back_edge = room_size.y - p.y;
	c *= mix(0.77, 1.0, smoothstep(0.0, 0.48, min(side_edge, back_edge)));
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
