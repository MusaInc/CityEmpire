class_name SeabedMesh
extends RefCounted
## The sea floor under the shallows, as real geometry: a coarse grid built
## from the baked seabed (tools/bake_seabed.gd, the same depths the water
## shader uses), kept only where the water is shallow enough to see through
## (water.gdshader lets the floor show there and turns opaque by ~6 m). Sand
## or rock by the nearest shore (the bake's A channel), drawn with the
## island ground shader's shore look, so it continues the beaches and rock
## armour down under the surface. ~10–20k triangles, one draw, no collision.

const CELL := 16.0          # m
const KEEP_DEPTH := 12.0     # cells shallower than this somewhere are kept (water is opaque by ~6 m)
const SEA_Y := -1.6


static func build(img: Image, rect: Rect2, max_depth: float) -> MeshInstance3D:
	if img.is_compressed():
		img.decompress()
	var W := img.get_width()
	var H := img.get_height()
	var nx := int(rect.size.x / CELL)
	var nz := int(rect.size.y / CELL)
	# (Bilinear: nearest-pixel depths stepped the floor into 5 m terraces
	# that showed through the clear water as a checkerboard.)
	var sample := func(x: float, z: float) -> Vector2:
		var fx := clampf((x - rect.position.x) / rect.size.x * W - 0.5, 0.0, W - 1.001)
		var fz := clampf((z - rect.position.y) / rect.size.y * H - 0.5, 0.0, H - 1.001)
		var ix := int(fx)
		var iz := int(fz)
		var tx := fx - ix
		var tz := fz - iz
		var c := img.get_pixel(ix, iz).lerp(img.get_pixel(ix + 1, iz), tx).lerp(
			img.get_pixel(ix, iz + 1).lerp(img.get_pixel(ix + 1, iz + 1), tx), tz)
		return Vector2(c.r * max_depth, c.a)   # (depth; 0 = land) , rockiness
	# Depth and rockiness at every grid node.
	var dep := PackedFloat32Array()
	var rk := PackedFloat32Array()
	dep.resize((nx + 1) * (nz + 1))
	rk.resize((nx + 1) * (nz + 1))
	for i in nx + 1:
		for j in nz + 1:
			var s: Vector2 = sample.call(rect.position.x + i * CELL, rect.position.y + j * CELL)
			dep[i * (nz + 1) + j] = s.x
			rk[i * (nz + 1) + j] = s.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sand := Color(0.8, 0.72, 0.55)
	var rock := Color(0.42, 0.4, 0.37)   # (as Skyport's rock armour: one look across the joint)
	var n_cells := 0
	var vidx := {}   # grid node id -> vertex index (shared: smooth normals)
	var node := func(id: int, i: int, j: int) -> int:
		if vidx.has(id):
			return vidx[id]
		var x := rect.position.x + i * CELL
		var z := rect.position.y + j * CELL
		# (Land nodes: just under the surface – the shore geometry covers them.)
		var d := dep[id] if dep[id] > 0.05 else 0.5
		# (Rock matches the armour it continues: Skyport's lighter granite,
		# the cities' darker boulders.)
		var rc := rock if SkyportIsland.distance_to(Vector3(x, 0.0, z)) < 140.0 else Color(0.23, 0.225, 0.225)
		var c := sand.lerp(rc, smoothstep(0.3, 0.8, rk[id]))
		c.a = 0.5 / 8.0
		st.set_color(c)
		st.set_uv(Vector2(x, z))
		st.set_uv2(Vector2(0.0, -1.0))   # (island_ground: shore surface)
		st.add_vertex(Vector3(x, SEA_Y - maxf(d, 0.3), z))
		vidx[id] = vidx.size()
		return vidx[id]
	for i in nx:
		for j in nz:
			var ids := [i * (nz + 1) + j, (i + 1) * (nz + 1) + j, (i + 1) * (nz + 1) + j + 1, i * (nz + 1) + j + 1]
			var dmin := INF
			var water := 0
			for id: int in ids:
				if dep[id] > 0.05:
					water += 1
					dmin = minf(dmin, dep[id])
			if water == 0 or dmin > KEEP_DEPTH:
				continue
			n_cells += 1
			var ij := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			var vi: Array = []
			for k in 4:
				vi.append(node.call(ids[k], ij[k][0], ij[k][1]))
			for k: int in [0, 1, 2, 0, 2, 3]:   # (faces up)
				st.add_index(vi[k])
	if n_cells == 0:
		return null
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Seabed"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://src/world/shaders/island_ground.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 2400.0
	return mi
