class_name ShopPerson
extends Node3D
## A customer or member of staff inside a shop: the street crowd's
## hero-derived bodies (Crowd.MODEL) with the npc shader (walk cycle,
## carrying pose, head turn, the crowd's palettes), moved along a path at its own pace and turned smoothly.
## A Label3D over the head shows moods ("!" too dear, "?" out of stock, "£"
## paying) for a moment.

const MODEL := Crowd.MODEL
static var _meshes: Array = []
static var _mat_male: ShaderMaterial
static var _mat_female: ShaderMaterial
static var _carry_mats := {}

var speed := 1.25
var _cur_speed := 0.0
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
var blocked_by: Callable           # (pos) -> int : 0 free, 1 someone, 2 the player
var floor_ok: Callable             # (pos) -> bool : walkable (not a fixture)
var floor_height: Callable         # optional (pos) -> local y, for exterior steps
var _wait_t := 0.0
var _excused := false


## The crowd body types (person_0..), sharing the npc shader material without duplicating mesh data.
static func meshes() -> Array:
	if not _meshes.is_empty():
		return _meshes
	var scene: PackedScene = load(MODEL)
	if scene == null:
		return _meshes
	var inst := scene.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	mis.sort_custom(func(a, b):
		var na := int(String(a.name).trim_prefix("person_"))
		var nb := int(String(b.name).trim_prefix("person_"))
		return na < nb)
	var sh: Shader = load("res://src/empire/npc/npc.gdshader")
	_mat_male = ShaderMaterial.new()
	_mat_male.shader = sh
	_mat_male.set_shader_parameter("pivot_k", 1.0)
	_mat_female = ShaderMaterial.new()
	_mat_female.shader = sh
	_mat_female.set_shader_parameter("pivot_k", 0.925)
	for mi in mis:
		_meshes.append((mi as MeshInstance3D).mesh)
	inst.free()
	return _meshes


static func clear_cache() -> void:
	_meshes.clear()
	_mat_male = null
	_mat_female = null
	_carry_mats.clear()


static func base_mesh() -> Mesh:
	var ms := meshes()
	return ms[0] if not ms.is_empty() else null


