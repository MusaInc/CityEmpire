class_name VehicleFx
extends Node3D
## All vehicle effects, pooled and drawn in a handful of MultiMeshes (so 30
## cars cost the same draw calls as one):
##   smoke    tyre smoke, engine smoke and spray from wet roads
##   sparks   impacts, metal scraping walls, rims on shredded tyres
##   fire     a badly damaged engine (health < 20 %)
##   skids    dark tyre marks laid on the road (ring buffer)
##   debris   small physical chunks thrown off in heavy crashes (pooled,
##            budgeted by quality, cleaned up after a few seconds)
## Particles are integrated on the CPU in packed arrays and written to the
## MultiMesh buffer once per frame; the billboard happens in the shader.
## Works the same on the Mobile and Compatibility (web) renderers.

const SHADER := preload("res://src/fx/particle.gdshader")
const RIPPLE_SHADER := preload("res://src/fx/water_ripple.gdshader")

class Pool:
	var mm: MultiMesh
	var node: MultiMeshInstance3D
	var n := 0
	var pos: PackedVector3Array
	var vel: PackedVector3Array
	var life: PackedFloat32Array
	var max_life: PackedFloat32Array
	var size0: PackedFloat32Array
	var size1: PackedFloat32Array
	var col: PackedColorArray
	var next := 0
	var drag := 1.0
	var gravity := 0.0
	var buf: PackedFloat32Array

	func _init(count: int, mat: Material, parent: Node3D) -> void:
		n = count
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = n
		node = MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin = 2000.0
		parent.add_child(node)
		pos.resize(n)
		vel.resize(n)
		life.resize(n)
		max_life.resize(n)
		size0.resize(n)
		size1.resize(n)
		col.resize(n)
		buf.resize(n * 16)
		life.fill(0.0)
		max_life.fill(1.0)

	func emit(p: Vector3, v: Vector3, l: float, s0: float, s1: float, c: Color) -> void:
		var i := next
		next = (next + 1) % n
		pos[i] = p
		vel[i] = v
		life[i] = l
		max_life[i] = l
		size0[i] = s0
		size1[i] = s1
		col[i] = c

	func step(dt: float) -> void:
		var damp := exp(-drag * dt)
		for i in n:
			var l := life[i]
			var o := i * 16
			if l <= 0.0:
				buf[o] = 0.0
				buf[o + 5] = 0.0
				buf[o + 10] = 0.0
				buf[o + 3] = 0.0
				buf[o + 7] = -9999.0
				buf[o + 11] = 0.0
				buf[o + 15] = 0.0
				continue
			l -= dt
			life[i] = l
			var v := vel[i] * damp
			v.y -= gravity * dt
			vel[i] = v
			var p := pos[i] + v * dt
			pos[i] = p
			var k := 1.0 - clampf(l / max_life[i], 0.0, 1.0)
			var s := lerpf(size0[i], size1[i], k)
			var c := col[i]
			# Basis is a uniform scale (the shader billboards it).
			buf[o] = s
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 3] = p.x
			buf[o + 4] = 0.0
			buf[o + 5] = s
			buf[o + 6] = 0.0
			buf[o + 7] = p.y
			buf[o + 8] = 0.0
			buf[o + 9] = 0.0
			buf[o + 10] = s
			buf[o + 11] = p.z
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = c.a * (1.0 - k)
		mm.buffer = buf


