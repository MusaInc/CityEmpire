class_name TreeKit
## Mobile LODs baked from the WorldState oak, birch and pine Blender study.
const SPECIES := ["oak", "birch", "pine"]
const SPECIES_TINT := {
	"oak": Vector3(0.95, 1.0, 0.92),
	"birch": Vector3(1.04, 1.04, 0.90),
	"pine": Vector3(0.84, 0.96, 0.92),
}
const CANOPY := preload("res://src/world/shaders/tree_canopy.gdshader")
const LOD_CELL := 96.0
static var _meshes := {}


static func near_mesh(species: String) -> ArrayMesh:
	return _load_mesh(species, "near")


static func mesh(species: String) -> ArrayMesh:
	return _load_mesh(species, "far")


static func _load_mesh(species: String, lod: String) -> ArrayMesh:
	var key := species + "_" + lod
	if _meshes.has(key):
		return _meshes[key]
	var path := "res://assets/models/world_tree_%s.glb" % key
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	var result := ArrayMesh.new()
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var transform := node.transform
		var ancestor := node.get_parent() as Node3D
		while ancestor:
			transform = ancestor.transform * transform
			ancestor = ancestor.get_parent() as Node3D
		for surface in node.mesh.get_surface_count():
			var source := node.mesh.surface_get_material(surface) as StandardMaterial3D
			var material: Material = source
			if source and String(source.resource_name).begins_with("Foliage"):
				var canopy := ShaderMaterial.new()
				canopy.shader = CANOPY
				canopy.set_shader_parameter("foliage", source.albedo_texture)
				canopy.set_shader_parameter("species_tint", SPECIES_TINT.get(species, Vector3.ONE))
				material = canopy
			elif source:
				var bark := source.duplicate() as StandardMaterial3D
				bark.roughness = maxf(bark.roughness, 0.88)
				bark.metallic = 0.0
				material = bark
			var geometry := SurfaceTool.new()
			geometry.begin(Mesh.PRIMITIVE_TRIANGLES)
			geometry.append_from(node.mesh, surface, transform)
			geometry.set_material(material)
			geometry.commit(result)
	root.free()
	_meshes[key] = result
	return result


static func _h(p: Vector3, salt: int) -> float:
	return float(hash(Vector3i(floori(p.x * 2.0), floori(p.z * 2.0), salt)) % 10007) / 10007.0


## District-appropriate species selection: coastal headlands & hills favour
## wind-sculpted pines, urban CBD/waterfront boulevards favour tidy birch &
## oak avenues, and parks/Old Town/Westbank mix broad leafy oak & birch.
static func pick(p: Vector3, park := false) -> String:
	var block := Vector3(floorf(p.x / 55.0), 0.0, floorf(p.z / 55.0))
	var sample := p if _h(p, 5) < (0.65 if park else 0.24) else block
	var r := _h(sample, 31)
	var coastal := p.y > 14.0 or p.x < -700.0 or (p.z > 900.0 and park)
	var urban_core := not park and p.x > 180.0 and p.x < 780.0 and p.z > -480.0 and p.z < 300.0
	if coastal:
		return "pine" if r < 0.52 else ("oak" if r < 0.80 else "birch")
	if urban_core:
		return "birch" if r < 0.48 else ("oak" if r < 0.94 else "pine")
	return "oak" if r < 0.52 else ("birch" if r < 0.86 else "pine")


static func shape(p: Vector3, base_scale: float) -> Basis:
	var spread := lerpf(0.84, 1.12, _h(p, 9))
	var height := lerpf(0.86, 1.17, _h(p, 7))
	return Basis(Vector3.UP, _h(p, 29) * TAU).scaled_local(Vector3(spread, height, spread) * base_scale)


static func instance_batch(parent: Node3D, species: String, placements: Array, ends_at: float, detail := true, detail_range := 82.0) -> void:
	var far_mesh := mesh(species)
	if not detail:
		_add_lods(parent, placements, far_mesh, null, ends_at, detail_range)
		return
	# Visibility ranges use the centre of the whole MultiMesh. Group local
	# crowns so the end of a long street doesn't decide LOD for the near end.
	var near := near_mesh(species)
	var cells := {}
	for xf: Transform3D in placements:
		var p := xf.origin
		var cell := Vector2i(floori(p.x / LOD_CELL), floori(p.z / LOD_CELL))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(xf)
	for batch: Array in cells.values():
		_add_lods(parent, batch, far_mesh, near, ends_at, detail_range)


static func _add_lods(parent: Node3D, placements: Array, far_mesh: Mesh, near_mesh_resource: Mesh, ends_at: float, detail_range: float) -> void:
	var far := _instance_lod(parent, placements, far_mesh)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.visibility_range_end = ends_at
	far.visibility_range_end_margin = 16.0
	if near_mesh_resource != null:
		far.visibility_range_begin = detail_range
		far.visibility_range_begin_margin = 10.0
		var near := _instance_lod(parent, placements, near_mesh_resource)
		near.visibility_parent = near.get_path_to(far)


static func _instance_lod(parent: Node3D, placements: Array, lod: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = lod
	mm.instance_count = placements.size()
	for i in placements.size():
		mm.set_instance_transform(i, placements[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	instance.extra_cull_margin = 0.4
	parent.add_child(instance)
	return instance
