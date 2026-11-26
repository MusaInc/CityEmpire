class_name TreeImpostors
extends RefCounted
## Distant trees as two crossed cards (assets/world/tree_impostors.png,
## baked from TreeKit's own far meshes by tools/blender/bake_tree_impostors.py):
## 4 triangles a tree. Streamed chunks show them beyond their real trees'
## range (300 m on) and the FarCity shows them for every chunk that isn't
## streamed, so trees exist at every distance instead of appearing in front
## of you at 320 m (or later, when a chunk streamed in late at speed).

const ATLAS := "res://assets/world/tree_impostors.png"
static var _meshes := {}
static var _mat: ShaderMaterial


static func ready() -> bool:
	return ResourceLoader.exists(ATLAS)


static func mesh(species: String) -> ArrayMesh:
	if _meshes.has(species):
		return _meshes[species]
	var i := TreeKit.SPECIES.find(species)
	var far := TreeKit.mesh(species)
	if i < 0 or far == null:
		return null
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/world/shaders/tree_impostor.gdshader")
		_mat.set_shader_parameter("atlas", load(ATLAS))
	var bb := far.get_aabb()
	var size := maxf(bb.size.y, maxf(bb.size.x, bb.size.z))
	var y0 := bb.position.y
	var u0 := float(i) / TreeKit.SPECIES.size()
	var u1 := float(i + 1) / TreeKit.SPECIES.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var r := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var hw := r * size * 0.5
		var n := r.cross(Vector3.UP)
		var corners := [-hw + Vector3(0, y0, 0), hw + Vector3(0, y0, 0), hw + Vector3(0, y0 + size, 0), -hw + Vector3(0, y0 + size, 0)]
		var uvs := [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	var m := st.commit()
	m.surface_set_material(0, _mat)
	_meshes[species] = m
	return m


## One MultiMesh per species of `list` ([species, Transform3D]) under root.
static func place(root: Node3D, by_species: Dictionary, begin: float, end: float) -> void:
	for sp: String in by_species:
		var m := mesh(sp)
		var xfs: Array = by_species[sp]
		if m == null or xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = xfs.size()
		for j in xfs.size():
			mm.set_instance_transform(j, xfs[j])
		var mi := MultiMeshInstance3D.new()
		mi.name = "TreeImpostors_" + sp
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Fades in over the band the real trees fade out in (TreeKit.FADE before
		# their `ends_at`, which callers pass as begin + 20).
		var fb := begin + 20.0
		mi.visibility_range_begin = maxf(0.0, fb - TreeKit.FADE - 4.0) if begin > 0.0 else 0.0
		if begin > 0.0:
			mi.set_instance_shader_parameter("lod_fade_in", Vector2(fb - TreeKit.FADE, fb))
		mi.visibility_range_end = end
		root.add_child(mi)
