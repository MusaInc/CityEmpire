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

var game: EmpireGame
var _bodies: Array = []        # AnimatableBody3D
var _near: Array = []          # [[source, id]]: source 0 = city Traffic (id = car), 1 = island (id = car dict)
var _list_t := 0.0


func setup(g: EmpireGame) -> void:
	game = g
	process_physics_priority = -5
	for i in POOL:
		var b := AnimatableBody3D.new()
		b.name = "TrafficBody%d" % i
		b.sync_to_physics = false
		b.collision_layer = Car.BODY_LAYER
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = HALF * 2.0
		cs.shape = sh
		cs.position = Vector3(0, HALF.y + 0.15, 0)
		b.add_child(cs)
		b.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(b)
		b.top_level = true
		b.global_position = Vector3(0, -500, 0)
		_bodies.append(b)


## City traffic cars that currently have a body: [[id, Transform3D]] (Wrecks).
func city_cars() -> Array:
	var out: Array = []
	var tr: Traffic = game.world.traffic if game and game.world else null
	if tr == null:
		return out
	for src in _near:
		if int(src[0]) == 0 and not tr.knocked.has(int(src[1])):
			out.append([int(src[1]), traffic_xf(tr, int(src[1]))])
	return out


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
func drop(id: int) -> void:
	for i in _near.size():
		var src: Array = _near[i]
		if int(src[0]) == 0 and int(src[1]) == id:
			_near[i] = [-1, 0]   # (body i stays parked until the next listing)
			var b: AnimatableBody3D = _bodies[i]
			b.global_position = Vector3(0, -500, 0)
			b.process_mode = Node.PROCESS_MODE_DISABLED
			break


func _here() -> Vector3:
	var vn := game.vehicle_node()
	return vn.global_position if vn else game.player.global_position


func _island() -> IslandTraffic:
	return get_tree().get_first_node_in_group("island_traffic") as IslandTraffic


func _physics_process(dt: float) -> void:
	if game == null or game.world == null:
		return
	var here := _here()
	var tr: Traffic = game.world.traffic
	var it := _island()
	if it:
		var vn := game.vehicle_node()
		it.blocker = vn.global_position if vn else Vector3(INF, 0, INF)
	_list_t -= dt
	if _list_t <= 0.0:
		_list_t = LIST_EVERY
		var cand: Array = []
		if tr:
			for id in tr.car_count():
				if tr.knocked.has(id):
					continue
				var d := tr.car_position(id).distance_squared_to(here)
				if d < RANGE * RANGE:
					cand.append([d, 0, id])
		if it:
			for c in it.cars:
				if float(c["wait"]) > 0.0:
					continue
				var p: Vector3 = it.car_xf(c).origin
				var d2 := p.distance_squared_to(here)
				if d2 < RANGE * RANGE:
					cand.append([d2, 1, c])
		cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		_near = cand.slice(0, POOL).map(func(x): return [x[1], x[2]])
		# City traffic brakes for your vehicle in its lane (and queues).
		if tr:
			var vn := game.vehicle_node()
			var ids: Array = []
			for x in cand:
				if int(x[1]) == 0 and float(x[0]) < 40.0 * 40.0:
					ids.append(int(x[2]))
			tr.yield_to(vn.global_position if vn else game.player.global_position, ids)   # (people crossing too)
	for i in POOL:
		var b: AnimatableBody3D = _bodies[i]
		if i >= _near.size():
			if b.process_mode != Node.PROCESS_MODE_DISABLED:
				b.global_position = Vector3(0, -500, 0)
				b.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		var src: Array = _near[i]
		if int(src[0]) < 0:
			continue
		var xf := Transform3D()
		if int(src[0]) == 0:
			if tr == null:
				continue
			xf = traffic_xf(tr, int(src[1]))
		else:
			if it == null:
				continue
			xf = it.car_xf(src[1])
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.global_transform = xf
