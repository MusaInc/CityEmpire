class_name ShopPerson
extends Node3D
## A customer or member of staff inside a shop: the street crowd's
## hero-derived bodies (Crowd.MODEL) with the npc shader (walk cycle,
## carrying pose, head turn, the crowd's palettes), moved along a path at its own pace and turned smoothly.
## A Label3D over the head shows moods ("!" too dear, "?" out of stock, "£"
## paying) for a moment.

const MODEL := Crowd.MODEL
static var _meshes: Array = []
static var _mat: ShaderMaterial

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


## The crowd body types (person_0..), sharing the npc shader material.
static func meshes() -> Array:
	if not _meshes.is_empty():
		return _meshes
	var scene: PackedScene = load(MODEL)
	if scene == null:
		return _meshes
	var inst := scene.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	mis.sort_custom(func(a, b): return String(a.name) < String(b.name))
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/empire/npc/npc.gdshader")
	for mi in mis:
		var m: Mesh = (mi as MeshInstance3D).mesh.duplicate()
		m.surface_set_material(0, _mat)
		_meshes.append(m)
	inst.free()
	return _meshes


static func base_mesh() -> Mesh:
	var ms := meshes()
	return ms[0] if not ms.is_empty() else null


func _init(seed := 0, staff := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_mi = MeshInstance3D.new()
	var ms := meshes()
	# Staff: the plain body (the apron goes over its top); shoppers any of them.
	if not ms.is_empty():
		_mi.mesh = ms[0] if staff else ms[rng.randi() % ms.size()]
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s := rng.randf_range(0.94, 1.06)
	_mi.scale = Vector3(s, s * rng.randf_range(0.95, 1.06), s)
	add_child(_mi)
	# Same palettes as the street crowd (Crowd.TOPS + the shader's seed).
	_mi.set_instance_shader_parameter("seed", rng.randf())
	_mi.set_instance_shader_parameter("shirt", Color(0.92, 0.92, 0.9) if staff else Crowd.TOPS[rng.randi() % Crowd.TOPS.size()])
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
