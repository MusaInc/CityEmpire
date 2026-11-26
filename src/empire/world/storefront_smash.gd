class_name StorefrontSmash
extends Node
## Cars through shop windows (destruction overhaul 2026-11-25). Every
## streamed shop or ground-floor room (ShopInterior, group "shop_spans")
## has its display windows as breakable spans. Each physics frame the cars
## that can break things (Destructibles.cars_fn: yours, wrecked traffic,
## police) are checked a moment ahead of their motion against the spans
## near them:
##  * coming in square enough and hard enough (speed into the facade and
##    momentum: a hatch at ~18 km/h, a van slower) the window goes – glass,
##    riser and mullions – before the contact can stop the car, which ploughs
##    on into the shop a little slower and takes the hit (Car.external_impact:
##    a cracked windscreen, dents, scuffs);
##  * a nudge stays a nudge (the span's own collision stops the car);
##  * shards burst out, the crash sounds, the camera shakes (your car);
##  * DamageDesk bills it: a repair for your own shop, otherwise a property
##    damage charge with the police on their way.
## The pilasters, reveals, door returns, transom and walls are never spans:
## the building's structure always stands.
##
## Broken windows are remembered per unit for the session (rooms are
## rebuilt as you come and go): broken for BOARD_AFTER game minutes, then
## boarded up, then mended after MEND_AFTER – the street puts itself right.

const BREAK_SPEED := 4.6        # m/s into the facade
const BREAK_MOMENTUM := 6500.0  # kg·m/s
const LOOKAHEAD := 0.12         # s of motion tested ahead
const BOARD_AFTER := 90.0       # game minutes broken, then boarded
const MEND_AFTER := 600.0       # game minutes until it's glazed again
const SPAN_COST := 380.0        # per window, plus per metre below (was 2400: toned down 2026-11-26)
const COST_PER_M := 90.0

var game: EmpireGame
## unit id -> {span index: game minute broken}
var damage := {}
var _check_t := 0.0
## Stock knocked off the fixtures a car hits inside a shop (pooled).
const SPILL_MAX := 48
const SPILL_LIFE := 25.0
var _spill: Array = []          # [RigidBody3D, age]
var _spill_mesh: BoxMesh
var _spill_mats: Array[StandardMaterial3D] = []
var _watched := {}


func setup(g: EmpireGame) -> void:
	game = g
	process_physics_priority = -3


## What a room should look like when it's (re)built: span -> state.
func state_for(unit_id: String) -> Dictionary:
	var out := {}
	var now := _now()
	for i in damage.get(unit_id, {}):
		var age := now - float(damage[unit_id][i])
		if age < BOARD_AFTER:
			out[i] = "broken"
		elif age < MEND_AFTER:
			out[i] = "boarded"
	return out


func _now() -> float:
	return float(game.empire.day) * 1440.0 + float(game.empire.minute) if game and game.empire else 0.0


func _physics_process(dt: float) -> void:
	if game == null or game.props == null or not game.props.cars_fn.is_valid():
		return
	var rooms := get_tree().get_nodes_in_group("shop_spans")
	if rooms.is_empty():
		return
	_age_spill(dt)
	for o in game.props.cars_fn.call():
		var c := o as Car
		if c == null or not is_instance_valid(c):
			continue
		if not _watched.has(c.get_instance_id()):
			_watched[c.get_instance_id()] = true
			c.impact.connect(_on_car_impact.bind(c))
		if c.freeze or c.speed < BREAK_SPEED:
			continue
		for r in rooms:
			var si := r as ShopInterior
			if si == null or not is_instance_valid(si) or not si.is_inside_tree():
				continue
			if si.global_position.distance_to(c.global_position) > si.W + 14.0:
				continue
			_test(c, si)
	# Restoration: the windows of loaded rooms move on to boarded / mended.
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 2.0
		_restore(rooms)


func _test(c: Car, si: ShopInterior) -> void:
	var inv := si.global_transform.affine_inverse()
	var size: Vector3 = c.spec["size"]
	var v_local := inv.basis * c.linear_velocity
	# Into the shop = towards −z in the room frame (z points out of the facade).
	if v_local.z > -BREAK_SPEED:
		return
	if c.mass * -v_local.z < BREAK_MOMENTUM:
		return
	var ahead := c.linear_velocity * LOOKAHEAD
	var corners: Array[Vector3] = []
	for cx: float in [-0.5, 0.5]:
		for cz: float in [-0.5, 0.5]:
			corners.append(inv * (c.global_transform * Vector3(cx * size.x, size.y * 0.35, cz * size.z) + ahead))
	for i in si.span_count():
		if si.span_broken(i):
			continue
		var b := si.span_box(i)
		var lo: Vector3 = b[1]
		var hi: Vector3 = b[2]
		# Overlap of the car's (advanced) footprint box with the span – a car
		# wider than a narrow window has no corner inside it.
		var mn := corners[0]
		var mx := corners[0]
		for q: Vector3 in corners:
			mn = mn.min(q)
			mx = mx.max(q)
		var hit := mn.x < hi.x + 0.1 and mx.x > lo.x - 0.1 and mn.z < hi.z + 0.25 and mx.z > lo.z - 1.2 \
			and mn.y < hi.y + 0.5 and mx.y > lo.y - 0.5
		var at_local := Vector3(clampf((mn.x + mx.x) * 0.5, lo.x, hi.x), clampf(mn.y, lo.y + 0.3, hi.y), hi.z)
		if hit:
			_smash(c, si, i, si.global_transform * at_local, si.global_basis.z.normalized(), hi.x - lo.x)
			return


