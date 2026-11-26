// Dithered LOD cross-fade for instanced trees (2026-11-26: "trees should be
// fully loaded before in view" – the levels hard-swapped at 82 m and ~310 m,
// so trees visibly changed or appeared while you drove). Over each band both
// levels draw: the outgoing one keeps the pixels where the screen dither is
// >= t, the incoming one where it is < t, with the same dither – complementary,
// so there is never a gap or a double tree, and no transparency (opaque
// discard, mobile-cheap). Bands are per MultiMeshInstance (instance uniforms)
// because the same meshes are used at different ranges (city, hills, Skyport).
instance uniform vec2 lod_fade_in = vec2(-2.0, -1.0);    // band in which this level comes in
instance uniform vec2 lod_fade_out = vec2(1.0e6, 2.0e6); // band in which it goes out
varying flat float v_lod_d;

float lod_fade_dist(mat4 model, mat4 inv_view) {
	return distance((model * vec4(0.0, 0.0, 0.0, 1.0)).xyz, inv_view[3].xyz);
}

bool lod_fade_discard(vec2 frag) {
	float h = fract(52.9829189 * fract(dot(floor(frag), vec2(0.06711056, 0.00583715))));
	float tin = smoothstep(lod_fade_in.x, lod_fade_in.y, v_lod_d);      // 0 → 1 as it comes in
	float tout = smoothstep(lod_fade_out.x, lod_fade_out.y, v_lod_d);   // 0 → 1 as it goes out
	return h >= tin || h < tout;
}
