// The water mirror's clip plane (WaterMirror, 2026-11-26). Godot has no
// oblique near plane, and the mirrored camera sits under the water – often
// under the land – so everything below the sea (quay walls, foundations,
// shelving shores, terrain skirts) stood between it and the reflection.
// In that pass only (the one camera ever below the sea), vertices under the
// water are pinned up to its plane: underwater faces collapse onto it and
// are culled from below. No discard (that would cost every pass early-z on
// tiled mobile GPUs); the normal camera takes the untouched branch.
void mirror_clip_vertex(inout vec3 vtx, mat4 model, mat4 inv_view) {
	if (inv_view[3].y < -1.9) {
		vec3 w = (model * vec4(vtx, 1.0)).xyz;
		if (w.y < -1.6) {
			w.y = -1.6;
			vtx = (inverse(model) * vec4(w, 1.0)).xyz;
		}
	}
}