var cars: Array = []           # Car list provided by the game each frame
var smoke: Pool
var sparks: Pool
var fire: Pool
var _rip_mm: MultiMesh
var _rip_buf: PackedFloat32Array
var _rip_pos: PackedVector3Array
var _rip_life: PackedFloat32Array
var _rip_max: PackedFloat32Array
var _rip_r0: PackedFloat32Array
var _rip_r1: PackedFloat32Array
var _rip_alpha: PackedFloat32Array
var _rip_next := 0
const RIP_N := 28
var _wade_t := 0.0
var skid_mesh: ArrayMesh
var _skid_i := 0
var _skid_n := 1400
var _skid_last := {}           # car id * 4 + wheel -> [last position, left edge, right edge]
var _skid_pos := PackedVector3Array()
var _skid_uv := PackedVector2Array()
var _skid_idx := PackedInt32Array()
var _skid_dirty := false
var _skid_upload := 0.0
var debris_budget := 48
var _debris: Array = []        # [RigidBody3D, age]
var _debris_mesh: BoxMesh
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _spray_rng := RandomNumberGenerator.new()
var _spray_interval := 0.0


func _ready() -> void:
	var st := get_node_or_null("/root/Settings")
	if st:
		debris_budget = int(st.preset().get("debris", 32))
	smoke = Pool.new(260, _mat(false, 0.85), self)
	smoke.drag = 1.6
	smoke.gravity = -0.6
	sparks = Pool.new(180, _mat(true, 1.0), self)
	sparks.drag = 0.6
	sparks.gravity = 9.0
	fire = Pool.new(60, _mat(true, 1.0), self)
	fire.drag = 2.0
	fire.gravity = -3.0
	# Pooled horizontal expanding water-surface ripple & foam rings (1 draw call).
	_rip_mm = MultiMesh.new()
	_rip_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rip_mm.use_colors = true
	var rq := PlaneMesh.new()
	rq.size = Vector2(2.0, 2.0)
	_rip_mm.mesh = rq
	_rip_mm.instance_count = RIP_N
	var rmat := ShaderMaterial.new()
	rmat.shader = RIPPLE_SHADER
	var rnode := MultiMeshInstance3D.new()
	rnode.multimesh = _rip_mm
	rnode.material_override = rmat
	rnode.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rnode.extra_cull_margin = 2000.0
	add_child(rnode)
	_rip_pos.resize(RIP_N)
	_rip_life.resize(RIP_N)
	_rip_max.resize(RIP_N)
	_rip_r0.resize(RIP_N)
	_rip_r1.resize(RIP_N)
	_rip_alpha.resize(RIP_N)
	_rip_buf.resize(RIP_N * 16)
	_rip_life.fill(0.0)
	_rip_max.fill(1.0)
	# Skid marks: continuous ribbons (one ArrayMesh, a ring buffer of quads;
	# each quad starts on the previous one's end edge, so a trail has no gaps
	# at bends and no darker overlaps), feathered at the sides.
	_skid_pos.resize(_skid_n * 4)
	_skid_uv.resize(_skid_n * 4)
	_skid_idx.resize(_skid_n * 6)
	for i in _skid_n:
		for k in 4:
			_skid_pos[i * 4 + k] = Vector3(0, -9999, 0)
			_skid_uv[i * 4 + k] = Vector2(float(k % 2), 0.0)
		for k in 6:
			_skid_idx[i * 6 + k] = i * 4 + [0, 2, 1, 1, 2, 3][k]
	skid_mesh = ArrayMesh.new()
	var sk := MeshInstance3D.new()
	sk.mesh = skid_mesh
	var skm := StandardMaterial3D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.02, 0.02, 0.0))
	grad.set_color(1, Color(0.02, 0.02, 0.02, 0.0))
	grad.add_point(0.22, Color(0.02, 0.02, 0.02, 0.6))
	grad.add_point(0.78, Color(0.02, 0.02, 0.02, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 32
	gt.height = 1
	skm.albedo_texture = gt
	skm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skm.roughness = 0.9
	skm.cull_mode = BaseMaterial3D.CULL_DISABLED
	skm.render_priority = -1
	sk.material_override = skm
	sk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sk.extra_cull_margin = 2000.0
	add_child(sk)
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3(0.35, 0.06, 0.25)


func _mat(additive: bool, alpha: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("additive", additive)
	m.set_shader_parameter("alpha", alpha)
	m.render_priority = 1
	return m


func _process(dt: float) -> void:
	_t += dt
	_skid_flush(dt)
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	for o in cars:
		# (Untyped: a car freed this frame, e.g. the old player after a car
		# switch, must be skipped, not assigned to a typed variable.)
		if not is_instance_valid(o):
			continue
		var c := o as Car
		if not c.visible or c.freeze:
			continue
		if c.global_position.distance_squared_to(cp) > 160.0 * 160.0:
			continue
		_car_fx(c, dt)
	smoke.step(dt)
	sparks.step(dt)
	fire.step(dt)
	_step_ripples(dt)
	# Debris lifetime.
	var keep: Array = []
	for d in _debris:
		d[1] += dt
		var b: RigidBody3D = d[0]
		if d[1] > 7.0 or b.global_position.y < -50.0:
			b.queue_free()
		else:
			keep.append(d)
	_debris = keep


## Reuse the smoke batch for short, cool-coloured tyre mist. The caller
## supplies a paved-surface check because suspension also hits grass,
## roofs and the seabed.
func wet_tyre_spray(c: Car, wetness: float, dt: float, paved_at: Callable) -> void:
	var velocity := c.linear_velocity.slide(Vector3.UP)
	var strength := smoothstep(0.18, 0.83, wetness) * smoothstep(5.0, 24.0, velocity.length())
	if strength < 0.025 or c.in_water or c.wheels_on_ground < 1 or c.global_basis.y.y < 0.55:
		_spray_interval = 0.0
		return
	var frame_time := minf(dt, 0.10)
	_spray_interval -= frame_time
	if _spray_interval > 0.0:
		return
	var interval := lerpf(0.115, 0.033, strength)
	var lag := minf(-_spray_interval, frame_time)
	var bursts := mini(3, floori(lag / interval) + 1)
	_spray_interval = maxf(interval * bursts - lag, 0.0)
	var reversing := c.global_basis.z.dot(velocity) > 0.0
	var axle := 0 if reversing else 2
	for side in 2:
		var wheel := axle + side
		if not c.wheel_contact(wheel):
			continue
		var contact := c.wheel_contact_point(wheel)
		if contact.distance_squared_to(c.global_position) > 36.0 or not paved_at.call(contact):
			continue
		var outward := c.global_basis.x * (-1.0 if side == 0 else 1.0)
		for burst in bursts:
			# Spread low-frame-rate emissions along the wheel's travel
			# instead of stacking several quads at the latest contact.
			var offset := lag - float(burst) * interval
			_emit_tyre_spray(contact - velocity * offset, velocity, outward, strength)


func _emit_tyre_spray(contact: Vector3, velocity: Vector3, outward: Vector3, strength: float) -> void:
	var at := contact + outward * 0.08 + Vector3.UP * 0.08
	var drift := velocity * 0.52 + outward * _spray_rng.randf_range(0.28, 0.72)
	drift.y = _spray_rng.randf_range(0.32, 0.72) * (0.68 + 0.32 * strength)
	var mist := Color(0.56, 0.64, 0.70, lerpf(0.09, 0.24, strength))
	smoke.emit(at, drift, _spray_rng.randf_range(0.26, 0.44), 0.16,
		_spray_rng.randf_range(0.48, 0.78) * (0.72 + 0.28 * strength), mist)
	if strength > 0.35:
		# Tight fine-droplet rooster tail close to the road surface.
		var drops := drift * 0.68 + outward * 0.26
		drops.y *= 0.48
		smoke.emit(at + outward * 0.06, drops, 0.19, 0.07, 0.18,
			Color(0.68, 0.76, 0.82, 0.26 * strength))


func _car_fx(c: Car, dt: float) -> void:
	var xf := c.global_transform
	var sp := c.speed
	var id := c.get_instance_id()
	for i in 4:
		var slip := c.wheel_slip[i]
		if not c.wheel_contact(i):
			_skid_last.erase(id * 4 + i)
			continue
		var p := c.wheel_contact_point(i)
		if slip > 0.35 and sp > 4.0:
			if _rng.randf() < slip * dt * 30.0:
				# Distinguish wet-road spray mist from dry-road rubber tyre smoke.
				var wet := clampf(CarVisual.visible_wetness, 0.0, 1.0)
				var v := -c.linear_velocity * lerpf(0.1, 0.22, wet) + Vector3(_rng.randf_range(-1.4, 1.4), _rng.randf_range(0.3, 1.0), _rng.randf_range(-1.4, 1.4))
				var g := _rng.randf_range(0.8, 0.9)
				var dry_col := Color(g, g * 0.99, g * 0.97, 0.24 * slip)
				var wet_col := Color(0.58, 0.66, 0.73, 0.18 * slip)
				smoke.emit(p + Vector3.UP * lerpf(0.25, 0.14, wet), v, _rng.randf_range(lerpf(1.0, 0.35, wet), lerpf(1.7, 0.65, wet)),
					lerpf(0.6, 0.24, wet), lerpf(2.4 + slip * 1.2, 0.95 + slip * 0.5, wet), dry_col.lerp(wet_col, wet))
			_skid(id * 4 + i, p, c.linear_velocity, slip)
		else:
			_skid_last.erase(id * 4 + i)
		if c.puncture > 0.0 and sp > 6.0 and _rng.randf() < dt * 25.0:
			sparks.emit(p + Vector3.UP * 0.05, -c.linear_velocity * 0.2 + Vector3(_rng.randf_range(-2, 2), _rng.randf_range(1, 3), _rng.randf_range(-2, 2)),
				0.35, 0.08, 0.02, Color(1.0, 0.7, 0.3, 1.0))
	# Engine smoke / fire.
	var hood := xf * Vector3(0, (c.spec["size"] as Vector3).y * 0.75, -(c.spec["size"] as Vector3).z * 0.32)
	if c.health < 0.55 and _rng.randf() < dt * (5.0 + (0.55 - c.health) * 26.0):
		# Thin wisps at first, darker as the engine gets worse; they stream
		# back with the car's speed instead of hanging in front of the camera.
		var dark := clampf(0.55 - c.health, 0.0, 0.5)
		var g2 := 0.5 - dark * 0.7
		smoke.emit(hood, Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(1.0, 2.0), _rng.randf_range(-0.3, 0.3)) - c.linear_velocity * 0.25,
			_rng.randf_range(1.0, 1.8), 0.35, 1.6 + dark * 1.2, Color(g2, g2, g2 * 1.03, 0.2 + dark * 0.6))
	if c.health < 0.2 and _rng.randf() < dt * 30.0:
		fire.emit(hood + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3)), Vector3(0, _rng.randf_range(1.5, 3.0), 0),
			_rng.randf_range(0.3, 0.6), 0.5, 0.15, Color(1.0, _rng.randf_range(0.35, 0.6), 0.1, 1.0))
	# Scraping: sparks off the side.
	if c.scraping > 0.3 and sp > 5.0 and _rng.randf() < dt * 40.0 * c.scraping:
		var side := xf.basis.x * (1.0 if _rng.randf() < 0.5 else -1.0) * (c.spec["size"] as Vector3).x * 0.5
		sparks.emit(c.global_position + side + Vector3.UP * 0.5, -c.linear_velocity * 0.3 + Vector3(_rng.randf_range(-3, 3), _rng.randf_range(1, 4), _rng.randf_range(-3, 3)),
			0.4, 0.1, 0.02, Color(1.0, 0.75, 0.35, 1.0))


