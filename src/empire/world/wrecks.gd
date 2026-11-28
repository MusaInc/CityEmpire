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
const LOOKAHEAD := 0.24       # s of relative motion checked ahead (swaps traffic before kinematic contact)
const CLEAR_AFTER := 45.0     # s, at most
const CLEAR_AWAY := 110.0     # m: a settled wreck clears once you're this far

var game: EmpireGame
var wrecks: Array = []        # {car, t, traffic: id or -1, hit, spawn_y, parked: [CityWorld, key, xf, kind, col] or [], island: Dictionary or null}
const UNTOUCHED_BACK := 1.6   # s: a swapped car nothing touched goes back to traffic / the kerb
var _parked := {}             # Vector3i(key.x, key.y, world_idx) -> [[Transform3D, kind]]
var _prune_t := 0.0
var _rng := RandomNumberGenerator.new()


func _p_key(w: CityWorld, key: Vector2i) -> Vector3i:
	return Vector3i(key.x, key.y, 0 if w == game.world else 1)


func _prune_parked() -> void:
	for k in _parked.keys():
		var vk: Vector3i = k
		var w: CityWorld = game.world if vk.z == 0 else game.world.mainland
		if w == null or not w._loaded.has(Vector2i(vk.x, vk.y)):
			_parked.erase(k)


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
	if me and is_instance_valid(me) and not me.freeze and (me.linear_velocity.length() > 0.15 or me.throttle > 0.05 or me.brake > 0.05):
		_look_ahead(me)
	var keep: Array = []
	var here := game.vehicle_node().global_position if game.vehicle_node() else game.player.global_position
	var obs: Array = []
	for w in wrecks:
		var tr: Traffic = w.get("source")
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
	for world in [game.world, game.world.mainland]:
		if world and world.traffic:
			world.traffic.obstacles = obs
	_prune_t += dt
	if _prune_t >= 4.0:
		_prune_t = 0.0
		_prune_parked()


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
			var ck := _p_key(cw, pk[1])
			if _parked.has(ck):
				(_parked[ck] as Array).append([pk[2], pk[3], pk[4]] if pk.size() > 4 else [pk[2], pk[3]])
	var ic = w.get("island")
	if ic is Dictionary:
		(ic as Dictionary)["wait"] = 0.0


func _free(w: Dictionary, tr: Traffic) -> void:
	if tr and int(w["traffic"]) >= 0:
		tr.release(int(w["traffic"]))
	var ic = w.get("island")
	if ic is Dictionary and float((ic as Dictionary).get("wait", 0.0)) > 12.0:
		(ic as Dictionary)["wait"] = 4.0


func _hits_swept(me: Car, mp: Vector3, rel_v: Vector3, mh: Vector2, xf: Transform3D, oh: Vector2) -> bool:
	return _hits(me, mp, mh, xf, oh) \
		or _hits(me, mp + rel_v * (LOOKAHEAD * 0.5), mh, xf, oh) \
		or _hits(me, mp + rel_v * LOOKAHEAD, mh, xf, oh)


