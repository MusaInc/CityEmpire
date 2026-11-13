class_name ShopPerson
extends Node3D
## A customer or member of staff inside a shop: the city's pedestrian model
## with the npc shader (walk cycle, carrying pose, head turn, per-person
## colours), moved along a path at its own pace and turned smoothly.
## A Label3D over the head shows moods ("!" too dear, "?" out of stock, "£"
## paying) for a moment.

const MODEL := "res://assets/models/pedestrian.glb"
static var _mesh: Mesh
static var _mats := {}

var speed := 1.25
var path := PackedVector3Array()   # parent-space points
var _pi := 0
var stride := 0.0
var walk := 0.0
var carry := 0.0
var carry_box: MeshInstance3D
var _mi: MeshInstance3D
var _bubble: Label3D
var _bubble_t := 0.0
var _yaw_goal := 0.0
var face_goal := Vector3.INF       # look at this (parent space) when standing
var blocked_by: Callable           # (pos) -> bool : someone's in the way


static func base_mesh() -> Mesh:
	if _mesh:
		return _mesh
	var scene: PackedScene = load(MODEL)
	if scene == null:
		return null
	var inst := scene.instantiate()
	var found: MeshInstance3D = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		found = n
		break
	if found:
		_mesh = found.mesh.duplicate()
		var sh: Shader = load("res://src/empire/npc/npc.gdshader")
		for i in _mesh.get_surface_count():
			var src := _mesh.surface_get_material(i)
			var nm := String(src.resource_name) if src else ""
			var part: int = {"skin": 1, "pants": 2, "hair": 3, "shirt": 4}.get(nm, 0)
			if not _mats.has(part):
				var sm := ShaderMaterial.new()
				sm.shader = sh
				sm.set_shader_parameter("part", part)
				_mats[part] = sm
			_mesh.surface_set_material(i, _mats[part])
	inst.free()
	return _mesh


func _init(seed := 0, staff := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_mi = MeshInstance3D.new()
	_mi.mesh = base_mesh()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s := rng.randf_range(0.94, 1.06)
	_mi.scale = Vector3(s, s * rng.randf_range(0.95, 1.06), s)
	add_child(_mi)
	var skins := [Color(0.95, 0.78, 0.65), Color(0.85, 0.64, 0.5), Color(0.68, 0.48, 0.34), Color(0.5, 0.34, 0.24),
		Color(0.33, 0.22, 0.16)]
	var hairs := [Color(0.07, 0.06, 0.05), Color(0.24, 0.15, 0.09), Color(0.42, 0.28, 0.16), Color(0.78, 0.64, 0.38),
		Color(0.62, 0.6, 0.58)]
	var pants := [Color(0.16, 0.18, 0.26), Color(0.1, 0.1, 0.11), Color(0.28, 0.36, 0.5), Color(0.62, 0.56, 0.44),
		Color(0.34, 0.33, 0.33)]
	_mi.set_instance_shader_parameter("skin", skins[rng.randi() % skins.size()])
	_mi.set_instance_shader_parameter("hair", hairs[rng.randi() % hairs.size()])
	_mi.set_instance_shader_parameter("trousers", pants[rng.randi() % pants.size()])
	_mi.set_instance_shader_parameter("shirt", Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.7), rng.randf_range(0.35, 0.9)))
	_mi.set_instance_shader_parameter("apron", 1.0 if staff else 0.0)
	speed = rng.randf_range(1.05, 1.4) * (1.15 if staff else 1.0)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 64
	_bubble.pixel_size = 0.006
	_bubble.position = Vector3(0, 2.15, 0)
	_bubble.outline_size = 12
	_bubble.no_depth_test = false
	add_child(_bubble)


func set_path(p: PackedVector3Array) -> void:
	path = p
	_pi = 0


func arrived() -> bool:
	return _pi >= path.size()


func say(text: String, col := Color.WHITE, secs := 1.6) -> void:
	_bubble.text = text
	_bubble.modulate = col
	_bubble_t = secs


func set_carry(on: bool, colour := Color(0.7, 0.55, 0.35)) -> void:
	carry = 1.0 if on else 0.0
	if on and carry_box == null:
		carry_box = MeshInstance3D.new()
		carry_box.mesh = ShopInterior.shape_mesh("case")
		carry_box.material_override = ShopInterior._mat("goods")
		carry_box.position = Vector3(0, 1.08, -0.38)
		carry_box.scale = Vector3.ONE * 0.85
		add_child(carry_box)
	if carry_box:
		carry_box.visible = on
		if on:
			carry_box.material_override = _carry_mat(colour)


static func _carry_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _process(dt: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= dt
		if _bubble_t <= 0.0:
			_bubble.text = ""
	var moving := false
	if _pi < path.size():
		var tgt := path[_pi]
		var to := tgt - position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.12:
			_pi += 1
		else:
			var step := speed * dt
			var ahead := position + to / dist * minf(0.45, dist)
			if blocked_by.is_valid() and blocked_by.call(ahead):
				step *= 0.15  # someone in the way: shuffle, don't stop dead
			position += to / dist * minf(step, dist)
			stride += minf(step, dist)
			_yaw_goal = atan2(-to.x, -to.z)
			moving = true
	elif face_goal != Vector3.INF:
		var f := face_goal - position
		if Vector2(f.x, f.z).length() > 0.05:
			_yaw_goal = atan2(-f.x, -f.z)
	walk = move_toward(walk, 1.0 if moving else 0.0, dt * 4.0)
	rotation.y = lerp_angle(rotation.y, _yaw_goal, 1.0 - exp(-dt * 9.0))
	_mi.set_instance_shader_parameter("stride", stride)
	_mi.set_instance_shader_parameter("walk", walk)
	_mi.set_instance_shader_parameter("carry", carry)
