class_name SkyportKit
extends RefCounted
## The airport prop kit (assets/models/skyport_kit.glb, built by
## tools/blender/build_skyport.py): one mesh per prop, vertex-coloured on
## skyport_kit.gdshader, glazing on the airport's glass. Props are placed as
## MultiMeshes (one per prop per group) so a whole airport's worth of tugs,
## seats, fences and lights is a few dozen draw calls.

const PATH := "res://assets/models/skyport_kit.glb"
static var _meshes := {}
static var _mat: ShaderMaterial
static var _mesh_mat: StandardMaterial3D


static func ready() -> bool:
	_load()
	return not _meshes.is_empty()


static func mesh(name: String) -> Mesh:
	_load()
	return _meshes.get(name)


static func _load() -> void:
	if not _meshes.is_empty() or not ResourceLoader.exists(PATH):
		return
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://src/world/shaders/skyport_kit.gdshader")
	_mesh_mat = StandardMaterial3D.new()
	_mesh_mat.albedo_color = Color(0.55, 0.57, 0.6, 0.38)
	_mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_mat.roughness = 0.6
	var glass := SkyportDistrict.terminal_glass()
	var inst := (load(PATH) as PackedScene).instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var src := (mi as MeshInstance3D).mesh as ArrayMesh
		if src == null:
			continue
		var m := src.duplicate() as ArrayMesh
		for i in m.get_surface_count():
			var sm := m.surface_get_material(i)
			var nm := String(sm.resource_name) if sm else ""
			if nm == "kit_glass":
				m.surface_set_material(i, glass)
			elif nm == "kit_mesh":
				m.surface_set_material(i, _mesh_mat)
			else:
				m.surface_set_material(i, _mat)
		_meshes[String(mi.name)] = m
	inst.free()


## One MultiMesh of `name` at the given transforms under target.
static func place(target: Node3D, name: String, xforms: Array, range_end := 900.0, shadows := true) -> MultiMeshInstance3D:
	var m := mesh(name)
	if m == null or xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "Kit_" + name
	mi.multimesh = mm
	mi.visibility_range_end = range_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(mi)
	return mi


## Transform at local point p, facing yaw (radians about +Y; 0 = the prop's
## front looks down -Z).
static func at(p: Vector3, yaw := 0.0, s := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), p)
