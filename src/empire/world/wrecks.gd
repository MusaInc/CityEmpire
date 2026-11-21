class_name Wrecks
extends Node
## Crashing into other cars (2026-11-21), as in NEVER STOP: a car you hit is
## a real car, not a wall. The city's traffic is drawn on the GPU (with a
## kinematic box near you: infinitely heavy) and parked cars are part of the
## street, so neither could be shunted. Just before your car reaches one
## (its footprint ~0.1 s ahead, relative motion), that car is swapped for a
## physical Car – same body, paint, place and speed – and physics does the
## rest: momentum shared by mass, both take damage (Car's own model),
## spins, shoves. The traffic slot holds its lane (Traffic.knock: cars behind
## queue, and brake for the wreck), the parked car leaves the kerb.
## A wreck rolls to a stop, stays a while, then clears once you're away.

const MAX := 8
const LOOKAHEAD := 0.1        # s of relative motion checked ahead
const CLEAR_AFTER := 45.0     # s, at most
const CLEAR_AWAY := 110.0     # m: a settled wreck clears once you're this far

var game: EmpireGame
var wrecks: Array = []        # {car, t, traffic: id or -1, hit, spawn_y, parked: [CityWorld, key, xf, kind] or []}
const UNTOUCHED_BACK := 1.2   # s: a swapped car nothing touched goes back to traffic / the kerb
var _parked := {}             # [CityWorld, chunk key] -> [[Transform3D, kind]]
var _rng := RandomNumberGenerator.new()


func setup(g: EmpireGame) -> void:
	game = g
	process_physics_priority = -4   # after TrafficBodies has placed its boxes
	_rng.randomize()


## Cars that can knock things over (Destructibles.cars_fn): the wrecks.
func cars() -> Array:
	return wrecks.map(func(w): return w["car"]).filter(func(c): return is_instance_valid(c))


func _physics_process(dt: float) -> void:
	if game == null or game.world == null:
		return
	var me := game.vehicle_node() as Car
	if me and is_instance_valid(me) and not me.freeze and me.linear_velocity.length() > 1.5:
		_look_ahead(me)
	var tr: Traffic = game.world.traffic
	var keep: Array = []
	var here := game.vehicle_node().global_position if game.vehicle_node() else game.player.global_position
	var obs: Array = []
	for w in wrecks:
		var c: Car = w["car"]
		if not is_instance_valid(c):
			_free(w, tr)
			continue
		w["t"] += dt
		if not w["hit"]:
			for b in c.get_colliding_bodies():
				if b is Car or b is RigidBody3D:
					w["hit"] = true
		# A near miss (swapped, never touched): straight back into traffic –
		# a car that just stopped in its lane looked broken.
		if not w["hit"] and w["t"] > UNTOUCHED_BACK:
			_restore(w, tr)
			continue
		# Spawn sanity: thrown by an overlap, or fallen through the world.
		if (w["t"] < 2.0 and c.linear_velocity.length() > 45.0) or c.global_position.y < float(w["spawn_y"]) - 8.0:
			_restore(w, tr)
			continue
		# Nobody's driving it: it rolls on, then brakes to a stop.
		c.throttle = 0.0
		c.handbrake = false
		c.brake = 0.0 if w["t"] < 1.2 else 0.7
		var far := c.global_position.distance_to(here) > CLEAR_AWAY
		if w["t"] > CLEAR_AFTER and far or w["t"] > CLEAR_AFTER * 3.0 or (far and w["t"] > 8.0 and c.speed < 0.5):
			c.queue_free()
			_free(w, tr)
			continue
		obs.append(c.global_position)
		keep.append(w)
	wrecks = keep
	if tr:
		tr.obstacles = obs


## Undo a swap: the physical car goes, the traffic slot / parked car comes back.
func _restore(w: Dictionary, tr: Traffic) -> void:
	var c: Car = w["car"]
	if is_instance_valid(c):
		c.queue_free()
	_free(w, tr)
	var pk: Array = w.get("parked", [])
	if not pk.is_empty():
		var cw: CityWorld = pk[0]
		if is_instance_valid(cw):
			cw.unbreak_item((pk[2] as Transform3D).origin)
			cw.refresh_parked(pk[1])
			var ck := [cw, pk[1]]
			if _parked.has(ck):
				(_parked[ck] as Array).append([pk[2], pk[3]])


func _free(w: Dictionary, tr: Traffic) -> void:
	if tr and int(w["traffic"]) >= 0:
		tr.release(int(w["traffic"]))


