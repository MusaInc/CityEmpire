class_name FoliageKit
extends RefCounted
## The card foliage (assets/models/foliage_kit.glb + foliage_atlas.png,
## tools/blender/build_foliage_cards.py) as instanceable meshes for parks and
## landscaping outside the city's chunk furniture: bush_round, bush_low,
## shrub_tall, box_ball, hedge_block, flower_bed, grass_tuft.

const PATH := "res://assets/models/foliage_kit.glb"
static var _meshes := {}
static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/world/shaders/foliage.gdshader")
		_mat.set_shader_parameter("atlas", load("res://assets/world/foliage_atlas.png"))
	return _mat


static func mesh(name: String) -> Mesh:
	if _meshes.is_empty() and ResourceLoader.exists(PATH):
		var inst := (load(PATH) as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := ((mi as MeshInstance3D).mesh as ArrayMesh).duplicate() as ArrayMesh
			for i in m.get_surface_count():
				m.surface_set_material(i, material())
			_meshes[String(mi.name)] = m
		inst.free()
	return _meshes.get(name)


## MultiMeshes of {name: [Transform3D]} under target.
static func place(target: Node3D, by_name: Dictionary, range_end := 260.0) -> void:
	for nm: String in by_name:
		var m := mesh(nm)
		var xfs: Array = by_name[nm]
		if m == null or xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Foliage_" + nm
		mi.multimesh = mm
		mi.visibility_range_end = range_end
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if nm == "grass_tuft" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		target.add_child(mi)
