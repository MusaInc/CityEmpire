// Photographic PBR detail (CC0 Poly Haven sets, assets/textures/pbr): one RGBA
// texture per material – R albedo luminance (mean 0.5), G/B normal x/y,
// A roughness (tools/textures/pack_detail.gd). The surface keeps its own
// colour; the photo adds grain, relief and roughness variation up close.

// Weight of the detail at a distance (mips carry it a little further than
// the normals, which would shimmer).
float pbr_fade(float dist) {
	return 1.0 - smoothstep(35.0, 140.0, dist);
}

// World normal for a flat-ish surface (tangent +X, bitangent +Z).
vec3 pbr_flat_normal(vec4 d, vec3 nw, float k) {
	vec2 nxy = (d.gb * 2.0 - 1.0) * k;
	return normalize(nw + vec3(nxy.x, 0.0, -nxy.y));
}

// World normal for a wall (tangent along the wall, bitangent up).
vec3 pbr_wall_normal(vec4 d, vec3 nw, float k) {
	vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), nw) + vec3(1e-4));
	vec2 nxy = (d.gb * 2.0 - 1.0) * k;
	return normalize(nw + t * nxy.x + vec3(0.0, 1.0, 0.0) * nxy.y);
}