func _init(seed := 0, staff := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_mi = MeshInstance3D.new()
	var ms := meshes()
	# Staff: the plain body (the apron goes over its top); shoppers any of them.
	var body_idx := 0 if staff else (rng.randi() % maxi(ms.size(), 1))
	if not ms.is_empty():
		_mi.mesh = ms[body_idx]
		_mi.material_override = _mat_female if (body_idx % 2 == 1) else _mat_male
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


## Staff uniform by the business's level (Growth): an independent's
## staff wear a white top and the green apron; an established business
## puts them in your brand's apron; a major retailer or flagship in a
## brand-coloured top (no apron – a proper uniform).
func set_uniform(level: int, cols: Array) -> void:
	var prim: Color = cols[0]
	var acc: Color = cols[1]
	if level >= 3:
		_mi.set_instance_shader_parameter("shirt", prim)
		_mi.set_instance_shader_parameter("apron", 0.0)
	elif level == 2:
		_mi.set_instance_shader_parameter("shirt", Color(0.94, 0.94, 0.92) if prim.get_luminance() < 0.6 else acc)
		_mi.set_instance_shader_parameter("apron", 1.0)
		_mi.set_instance_shader_parameter("apron_col", Vector3(prim.r, prim.g, prim.b))


func _floor_ok(at: Vector3) -> bool:
	return not floor_ok.is_valid() or floor_ok.call(at)


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
		var is_fem := _mi != null and _mi.material_override == _mat_female
		var sc := _mi.scale if _mi != null else Vector3.ONE
		carry_box.position = Vector3(0.0, 1.08 * sc.y * (0.925 if is_fem else 1.0), -0.38 * sc.z)
		carry_box.scale = Vector3.ONE * 0.85
		add_child(carry_box)
	if carry_box:
		carry_box.visible = on
		if on:
			carry_box.material_override = _carry_mat(colour)


static func _carry_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_rgba32()
	if _carry_mats.has(key):
		return _carry_mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	_carry_mats[key] = m
	return m


func _enter_tree() -> void:
	add_to_group("door_openers")  # staff through the stockroom door


func _process(dt: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= dt
		if _bubble_t <= 0.0:
			_bubble.text = ""
	var target_speed := 0.0
	var mv := Vector3.ZERO
	if _pi < path.size():
		var tgt := path[_pi]
		var to := tgt - position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.12:
			_pi += 1
		else:
			var dir := to / dist
			var ahead := position + dir * minf(0.5, dist + 0.3)
			var move_dir := dir
			var speed_scale := 1.0
			# Ease gently into the final stop instead of snapping to zero.
			if _pi == path.size() - 1 and dist < 0.45:
				speed_scale = lerpf(0.35, 1.0, clampf(dist / 0.45, 0.0, 1.0))
			var who: int = int(blocked_by.call(ahead)) if blocked_by.is_valid() else 0
			if who != 0:
				# Someone in the way: step to the left of them (as on the
				# pavement) if that's free, else wait. Two people face to
				# face both stepping left pass; after a second a stuck one
				# tries the right; after a few, in a narrow aisle, they
				# squeeze past ("excuse me") rather than stand there for ever.
				var left := Vector3(dir.z, 0.0, -dir.x)
				var side_at := position + (dir * 0.25 + left * 0.45)
				_wait_t += dt
				if int(blocked_by.call(side_at)) == 0 and _floor_ok(side_at):
					move_dir = (dir * 0.35 + left * 0.65).normalized()
					speed_scale = 0.6
				elif _wait_t > 1.0 and int(blocked_by.call(position - left * 0.45)) == 0 and _floor_ok(position - left * 0.45):
					move_dir = -left
					speed_scale = 0.5
				elif _wait_t > (2.5 if who == 1 else 3.5):
					move_dir = dir
					speed_scale = 0.35
					if who == 2 and not _excused:
						_excused = true
						say("Excuse me", Color(0.9, 0.9, 0.95), 1.4)
				else:
					speed_scale = 0.0
			else:
				_wait_t = maxf(_wait_t - dt * 2.0, 0.0)
				_excused = false
			target_speed = speed * speed_scale
			var accel := 5.4 if target_speed < _cur_speed else 4.2
			_cur_speed = move_toward(_cur_speed, target_speed, dt * accel)
			var step_len := _cur_speed * dt
			if speed_scale > 0.0 or _cur_speed > 0.01:
				mv = move_dir * (minf(step_len, dist) if move_dir == dir else step_len)
				if move_dir == dir or _floor_ok(position + mv):
					position += mv
				else:
					mv = Vector3.ZERO
					_cur_speed = 0.0
			_yaw_goal = atan2(-to.x, -to.z)
	else:
		_cur_speed = move_toward(_cur_speed, 0.0, dt * 6.0)
		if face_goal != Vector3.INF:
			var f := face_goal - position
			if Vector2(f.x, f.z).length() > 0.05:
				_yaw_goal = atan2(-f.x, -f.z)
	if floor_height.is_valid():
		position.y = move_toward(position.y, float(floor_height.call(position)), dt * 2.4)
	var actual_dist := mv.length()
	var target_walk := clampf(_cur_speed / maxf(speed, 0.25), 0.0, 1.0)
	walk = lerpf(walk, target_walk, 1.0 - exp(-(7.0 if target_walk < walk else 5.5) * dt))
	if walk < 0.01 and target_walk <= 0.0:
		walk = 0.0
	if actual_dist > 0.0004:
		stride += actual_dist / maxf(walk, 0.42)
	rotation.y = lerp_angle(rotation.y, _yaw_goal, 1.0 - exp(-dt * 9.0))
	_mi.set_instance_shader_parameter("stride", stride)
	_mi.set_instance_shader_parameter("walk", walk)
	_mi.set_instance_shader_parameter("carry", carry)
	if carry_box and carry > 0.5:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		carry_box.visible = cam == null or cam.global_position.distance_squared_to(global_position + Vector3(0.0, 0.9, 0.0)) > 1.44