func _look_ahead(me: Car) -> void:
	var size: Vector3 = me.spec["size"]
	var mh := Vector2(size.x * 0.5 + 0.15, size.z * 0.5 + 0.15)
	var mp := me.global_position
	var mv := me.linear_velocity
	var tb: TrafficBodies = game.traffic_bodies
	var tr: Traffic = game.world.traffic
	if tb and tr:
		for it in tb.city_cars():
			var id: int = it[0]
			var xf: Transform3D = it[1]
			var ov := -xf.basis.z * tr.car_speed(id)
			if absf(xf.origin.y - mp.y) > 2.5 or xf.origin.distance_to(mp) > 20.0:
				continue
			var k := int(tr.c_kind[id])
			if _hits(me, mp + (mv - ov) * LOOKAHEAD, mh, xf, _half(game.world, k)):
				tb.drop(id)
				tr.knock(id)
				_spawn(k, xf, ov, tr.c_col[id], id)
	# Parked cars in the chunks round you (both landmasses).
	for w2 in [game.world, game.world.mainland]:
		var w: CityWorld = w2
		if w == null:
			continue
		var c0 := Vector2i(floori(mp.x / CityWorld.CHUNK), floori(mp.z / CityWorld.CHUNK))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := c0 + Vector2i(dx, dz)
				if not w._loaded.has(key):
					continue
				var ck := [w, key]
				if not _parked.has(ck):
					_parked[ck] = w.parked_cars(key)
				var list: Array = _parked[ck]
				for i in range(list.size() - 1, -1, -1):
					var pc: Array = list[i]
					var xf: Transform3D = pc[0]
					if absf(xf.origin.y - mp.y) > 2.5 or xf.origin.distance_to(mp) > 15.0:
						continue
					if _hits(me, mp + mv * LOOKAHEAD, mh, xf, _half(w, int(pc[1]))):
						list.remove_at(i)
						w.break_item(xf.origin)
						w.refresh_parked(key)
						_spawn(int(pc[1]), xf, Vector3.ZERO, CityWorld.kind_colour(int(pc[1]),
							CityWorld.CAR_COLORS[_rng.randi() % CityWorld.CAR_COLORS.size()]), -1, [w, key, xf, int(pc[1])])


## Half extents (x, z) of a traffic/parked car kind from its drawn model.
func _half(w: CityWorld, k: int) -> Vector2:
	var m: Mesh = w.car_meshes[k] if k < w.car_meshes.size() else null
	var a := m.get_aabb() if m else AABB(Vector3(-1, 0, -2.3), Vector3(2, 1.45, 4.6))
	return Vector2(a.size.x * 0.5, a.size.z * 0.5)


## Do my footprint (centre `at`, my yaw) and theirs overlap? 2-D separating axes.
static func _hits(me: Car, at: Vector3, mh: Vector2, xf: Transform3D, oh: Vector2) -> bool:
	var ax := [Vector2(me.global_basis.x.x, me.global_basis.x.z).normalized(), Vector2(me.global_basis.z.x, me.global_basis.z.z).normalized()]
	var bx := [Vector2(xf.basis.x.x, xf.basis.x.z).normalized(), Vector2(xf.basis.z.x, xf.basis.z.z).normalized()]
	var d := Vector2(xf.origin.x - at.x, xf.origin.z - at.z)
	for axis: Vector2 in ax + bx:
		var ra: float = mh.x * absf((ax[0] as Vector2).dot(axis)) + mh.y * absf((ax[1] as Vector2).dot(axis))
		var rb: float = oh.x * absf((bx[0] as Vector2).dot(axis)) + oh.y * absf((bx[1] as Vector2).dot(axis))
		if absf(d.dot(axis)) > ra + rb:
			return false
	return true


func _spawn(k: int, xf: Transform3D, vel: Vector3, col: Color, traffic_id: int, parked := []) -> void:
	while wrecks.size() >= MAX:
		var old: Dictionary = wrecks.pop_front()
		if is_instance_valid(old["car"]):
			(old["car"] as Car).queue_free()
		_free(old, game.world.traffic)
	var body: String = CityWorld.CAR_KINDS[k][2]
	var base := body if CarCatalog.CIVILIANS.has(body) else "civ_sedan"
	var spec := CarCatalog.civ_spec(base, _rng)
	spec["id"] = body
	spec["body"] = body
	CarCatalog._fit_body(spec)
	spec["paint"] = col
	var c := Car.new()
	c.name = "Wreck"
	c.setup(spec, "civilian")
	game.add_child(c)
	c.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * 0.05)
	c.linear_velocity = vel
	var vis := CarVisual.new()
	c.add_child(vis)
	vis.setup(c)
	wrecks.append({"car": c, "t": 0.0, "traffic": traffic_id, "hit": false, "spawn_y": xf.origin.y, "parked": parked})
