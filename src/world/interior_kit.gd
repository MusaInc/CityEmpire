class_name InteriorKit
extends RefCounted
## Shared wall furniture and material finishes for streamed interiors.
## Room space uses x across the floor and -z into the room. Cabinet fronts
## are +z. Callers reserve furniture, windows, circulation and interactions.

const BAY_SPACING := 1.36
const BAY_DEPTH := 0.44
const MIN_AISLE := 0.72
const STOCK_PALETTES := {
	"cafe": [Color("#aa875c"), Color("#64452e"), Color("#535d49"), Color("#956a50")],
	"grocery": [Color("#546e42"), Color("#af6641"), Color("#cfb870"), Color("#637784"), Color("#995853")],
	"fitness": [Color("#898c8a"), Color("#bfbcb4"), Color("#4b5961"), Color("#575654")],
	"fashion": [Color("#48484f"), Color("#ae9c86"), Color("#657276"), Color("#86585e"), Color("#cbc1aa")],
	"technology": [Color("#969b9d"), Color("#777c82"), Color("#c1c5c6"), Color("#4c5963")],
	"hospitality": [Color("#baad94"), Color("#62766f"), Color("#a18065"), Color("#dfcfb6")],
	"work": [Color("#977755"), Color("#838a88"), Color("#56605e"), Color("#b18c57")],
	"library": [Color("#766253"), Color("#92734d"), Color("#535b64"), Color("#6f4845"), Color("#b4a483")],
}
const TEXTURES := {
	"oak": "res://assets/textures/pbr/worldstate_retail_oak.png",
	"concrete": "res://assets/textures/pbr/worldstate_pavement_concrete.png",
	"terrazzo": "res://assets/textures/pbr/worldstate_retail_terrazzo.png",
	"ceramic": "res://assets/textures/pbr/worldstate_retail_ceramic.png",
}
static var _meshes: Dictionary = {}
static var _glass: StandardMaterial3D
static var _contact: ShaderMaterial


