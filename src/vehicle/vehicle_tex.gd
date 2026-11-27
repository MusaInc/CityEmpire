class_name VehicleTex
## Vehicle texture set (tools/blender/ws_texture.py, run by tools/vehicle_tex/run.sh).
##
## * Shared, tileable detail families in assets/vehicles/tex/<family>_n.png
##   (normal) + <family>_m.png (R cavity, G roughness, B metal mask,
##   A albedo variation). Every vehicle's UV0 is a real unwrap at 1 UV unit
##   = 1 metre, so a family tiles at the same physical size on every body.
## * One bake per model, assets/vehicles/tex/<model>_bake.png on UV2 (the
##   packed atlas): R ambient occlusion, G convex edges, B cavity. The
##   top-right strip is white: glass, lenses and parts with no bake of their
##   own (traffic wheels, far boxes) point there.
## Paint colour stays a shader uniform: the bake only shades it, so player
## colours, liveries and traffic tints all keep working.

const DIR := "res://assets/vehicles/tex/"
const SURFACE_SHADER := preload("res://src/vehicle/car_surface.gdshader")
## UV2 of the white texel every bake keeps free.
const WHITE_UV2 := Vector2(0.992, 0.992)

## Material name -> [family, repeats per metre, normal depth, albedo variation, roughness mix, stitch].
## (Wheel parts use a planar wheel-face UV of 0..1: one repeat.)
const FINISH := {
	"trim": ["plastic", 14.0, 0.22, 0.08, 0.3, 0.0],
	"plastic": ["plastic", 16.0, 0.3, 0.1, 0.35, 0.0],
	"interior": ["leather", 9.0, 0.9, 0.45, 0.8, 1.0],
	"headliner": ["carpet", 14.0, 0.35, 0.35, 0.4, 0.0],
	"liner": ["carpet", 10.0, 0.9, 0.5, 0.5, 0.0],
	"rubber": ["rubber", 12.0, 0.5, 0.3, 0.6, 0.0],
	"cladding": ["plastic", 9.0, 0.5, 0.15, 0.4, 0.0],
	"bed": ["plastic", 5.0, 1.0, 0.4, 0.6, 0.0],
	"grille": ["grille", 9.0, 1.0, 0.4, 0.5, 0.0],
	"seam": ["rubber", 12.0, 0.3, 0.2, 0.3, 0.0],
	"carbon": ["fabric", 22.0, 0.45, 0.55, 0.15, 0.0],
	# ("reflector" is also the door-mirror glass: AO only, no lamp facets.)
	"chrome": ["brushed", 4.0, 0.06, 0.04, 0.15, 0.0],
	"rim": ["alloy", 1.0, 0.12, 0.05, 0.25, 0.0],
	"rim_dark": ["alloy", 1.0, 0.12, 0.05, 0.25, 0.0],
	"caliper": ["plastic", 20.0, 0.25, 0.1, 0.2, 0.0],
	"plate": ["plastic", 30.0, 0.2, 0.1, 0.2, 0.0],
	"plate_rear": ["plastic", 30.0, 0.2, 0.1, 0.2, 0.0],
	# Craft (build_craft.py names).
	"teak": ["teak", 2.2, 0.9, 0.6, 0.6, 0.0],
	"cushion": ["leather", 7.0, 0.8, 0.4, 0.8, 1.0],
	"antifoul": ["rubber", 3.0, 0.4, 0.35, 0.4, 0.0],
	"metal": ["brushed", 5.0, 0.25, 0.15, 0.4, 0.0],
	"intake": ["grille", 10.0, 1.0, 0.4, 0.5, 0.0],
	"exhaust": ["brushed", 6.0, 0.3, 0.3, 0.6, 0.0],
	"blade": ["plastic", 6.0, 0.3, 0.2, 0.4, 0.0],
}

## Off = every vehicle renders as before the texture pass (review renders).
static var enabled := true
static var _tex := {}
static var _bakes := {}
static var _mats := {}


static func tex(file: String) -> Texture2D:
	if not enabled:
		return null
	if not _tex.has(file):
		var p := DIR + file + ".png"
		_tex[file] = load(p) if ResourceLoader.exists(p) else null
	return _tex[file]