func _look_ahead(me: Car) -> void:
	var size: Vector3 = me.spec["size"]
	var mh := Vector2(size.x * 0.5 + 0.55, size.z * 0.5 + 0.55)
	var mp := me.global_position
	var mv := me.linear_velocity
	var tb: TrafficBodies = game.traffic_bodies
	if tb:
		for it in tb.city_cars():
			var tr: Traffic = it[2]
			var id: int = it[0]
			var xf: Transform3D = it[1]
			var ov := -xf.basis.z * tr.car_speed(id)
			if absf(xf.origin.y - mp.y) > 2.5 or xf.origin.distance_to(mp) > 28.0:
				continue
			var k := int(tr.c_kind[id])
			var oh := _half(game.world, k)
			if _hits_swept(me, mp, mv - ov, mh, xf, oh):
				tb.drop(id, tr)
				tr.knock(id)
				_spawn(k, xf, ov, tr.c_col[id], id, [], tr)
		for it in tb.island_cars():
			var ic: Dictionary = it[0]
			var xf: Transform3D = it[1]
			var ov := -xf.basis.z * float(ic.get("v", 0.0))
			if absf(xf.origin.y - mp.y) > 2.5 or xf.origin.distance_to(mp) > 28.0:
				continue
			var k := int(ic.get("kind", 0))
			var oh := _half(game.world, k)
			if _hits_swept(me, mp, mv - ov, mh, xf, oh):
				tb.drop_island(ic)
				ic["wait"] = CLEAR_AFTER
				_spawn(k, xf, ov, ic.get("col", Color(0.7, 0.7, 0.7)), -1, [], null, ic)
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
				var ck := _p_key(w, key)
				if not _parked.has(ck):
					_parked[ck] = w.parked_cars(key)
				var list: Array = _parked[ck]
				for i in range(list.size() - 1, -1, -1):
					var pc: Array = list[i]
					var xf: Transform3D = pc[0]
					if absf(xf.origin.y - mp.y) > 2.5 or xf.origin.distance_to(mp) > 22.0:
						continue
					var oh := _half(w, int(pc[1]))
					if _hits_swept(me, mp, mv, mh, xf, oh):
						list.remove_at(i)
						w.break_item(xf.origin)
						w.refresh_parked(key)
						var col: Color = pc[2] if pc.size() > 2 else CityWorld.kind_colour(int(pc[1]),
							CityWorld.CAR_COLORS[_rng.randi() % CityWorld.CAR_COLORS.size()])
						_spawn(int(pc[1]), xf, Vector3.ZERO, col, -1, [w, key, xf, int(pc[1]), col])


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


func _spawn(k: int, xf: Transform3D, vel: Vector3, col: Color, traffic_id: int, parked := [], source: Traffic = null, island = null) -> void:
	while wrecks.size() >= MAX:
		var old: Dictionary = wrecks.pop_front()
		if is_instance_valid(old["car"]):
			(old["car"] as Car).queue_free()
		_free(old, old.get("source"))
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
	c.reverse_enabled = false
	game.add_child(c)
	c.place(Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * 0.05), vel)
	c.splashed.connect(func(at: Vector3, spd: float):
		if game and game.vfx:
			game.vfx.splash(at, spd, clampf(c.mass / 1400.0, 0.85, 1.6))
		if game and game.audio:
			game.audio.play("splash", clampf(lerpf(-6.0, 2.0, spd / 20.0), -6.0, 2.0), clampf(lerpf(1.05, 0.76, spd / 24.0), 0.76, 1.08)))
	var vis := CarVisual.new()
	c.add_child(vis)
	vis.setup(c)
	if game.vfx:
		game.vfx.watch(c)
	wrecks.append({"car": c, "t": 0.0, "traffic": traffic_id, "source": source, "hit": false, "spawn_y": xf.origin.y, "parked": parked, "island": island})


# ------------------------------------------------------------ stealing
## (2026-11-26, "i want to steal cars"): any car you can walk up to – a
## stopped or crawling traffic car (city, Westbank, Skyport), a parked car, a
## settled wreck – can be taken. StreetCars turns it into a drivable car.

## Gap from the point to a car's footprint (m), or INF if not level with it.
static func _gap(p: Vector3, xf: Transform3D, half: Vector2) -> float:
	var lp := xf.affine_inverse() * p
	if absf(lp.y) > 2.4:
		return INF
	return Vector2(maxf(absf(lp.x) - half.x, 0.0), maxf(absf(lp.z) - half.y, 0.0)).length()