## Soft authored contact shade on inexpensive inset quads for Mobile.
static func add_contacts(root: Node3D, feet: Array[Rect2]) -> void:
	if feet.is_empty():
		return
	if _contact == null:
		_contact = ShaderMaterial.new()
		_contact.shader = preload("res://src/world/shaders/interior_contact.gdshader")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv := [Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]
	for foot in feet:
		var expanded := foot.grow(0.18)
		var x0 := expanded.position.x
		var x1 := expanded.end.x
		var z0 := expanded.position.y
		var z1 := expanded.end.y
		var y := 0.016
		var corners := [Vector3(x0, y, z0), Vector3(x1, y, z0),
			Vector3(x1, y, z1), Vector3(x0, y, z1)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			surface.set_uv(uv[i])
			surface.add_vertex(corners[i])
	var layer := MeshInstance3D.new()
	layer.name = "FurnitureContact"
	layer.mesh = surface.commit()
	layer.material_override = _contact
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.visibility_range_end = 36.0
	root.add_child(layer)


static func fitting_glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color("#868b89")
		_glass.metallic = 0.78
		_glass.roughness = 0.16
	return _glass


static func wall_finish(span: Vector2, tint: Color, style: int, seed: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/world/shaders/home_wall.gdshader")
	mat.set_shader_parameter("size", span)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("style", style)
	mat.set_shader_parameter("seed", float(posmod(seed, 128)))
	mat.set_shader_parameter("surface_detail", finish_texture("oak" if style == 1 else "concrete"))
	mat.set_shader_parameter("detail_on", true)
	return mat


static func finish_texture(finish: String) -> Texture2D:
	return load(TEXTURES.get(finish, TEXTURES["ceramic"])) as Texture2D


static func profile(use: String) -> String:
	match use:
		"convenience", "supermarket", "bakery":
			return "grocery"
		"department", "clothing", "arden", "threadline", "furniture":
			return "fashion"
		"electronics", "phone", "phones":
			return "technology"
		"fitness":
			return "fitness"
		"cafe", "restaurant", "takeaway":
			return "cafe"
		"hotel", "marina":
			return "hospitality"
		"warehouse", "garage", "aviation", "kestrel", "meridian":
			return "work"
		_:
			return "library"


## Each bay reserves its own footprint and the clearance in front. Solid
## returns can be furnished on either side of the same corner.
static func plan(width: float, depth: float, height: float, blocked: Array[Rect2],
		front_clear: float, back_clear: float, walls := [true, true, true]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if width < 3.4 or depth < 3.1:
		return result
	var floor_height := clampf(height - 0.16, 2.12, 3.3)
	var reserved: Array[Rect2] = blocked.duplicate()
	var strips: Array = [[], [], []]
	for side in 3:
		if not walls[side]:
			continue
		var limit := width - 0.75 if side == 2 else depth - 0.72
		var along := 0.78 if side == 2 else front_clear + BAY_SPACING * 0.5
		while along < limit:
			var p: Vector3
			var face: Vector3
			var access: Rect2
			match side:
				0:
					p = Vector3(BAY_DEPTH * 0.5, 0, -along)
					face = Vector3.RIGHT
					access = Rect2(0.02, -along - 0.66, BAY_DEPTH + MIN_AISLE, 1.32)
				1:
					p = Vector3(width - BAY_DEPTH * 0.5, 0, -along)
					face = Vector3.LEFT
					access = Rect2(width - BAY_DEPTH - MIN_AISLE, -along - 0.66, BAY_DEPTH + MIN_AISLE, 1.32)
				_:
					p = Vector3(along, 0, -depth + back_clear + BAY_DEPTH * 0.5)
					face = Vector3.BACK
					access = Rect2(along - 0.66, p.z - 0.21, 1.32, BAY_DEPTH + MIN_AISLE)
			if not reserved.any(func(r: Rect2) -> bool: return r.intersects(access)):
				var basis := Basis.looking_at(-face, Vector3.UP).scaled_local(Vector3(1, floor_height / 2.7, 1))
				var xf := Transform3D(basis, p)
				strips[side].append(xf)
				reserved.append(_foot_rect(xf).grow(0.012))
			along += BAY_SPACING
	# Give each available wall a share of the room's fixture budget.
	for i in maxi(strips[0].size(), maxi(strips[1].size(), strips[2].size())):
		for strip: Array in strips:
			if i < strip.size():
				result.append(strip[i])
				if result.size() == 30:
					return result
	return result


static func footprint(xf: Transform3D) -> AABB:
	return xf * AABB(Vector3(-0.65, 0, -0.215), Vector3(1.30, 2.7, 0.43))


static func _foot_rect(xf: Transform3D) -> Rect2:
	var a := footprint(xf)
	return Rect2(Vector2(a.position.x, a.position.z), Vector2(a.size.x, a.size.z))


static func _load_kit() -> void:
	if not _meshes.is_empty():
		return
	var scene := load("res://assets/models/interior_wall_kit.glb") as PackedScene
	if scene == null:
		return
	var model := scene.instantiate()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh.duplicate() as Mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			material = material.duplicate() as StandardMaterial3D
			var is_wood := material.resource_name == "Display oak"
			if is_wood:
				material.albedo_texture = load("res://assets/textures/pbr/showroom_oak.jpg")
				material.uv1_triplanar = true
				material.uv1_scale = Vector3.ONE * 1.14
			if mi.name != &"WallBay" and material.resource_name in ["Paper pack", "Folded fabric", "Glazed ceramic"]:
				material.vertex_color_use_as_albedo = true
			mesh.surface_set_material(surface, material)
		_meshes[String(mi.name)] = mesh
	model.free()


static func mannequin() -> Mesh:
	_load_kit()
	return _meshes.get("Mannequin")


static func dress(root: Node3D, bays: Array[Transform3D], kind: String, seed: int) -> void:
	if bays.is_empty():
		return
	_load_kit()
	if not _meshes.has("WallBay"):
		return
	_batch(root, "WallBay", bays, [], 72.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, kind])
	var palette: Array = STOCK_PALETTES.get(kind, STOCK_PALETTES["library"])
	var shape := "Fold" if kind in ["fashion", "fitness"] else ("Book" if kind in ["library", "hospitality"] else "Carton")
	var items: Array[Transform3D] = []
	var colours: Array[Color] = []
	var ceramics: Array[Transform3D] = []
	var ceramic_colours: Array[Color] = []
	var columns := 4 if shape == "Fold" else (10 if shape == "Book" else 6)
	for bay in bays:
		for row in 5:
			if kind in ["hospitality", "cafe"] and row % 2 == 0:
				for i in rng.randi_range(1, 3):
					var scale_y := rng.randf_range(0.6, 1.42)
					var offset := Vector3(-0.37 + i * 0.34 + rng.randf_range(-0.065, 0.065), 0.46 + row * 0.48, 0.052)
					ceramics.append(bay * Transform3D(Basis.from_scale(Vector3(1, scale_y, 1)), offset))
					ceramic_colours.append(palette[rng.randi_range(0, palette.size() - 1)])
				continue
			var stocked := rng.randi_range(columns - 2, columns)
			if kind == "hospitality":
				stocked = mini(stocked, rng.randi_range(2, 5))
			if row == 4:
				stocked = maxi(2, stocked - 2)
			for i in stocked:
				var p := Vector3(-0.52 + float(i + 0.5) * 1.04 / columns, 0.46 + row * 0.48, rng.randf_range(0.025, 0.095))
				var size := rng.randf_range(0.84, 1.13)
				var item := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)).scaled(Vector3.ONE * size), p)
				items.append(bay * item)
				colours.append(palette[(row + (i / 2) + rng.randi_range(0, 1)) % palette.size()])
				if shape == "Fold" and row < 4:
					for layer in rng.randi_range(1, 3):
						item.origin.y = p.y + (layer + 1) * 0.058 * size
						items.append(bay * item)
						colours.append(colours[-1])
	_batch(root, shape, items, colours, 34.0)
	if _meshes.has("Vase"):
		_batch(root, "Vase", ceramics, ceramic_colours, 34.0)