## The bake for a model file (e.g. "kestrel", "civ_sedan_lod1", "wheel_five"); null if none.
static func bake(model: String) -> Texture2D:
	if not enabled:
		return null
	if not _bakes.has(model):
		var p := DIR + model + "_bake.png"
		if not ResourceLoader.exists(p) and model.ends_with("_traffic"):
			p = DIR + model.trim_suffix("_traffic") + "_bake.png"
		_bakes[model] = load(p) if ResourceLoader.exists(p) else null
	return _bakes[model]


static func has_family(name: String) -> bool:
	return FINISH.has(name) and tex(String(FINISH[name][0]) + "_n") != null


## A detail finish: the base look of `base` (a StandardMaterial3D, as
## CarVisual.shared_mat builds it or a GLB carries it) on the car_surface
## shader with the family's maps and this model's bake. Cached per
## (name, model) so a fleet shares them.
static func surface(name: String, base: BaseMaterial3D, model: String) -> Material:
	var key := name + "@" + model + "@" + str(base.get_instance_id())
	if not _mats.has(key):
		_mats[key] = make_surface(name, base, model)
	return _mats[key]


## An uncached car_surface material (for per-car colours such as paint2).
static func make_surface(name: String, base: BaseMaterial3D, model: String) -> ShaderMaterial:
	var f: Array = FINISH.get(name, ["plastic", 10.0, 0.0, 0.0, 0.0, 0.0])
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("albedo", base.albedo_color)
	m.set_shader_parameter("roughness", base.roughness)
	m.set_shader_parameter("metallic", base.metallic)
	m.set_shader_parameter("specular", base.metallic_specular)
	m.set_shader_parameter("clearcoat", base.clearcoat if base.clearcoat_enabled else 0.0)
	m.set_shader_parameter("clearcoat_roughness", base.clearcoat_roughness)
	if base.emission_enabled:
		m.set_shader_parameter("emission_color", base.emission)
		m.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
	if FINISH.has(name):
		m.set_shader_parameter("detail_n", tex(String(f[0]) + "_n"))
		m.set_shader_parameter("detail_m", tex(String(f[0]) + "_m"))
		m.set_shader_parameter("detail_scale", float(f[1]))
		m.set_shader_parameter("normal_depth", float(f[2]))
		m.set_shader_parameter("albedo_var", float(f[3]))
		m.set_shader_parameter("rough_mix", float(f[4]))
		m.set_shader_parameter("stitch", float(f[5]))
	else:
		m.set_shader_parameter("normal_depth", 0.0)
		m.set_shader_parameter("albedo_var", 0.0)
		m.set_shader_parameter("rough_mix", 0.0)
	var b := bake(model)
	if b:
		m.set_shader_parameter("bake_tex", b)
		m.set_shader_parameter("ao_strength", 1.0)
	else:
		m.set_shader_parameter("ao_strength", 0.0)
	m.resource_name = name
	return m


## The opaque finishes of one mesh, set on the mesh itself (the caller
## owns or duplicated it): for meshes handed around without a node.
static func dress_mesh(mesh: Mesh, model: String, skip: Array = []) -> Mesh:
	if mesh == null or bake(model) == null:
		return mesh
	for i in mesh.get_surface_count():
		var sm := mesh.surface_get_material(i) as StandardMaterial3D
		if sm == null or sm.resource_name in skip or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or sm.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or sm.emission_enabled:
			continue
		mesh.surface_set_material(i, surface(sm.resource_name.get_slice(".", 0), sm, model))
	return mesh


## Opaque imported StandardMaterial3D finishes of a whole node tree (craft,
## rail, ships, the legacy delivery van) onto car_surface with their
## model's bake. Transparent and unshaded materials (glass, lamps, rotor
## blur) are left as they are.
static func dress(root: Node, model: String) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var cur := mi.get_surface_override_material(i)
			if cur == null:
				cur = mi.mesh.surface_get_material(i)
			var sm := cur as StandardMaterial3D
			if sm == null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
					or sm.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
				continue
			var n := sm.resource_name.get_slice(".", 0)
			mi.set_surface_override_material(i, surface(n, sm, model))