func _skid(key: int, p: Vector3, v: Vector3, slip: float) -> void:
	var last: Array = _skid_last.get(key, [])
	var hw := 0.12 * clampf(0.6 + slip, 0.6, 1.3)
	if not last.is_empty() and (last[0] as Vector3).distance_to(p) < 0.45:
		return
	if last.is_empty() or (last[0] as Vector3).distance_to(p) > 3.0:
		# A new trail: its first edge, square to the way the car is going.
		var f0 := Vector3(v.x, 0.0, v.z).normalized() if Vector3(v.x, 0.0, v.z).length() > 0.5 else Vector3.FORWARD
		var r0 := f0.cross(Vector3.UP).normalized()
		_skid_last[key] = [p, p - r0 * hw + Vector3.UP * 0.03, p + r0 * hw + Vector3.UP * 0.03]
		return
	var d := p - (last[0] as Vector3)
	var fwd := Vector3(d.x, 0.0, d.z).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var l1 := p - right * hw + Vector3.UP * 0.03
	var r1 := p + right * hw + Vector3.UP * 0.03
	var j := _skid_i * 4
	_skid_pos[j] = last[1]
	_skid_pos[j + 1] = last[2]
	_skid_pos[j + 2] = l1
	_skid_pos[j + 3] = r1
	_skid_i = (_skid_i + 1) % _skid_n
	_skid_last[key] = [p, l1, r1]
	_skid_dirty = true