static func _batch(root: Node3D, mesh_id: String, offsets: Array[Transform3D], colours: Array[Color], radius: float) -> void:
	if offsets.is_empty():
		return
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = not colours.is_empty()
	instances.mesh = _meshes[mesh_id]
	instances.instance_count = offsets.size()
	for i in offsets.size():
		instances.set_instance_transform(i, offsets[i])
		if instances.use_colors:
			instances.set_instance_color(i, colours[i])
	var node := MultiMeshInstance3D.new()
	node.name = mesh_id
	node.multimesh = instances
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = radius
	node.visibility_range_end_margin = 6.0
	root.add_child(node)


static func tune_light(light: OmniLight3D, energy: float, reach: float) -> void:
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.26
	light.light_specular = 0.42
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 46.0
	light.distance_fade_length = 18.0


## Use the room frame so bounds follow rotated storefronts and home floors.
static func add_lighting_zone(parent: Node3D, bounds: AABB, room_transform := Transform3D.IDENTITY) -> Node3D:
	var zone := Node3D.new()
	zone.name = "InteriorLightingZone"
	zone.transform = room_transform
	zone.set_meta("bounds", bounds)
	zone.add_to_group("interior_lighting_zones")
	parent.add_child(zone)
	return zone


static func camera_weight(tree: SceneTree, camera_position: Vector3) -> float:
	var weight := 0.0
	for zone: Node3D in tree.get_nodes_in_group("interior_lighting_zones"):
		if not zone.is_visible_in_tree() or zone.is_queued_for_deletion():
			continue
		var p := zone.to_local(camera_position)
		var room: AABB = zone.get_meta("bounds")
		var margin := (p - room.position).min(room.end - p)
		weight = maxf(weight, smoothstep(-0.30, 1.20, minf(margin.x, minf(margin.y, margin.z))))
	return weight


static func room_probe(zone: Node3D, tint: Color, ambient_energy: float, reflection: float) -> void:
	var room: AABB = zone.get_meta("bounds")
	var probe := ReflectionProbe.new()
	probe.name = "InteriorBounce"
	probe.position = room.get_center()
	probe.size = room.size
	probe.origin_offset.y = minf(0.0, 1.7 - room.size.y * 0.5)
	probe.interior = true
	probe.box_projection = true
	probe.blend_distance = 0.65
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = tint
	probe.ambient_color_energy = ambient_energy
	probe.intensity = reflection
	probe.max_distance = room.size.length()
	zone.add_child(probe)
