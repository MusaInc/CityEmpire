class_name TrafficBodies
extends Node
## Solid traffic. The city's moving cars are drawn on the GPU (Traffic) and
## Skyport's by a MultiMesh (IslandTraffic), so neither had a body: you
## drove straight through them. As in Never Stop (CivilianTraffic: a frozen
## kinematic body per civilian car), the few cars near you get a kinematic
## box that follows them every physics tick – your car hits them, you can't
## walk through them. A pool of POOL bodies; cars are re-listed a few times a
## second, nearest first. Bus/box-truck-sized bodies use the longer box.
##
## Island cars also brake for your vehicle when it's in their lane ahead
## (IslandTraffic.blocker).

const POOL := 14
const RANGE := 70.0            # m from you
const LIST_EVERY := 0.25
const HALF := Vector3(1.0, 0.75, 2.3)

static var _shapes := {}       # body name -> [BoxShape3D, float center_y]

var game: EmpireGame
var _bodies: Array = []        # AnimatableBody3D
var _body_shapes: Array[CollisionShape3D] = []
var _near: Array = []          # [[source, id]]: source 0 = Commercial, 1 = Skyport, 2 = Westbank
var _list_t := 0.0
var _island_cache: IslandTraffic
var _island_check_t := 0.0


static func _shape_for(body_name: String) -> Array:
	if _shapes.has(body_name):
		return _shapes[body_name] as Array
	var d: Dictionary = BodyDims.DIMS.get(body_name, {})
	var sh := BoxShape3D.new()
	var cy := HALF.y + 0.15
	if not d.is_empty():
		var w := maxf(float(d["W"]) * 0.96, 1.6)
		var h := maxf(float(d["roof"]) - float(d["ride"]), 1.2)
		var l := maxf(float(d["L"]) * 0.98, 3.8)
		sh.size = Vector3(w, h, l)
		cy = float(d["ride"]) + h * 0.5
	else:
		sh.size = HALF * 2.0
	var entry := [sh, cy]
	_shapes[body_name] = entry
	return entry


static func _kind_body(kind_idx: int) -> String:
	if kind_idx >= 0 and kind_idx < CityWorld.CAR_KINDS.size():
		return String(CityWorld.CAR_KINDS[kind_idx][2])
	return ""


func setup(g: EmpireGame) -> void:
	game = g
	process_physics_priority = -5
	var def_shape := _shape_for("")
	for i in POOL:
		var b := AnimatableBody3D.new()
		b.name = "TrafficBody%d" % i
		b.sync_to_physics = false
		b.collision_layer = Car.BODY_LAYER
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = def_shape[0]
		cs.position = Vector3(0, float(def_shape[1]), 0)
		b.add_child(cs)
		b.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(b)
		b.top_level = true
		b.global_position = Vector3(0, -500, 0)
		_bodies.append(b)
		_body_shapes.append(cs)


## City traffic cars that currently have a body: [[id, Transform3D, Traffic source]] (Wrecks).
func city_cars() -> Array:
	var out: Array = []
	for src in _near:
		var tr := _traffic(int(src[0]))
		if tr and not tr.knocked.has(int(src[1])):
			out.append([int(src[1]), traffic_xf(tr, int(src[1])), tr])
	return out


func _traffic(source: int) -> Traffic:
	if game == null or game.world == null:
		return null
	if source == 0:
		return game.world.traffic
	if source == 2 and game.world.mainland:
		return game.world.mainland.traffic
	return null


static func traffic_xf(tr: Traffic, id: int) -> Transform3D:
	var s := tr.car_s(id, tr.now)
	var p := tr.lane_point(tr.c_lane[id], s)
	var dir := tr.lane_dir(tr.c_lane[id], s)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p)