## Uploads the skid ribbons when they changed (at most 12 times a second).
func _skid_flush(dt: float) -> void:
	_skid_upload -= dt
	if not _skid_dirty or _skid_upload > 0.0:
		return
	_skid_upload = 0.08
	_skid_dirty = false
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _skid_pos
	arr[Mesh.ARRAY_TEX_UV] = _skid_uv
	var nrm := PackedVector3Array()
	nrm.resize(_skid_pos.size())
	nrm.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = _skid_idx
	skid_mesh.clear_surfaces()
	skid_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


## A hit: sparks, a puff of dust/debris, chunks off the car for big ones.
func impact(at: Vector3, normal: Vector3, strength: float, paint: Color) -> void:
	var n := int(clampf(strength * 1.2, 4.0, 40.0))
	for i in n:
		var v := (normal * _rng.randf_range(1.0, 4.0) + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 1.5), _rng.randf_range(-1, 1)) * strength * 0.25)
		sparks.emit(at, v, _rng.randf_range(0.25, 0.6), 0.12, 0.03, Color(1.0, _rng.randf_range(0.6, 0.85), 0.35, 1.0))
	for i in int(clampf(strength * 0.3, 1.0, 8.0)):
		smoke.emit(at + Vector3(_rng.randf_range(-0.5, 0.5), 0.2, _rng.randf_range(-0.5, 0.5)),
			Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 1.5), _rng.randf_range(-1, 1)), 1.0, 0.7, 2.2, Color(0.55, 0.53, 0.5, 0.28))
	if strength > 10.0:
		for i in int(clampf((strength - 8.0) * 0.4, 1.0, 6.0)):
			_chunk(at, normal, strength, paint if i % 2 == 0 else Color(0.05, 0.05, 0.06))