func _smash(c: Car, si: ShopInterior, i: int, at: Vector3, outward: Vector3, width: float) -> void:
	si.break_span(i)
	var uid := String(si.unit.get("id", ""))
	if not damage.has(uid):
		damage[uid] = {}
	damage[uid][i] = _now()
	var spd := c.speed
	c.linear_velocity *= 0.82 if c.mass < 2500.0 else 0.9
	c.external_impact(at, outward, clampf(3.5 + spd * 0.32, 4.0, 14.0))
	# Shards: a burst of glass out and in, a few heavier pieces.
	if game.vfx:
		for k in int(clampf(width * 14.0, 20.0, 60.0)):
			var sv := c.linear_velocity * randf_range(0.2, 0.7) + Vector3(randf_range(-3, 3), randf_range(0.5, 4.0), randf_range(-3, 3))
			game.vfx.sparks.emit(at + Vector3(randf_range(-width * 0.4, width * 0.4), randf_range(-0.5, 1.2), 0.0), sv,
				randf_range(0.6, 1.2), 0.08, 0.04, Color(0.8, 0.88, 0.92, 0.85))
		for k in 3:
			game.vfx.smoke.emit(at + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)), Vector3(0, 0.8, 0), 1.2, 0.6, 2.0, Color(0.7, 0.68, 0.64, 0.25))
	if game.car_audio and c == game.vehicle_node():
		game.car_audio.play("crash_heavy_%d" % (randi() % 3), -4.0, randf_range(1.15, 1.3))
		game.chase.shake(0.5)
	# Whose window: your own shop is a repair bill, anyone else's is a charge.
	if c == game.vehicle_node() and game.damage_desk:
		var cost := roundf(SPAN_COST + COST_PER_M * width)
		var b: Business = game.empire.business_at(uid)
		var what := "%s window" % String(si.unit.get("shop_name", si.unit.get("name", "shop")))
		game.damage_desk.report(what, at, cost, uid if b != null else "")


func _restore(rooms: Array) -> void:
	for r in rooms:
		var si := r as ShopInterior
		if si == null or not is_instance_valid(si):
			continue
		var uid := String(si.unit.get("id", ""))
		if not damage.has(uid):
			continue
		var want := state_for(uid)
		for i in si.span_count():
			var have := String(si.front_state.get(i, ""))
			var w := String(want.get(i, ""))
			if have == w:
				continue
			# (Only out of the player's sight-line close up: no pop in their face.)
			if game.player.global_position.distance_to(si.global_position) < 25.0:
				continue
			if w == "boarded":
				si.board_span(i)
			elif w == "":
				si.mend_span(i)
		if want.is_empty() and si.front_state.is_empty():
			damage.erase(uid)


# ---------------------------------------------------------- inside a shop
## A car hitting a fixture inside a shop (shelving, a fridge, the counter):
## the fixture holds (it's bolted down), but what's on it comes off –
## packs and cases tumble out with the hit's momentum and lie about until
## they're tidied away.
func _on_car_impact(strength: float, at: Vector3, n: Vector3, other: Object, c: Car) -> void:
	if strength < 3.0 or not (other is StaticBody3D) or not is_instance_valid(c):
		return
	var si := (other as Node).get_parent() as ShopInterior
	if si == null or (other as Node).name != "Collision":
		return
	var count := int(clampf(strength * 1.4, 5.0, 16.0))
	for k in count:
		_spill_one(at + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 1.4), randf_range(-0.6, 0.6)),
			-n * randf_range(0.5, 2.5) + c.linear_velocity * randf_range(0.2, 0.6) + Vector3(0, randf_range(0.5, 2.5), 0))
	if game.car_audio and c == game.vehicle_node():
		game.car_audio.play("crash_light_%d" % (randi() % 2), -8.0, randf_range(1.3, 1.5))


func _spill_one(at: Vector3, vel: Vector3) -> void:
	if _spill_mesh == null:
		_spill_mesh = BoxMesh.new()
		_spill_mesh.size = Vector3(0.16, 0.22, 0.1)
		for col: Color in [Color(0.85, 0.2, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.45, 0.8), Color(0.9, 0.9, 0.85), Color(0.25, 0.6, 0.3), Color(0.55, 0.35, 0.2)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = col
			m.roughness = 0.6
			_spill_mats.append(m)
	if _spill.size() >= SPILL_MAX:
		var old: Array = _spill.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()
	var b := RigidBody3D.new()
	b.collision_layer = 1 << 5
	b.collision_mask = 1 | (1 << 3) | CityWorld.HUMAN_LAYER
	b.mass = 0.6
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var sc := randf_range(0.7, 1.6)
	bs.size = _spill_mesh.size * sc
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _spill_mesh
	mi.scale = Vector3.ONE * sc
	mi.material_override = _spill_mats[randi() % _spill_mats.size()]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(mi)
	game.add_child(b)
	b.global_position = at
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_spill.append([b, 0.0])


func _age_spill(dt: float) -> void:
	for i in range(_spill.size() - 1, -1, -1):
		var e: Array = _spill[i]
		e[1] = float(e[1]) + dt
		if float(e[1]) > SPILL_LIFE or not is_instance_valid(e[0]):
			if is_instance_valid(e[0]):
				(e[0] as Node).queue_free()
			_spill.remove_at(i)