## A car Wrecks is replacing with a real one: its kinematic body leaves at
## once (a rigid car spawned inside it would be flung out).
func drop(id: int, traffic: Traffic = null) -> void:
	for i in _near.size():
		var src: Array = _near[i]
		if _traffic(int(src[0])) == (traffic if traffic else _traffic(0)) and int(src[0]) in [0, 2] and int(src[1]) == id:
			_near[i] = [-1, 0]   # (body i stays parked until the next listing)
			var b: AnimatableBody3D = _bodies[i]
			b.global_position = Vector3(0, -500, 0)
			b.process_mode = Node.PROCESS_MODE_DISABLED
			break


func _here() -> Vector3:
	var vn := game.vehicle_node()
	return vn.global_position if vn else game.player.global_position


func _island(dt: float) -> IslandTraffic:
	if _island_cache != null and is_instance_valid(_island_cache):
		return _island_cache
	_island_cache = null
	_island_check_t -= dt
	if _island_check_t <= 0.0 and is_inside_tree():
		_island_cache = get_tree().get_first_node_in_group("island_traffic") as IslandTraffic
		_island_check_t = 1.0 if _island_cache == null else 0.0
	return _island_cache


func _physics_process(dt: float) -> void:
	if game == null or game.world == null:
		return
	var here := _here()
	var it := _island(dt)
	if it:
		var vn := game.vehicle_node()
		it.blocker = here if (vn != null or not game.player.indoors) else Vector3(INF, 0, INF)
	_list_t -= dt
	if _list_t <= 0.0:
		_list_t = LIST_EVERY
		var cand: Array = []
		var r2 := RANGE * RANGE
		for source in [0, 2]:
			var tr := _traffic(source)
			if tr == null:
				continue
			if not tr.l_cars.is_empty():
				for id in tr.cars_near(here, RANGE):
					var d := tr.car_position(id).distance_squared_to(here)
					if d < r2:
						cand.append([d, source, id])
			else:
				for id in tr.car_count():
					if tr.knocked.has(id) or tr.is_dormant(id):
						continue
					var d := tr.car_position(id).distance_squared_to(here)
					if d < r2:
						cand.append([d, source, id])
		if it:
			for c in it.cars:
				if float(c["wait"]) > 0.0:
					continue
				var p: Vector3 = it.car_xf(c).origin
				var d2 := p.distance_squared_to(here)
				if d2 < r2:
					cand.append([d2, 1, c])
		cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		_near = cand.slice(0, POOL).map(func(x): return [x[1], x[2]])
		# City traffic brakes for your vehicle in its lane (and queues).
		for source in [0, 2]:
			var tr := _traffic(source)
			if tr == null:
				continue
			var vn := game.vehicle_node()
			var ids: Array = []
			for x in cand:
				if int(x[1]) == source and (float(x[0]) < 40.0 * 40.0 or not tr.pedestrian_obstacles.is_empty()):
					ids.append(int(x[2]))
			tr.yield_to(vn.global_position if vn else game.player.global_position, ids)   # (people crossing too)
	for i in POOL:
		var b: AnimatableBody3D = _bodies[i]
		if i >= _near.size() or int(_near[i][0]) < 0 or (int(_near[i][0]) == 1 and it == null):
			if b.process_mode != Node.PROCESS_MODE_DISABLED:
				b.global_position = Vector3(0, -500, 0)
				b.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		var src: Array = _near[i]
		var xf := Transform3D()
		var body_name := ""
		if int(src[0]) in [0, 2]:
			var tr := _traffic(int(src[0]))
			if tr == null:
				continue
			var cid := int(src[1])
			xf = traffic_xf(tr, cid)
			if cid >= 0 and cid < tr.c_kind.size():
				body_name = _kind_body(tr.c_kind[cid])
		else:
			if it == null:
				continue
			var ic: Dictionary = src[1]
			xf = it.car_xf(ic)
			body_name = _kind_body(int(ic.get("kind", -1)))
		var sh_entry := _shape_for(body_name)
		var cs := _body_shapes[i]
		if cs.shape != sh_entry[0]:
			cs.shape = sh_entry[0]
			cs.position.y = float(sh_entry[1])
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.global_transform = xf