func _chunk(at: Vector3, normal: Vector3, strength: float, col: Color) -> void:
	if _debris.size() >= debris_budget:
		var old: Array = _debris.pop_front()
		(old[0] as Node).queue_free()
	var b := RigidBody3D.new()
	b.collision_layer = 1 << 5
	b.collision_mask = 1 | (1 << 3)
	b.mass = 3.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = _debris_mesh.size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _debris_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.4
	m.roughness = 0.4
	mi.material_override = m
	mi.scale = Vector3.ONE * _rng.randf_range(0.6, 1.6)
	b.add_child(mi)
	add_child(b)
	b.global_position = at + normal * 0.3 + Vector3.UP * 0.3
	b.linear_velocity = normal * _rng.randf_range(2, 6) + Vector3(_rng.randf_range(-3, 3), _rng.randf_range(2, 6), _rng.randf_range(-3, 3)) * clampf(strength / 20.0, 0.5, 2.0)
	b.angular_velocity = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
	_debris.append([b, 0.0])


func emit_ripple(at: Vector3, r0: float, r1: float, life: float, alpha := 0.72) -> void:
	if _rip_mm == null:
		return
	var i := _rip_next
	_rip_next = (_rip_next + 1) % RIP_N
	_rip_pos[i] = Vector3(at.x, Car.WATER_Y + 0.06, at.z)
	_rip_life[i] = life
	_rip_max[i] = maxf(life, 0.05)
	_rip_r0[i] = r0
	_rip_r1[i] = r1
	_rip_alpha[i] = alpha