## The nearest car within `reach` of p you could take: {} or {src, d, xf, k,
## col, ...}. src: "traffic" | "island" | "parked" | "wreck".
func stealable(p: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	var tb: TrafficBodies = game.traffic_bodies
	if tb:
		for it in tb.city_cars():
			var tr: Traffic = it[2]
			var id: int = it[0]
			if tr.car_speed(id) > 1.6:
				continue
			var k := int(tr.c_kind[id])
			var d := _gap(p, it[1], _half(game.world, k))
			if d < bd:
				bd = d
				best = {"src": "traffic", "tr": tr, "id": id, "xf": it[1], "k": k, "col": tr.c_col[id]}
		for it in tb.island_cars():
			var ic: Dictionary = it[0]
			if float(ic.get("v", 0.0)) > 1.6:
				continue
			var k2 := int(ic.get("kind", 0))
			var d2 := _gap(p, it[1], _half(game.world, k2))
			if d2 < bd:
				bd = d2
				best = {"src": "island", "ic": ic, "xf": it[1], "k": k2, "col": ic.get("col", Color(0.7, 0.7, 0.7))}
	for w2 in [game.world, game.world.mainland]:
		var w: CityWorld = w2
		if w == null:
			continue
		var c0 := Vector2i(floori(p.x / CityWorld.CHUNK), floori(p.z / CityWorld.CHUNK))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := c0 + Vector2i(dx, dz)
				if not w._loaded.has(key):
					continue
				var ck := _p_key(w, key)
				if not _parked.has(ck):
					_parked[ck] = w.parked_cars(key)
				var list: Array = _parked[ck]
				for i in list.size():
					var pc: Array = list[i]
					var d3 := _gap(p, pc[0], _half(w, int(pc[1])))
					if d3 < bd:
						bd = d3
						var col: Color = pc[2] if pc.size() > 2 else CityWorld.kind_colour(int(pc[1]),
							CityWorld.CAR_COLORS[absi(hash(key) + i) % CityWorld.CAR_COLORS.size()])
						best = {"src": "parked", "w": w, "key": key, "entry": pc, "xf": pc[0], "k": int(pc[1]), "col": col}
	for wr in wrecks:
		var c: Car = wr["car"]
		if not is_instance_valid(c) or c.linear_velocity.length() > 1.0:
			continue
		var s: Vector3 = c.spec["size"]
		var d4 := _gap(p, c.global_transform, Vector2(s.x * 0.5, s.z * 0.5))
		if d4 < bd:
			bd = d4
			best = {"src": "wreck", "wreck": wr, "xf": c.global_transform, "k": -1, "col": c.spec.get("paint", Color.WHITE)}
	if not best.is_empty():
		best["d"] = bd
		best["world"] = (best["xf"] as Transform3D).origin
	return best


## Take the car out of the street: it leaves traffic / the kerb / the wreck
## list. Returns [body, Transform3D, paint, damage, dent_state, release]
## where release = [Traffic, id] to hand back to traffic once you're far
## away (or []).
func take(c: Dictionary) -> Array:
	var xf: Transform3D = c["xf"]
	var body := ""
	var release := []
	var damage := {}
	var dents := {}
	match String(c["src"]):
		"traffic":
			var tr: Traffic = c["tr"]
			var id: int = c["id"]
			game.traffic_bodies.drop(id, tr)
			tr.knock(id)
			release = [tr, id]
			body = CityWorld.CAR_KINDS[int(c["k"])][2]
		"island":
			var ic: Dictionary = c["ic"]
			game.traffic_bodies.drop_island(ic)
			ic["wait"] = 1.0e9      # (gone for good: you've got it)
			body = CityWorld.CAR_KINDS[int(c["k"])][2]
		"parked":
			var w: CityWorld = c["w"]
			var key: Vector2i = c["key"]
			var list: Array = _parked.get(_p_key(w, key), [])
			list.erase(c["entry"])
			w.break_item(xf.origin)
			w.refresh_parked(key)
			body = CityWorld.CAR_KINDS[int(c["k"])][2]
		"wreck":
			var wr: Dictionary = c["wreck"]
			var car: Car = wr["car"]
			body = String(car.spec.get("body", "civ_sedan"))
			damage = car.damage_state()
			if car.visual:
				dents = car.visual.visual_state()
			wrecks.erase(wr)
			if wr.get("source") and int(wr["traffic"]) >= 0:
				release = [wr["source"], int(wr["traffic"])]
			car.queue_free()
	return [body, xf, c["col"], damage, dents, release]