func _step_ripples(dt: float) -> void:
	if _rip_mm == null:
		return
	for i in RIP_N:
		var l := _rip_life[i]
		var o := i * 16
		if l <= 0.0:
			_rip_buf[o] = 0.0; _rip_buf[o + 5] = 0.0; _rip_buf[o + 10] = 0.0
			_rip_buf[o + 3] = 0.0; _rip_buf[o + 7] = -9999.0; _rip_buf[o + 11] = 0.0
			_rip_buf[o + 15] = 0.0
			continue
		l -= dt
		_rip_life[i] = l
		var k := 1.0 - clampf(l / _rip_max[i], 0.0, 1.0)
		var ease_k := 1.0 - pow(1.0 - k, 2.2)
		var r := lerpf(_rip_r0[i], _rip_r1[i], ease_k)
		var p := _rip_pos[i]
		_rip_buf[o] = r; _rip_buf[o + 1] = 0.0; _rip_buf[o + 2] = 0.0; _rip_buf[o + 3] = p.x
		_rip_buf[o + 4] = 0.0; _rip_buf[o + 5] = 1.0; _rip_buf[o + 6] = 0.0; _rip_buf[o + 7] = p.y
		_rip_buf[o + 8] = 0.0; _rip_buf[o + 9] = 0.0; _rip_buf[o + 10] = r; _rip_buf[o + 11] = p.z
		_rip_buf[o + 12] = 0.92; _rip_buf[o + 13] = 0.96; _rip_buf[o + 14] = 1.0
		_rip_buf[o + 15] = _rip_alpha[i] * (1.0 - k) * (1.0 - k)
	_rip_mm.buffer = _rip_buf


## Physically scaled water-entry splash for characters (obj_scale ~0.3–0.65)
## and vehicles (obj_scale ~1.0–1.6): plume spray, droplets, surface foam, and
## expanding concentric water ripples.
func splash(at: Vector3, speed: float, obj_scale := 1.0) -> void:
	var sc := clampf(obj_scale, 0.25, 1.8)
	var sp := clampf(speed / 15.0, 0.25, 1.7)
	var k := clampf(sp * sc, 0.22, 2.0)
	var water_p := Vector3(at.x, Car.WATER_Y + 0.08, at.z)
	# Expanding surface ripple & foam rings.
	emit_ripple(water_p, 0.55 * sc, (3.2 + 3.6 * k) * sc, lerpf(1.4, 2.6, clampf(k * 0.6, 0.0, 1.0)), clampf(0.45 + 0.35 * k, 0.45, 0.85))
	if k > 0.45:
		emit_ripple(water_p, 0.35 * sc, (2.1 + 2.4 * k) * sc, lerpf(1.1, 2.1, clampf(k * 0.5, 0.0, 1.0)), clampf(0.35 + 0.28 * k, 0.35, 0.72))
	# Upward & outward water spray plume.
	var plume_n := clampi(int(20.0 * k) + 6, 6, 46)
	for i in plume_n:
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(0.15, 1.35) * sc
		var out_v := Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(1.0, 4.6) * k
		var up_v := Vector3.UP * _rng.randf_range(2.2, 7.6) * k
		smoke.emit(water_p + Vector3(cos(ang) * rad, 0.12, sin(ang) * rad), out_v + up_v,
			_rng.randf_range(0.55, 1.35), 0.45 * sc, (1.35 + 1.15 * k) * sc, Color(0.86, 0.93, 0.97, clampf(0.42 + 0.25 * k, 0.42, 0.72)))
	# Low floating foam collar on the surface.
	var foam_n := clampi(int(10.0 * sc) + 3, 4, 18)
	for i in foam_n:
		var ang := _rng.randf() * TAU
		var rad := _rng.randf_range(0.25, 1.6) * sc
		smoke.emit(water_p + Vector3(cos(ang) * rad, 0.05, sin(ang) * rad),
			Vector3(cos(ang), 0.05, sin(ang)) * _rng.randf_range(0.5, 2.2) * k,
			_rng.randf_range(0.9, 1.8), 0.65 * sc, 1.8 * sc, Color(0.92, 0.97, 1.0, 0.46))
	# High-velocity arcing water droplets.
	var drop_n := clampi(int(18.0 * k) + 5, 5, 40)
	for i in drop_n:
		var ang := _rng.randf() * TAU
		var v := Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(1.2, 5.2) * k + Vector3.UP * _rng.randf_range(3.2, 9.2) * k
		sparks.emit(water_p + Vector3.UP * 0.2, v, _rng.randf_range(0.45, 0.95), 0.09 * maxf(sc, 0.6), 0.03, Color(0.84, 0.93, 1.0, 0.85))


## Continuous wake ripples & small splashes while a character or vehicle moves in water.
func water_disturb(at: Vector3, vel: Vector3, obj_scale := 0.4, dt := 0.016) -> void:
	var spd := Vector2(vel.x, vel.z).length()
	if spd < 0.45:
		return
	_wade_t -= dt
	if _wade_t > 0.0:
		return
	_wade_t = clampf(0.28 / maxf(spd * 0.25, 0.5), 0.09, 0.26)
	var water_p := Vector3(at.x, Car.WATER_Y + 0.06, at.z)
	emit_ripple(water_p, 0.32 * obj_scale, (1.6 + spd * 0.25) * obj_scale, 1.25, 0.48)
	for i in 3:
		var ang := _rng.randf() * TAU
		var v := Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(0.6, 1.8) + Vector3.UP * _rng.randf_range(1.2, 2.8)
		sparks.emit(water_p + Vector3.UP * 0.1, v, _rng.randf_range(0.28, 0.55), 0.06, 0.025, Color(0.86, 0.94, 1.0, 0.78))
		smoke.emit(water_p + Vector3(cos(ang) * 0.25, 0.06, sin(ang) * 0.25), v * 0.45,
			_rng.randf_range(0.35, 0.65), 0.25 * obj_scale, 0.85 * obj_scale, Color(0.90, 0.96, 1.0, 0.36))


## A mine going off: a fireball, a ring of sparks and a column of smoke.
func explosion(at: Vector3) -> void:
	for i in 40:
		var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.2), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(4.0, 13.0)
		sparks.emit(at + Vector3.UP * 0.4, v, _rng.randf_range(0.4, 0.9), 0.16, 0.04, Color(1.0, _rng.randf_range(0.55, 0.85), 0.3, 1.0))
	for i in 28:
		fire.emit(at + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(0.2, 1.4), _rng.randf_range(-1.2, 1.2)),
			Vector3(_rng.randf_range(-2.5, 2.5), _rng.randf_range(2.0, 6.0), _rng.randf_range(-2.5, 2.5)),
			_rng.randf_range(0.4, 0.8), 1.4, 0.4, Color(1.0, _rng.randf_range(0.35, 0.65), 0.1, 1.0))
	for i in 14:
		smoke.emit(at + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1.5, 1.5)),
			Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(1.5, 4.0), _rng.randf_range(-1.2, 1.2)),
			_rng.randf_range(2.0, 3.2), 1.6, 5.0, Color(0.16, 0.15, 0.15, 0.55))
