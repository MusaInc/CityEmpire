class_name AirTraffic
extends Node3D
## Scripted airliners at Skyport (shared world dressing; no physics, no AI):
## each runs a fixed cycle – approach over the sea, touch down, roll out,
## taxi to its stand, wait, push back, taxi to the runway, take off, climb
## out and away – as a timeline of keyframed segments evaluated from the
## clock. Two planes, offset in time, share the runway. Only animated
## within ACTIVE m of the camera; beyond that they're hidden (cost: two
## MultiMesh-free meshes and a few vector lerps a frame).

const ACTIVE := 3200.0
const CYCLE := 300.0      # s for one full arrival + departure

var _planes: Array = []   # [Node3D, time offset, stand]
var _paths: Array = []    # per plane: [[t0, p0, p1, yaw0, yaw1], ...] in cycle seconds
var _t := float(OS.get_environment("AIR_T")) if OS.has_environment("AIR_T") else 0.0   # (captures: start mid-cycle)


func setup(P: Dictionary) -> void:
	var rw: Dictionary = P["runway"]
	var a: Vector3 = rw["from"]
	var b: Vector3 = rw["to"]
	var stands: Array = P["stands"]
	for k in 2:
		var stand: Vector3 = (stands[1 + k * 2] as Array)[0]
		var node := CraftModels.build("plane", "liner", {"size": Vector3(34, 9, 36), "jet": true,
			"paint": Color(0.94, 0.94, 0.95), "trim": [Color(0.12, 0.32, 0.6), Color(0.62, 0.14, 0.18)][k]})
		node.scale = Vector3.ONE
		add_child(node)
		_planes.append([node, k * CYCLE * 0.5, stand])
		_paths.append(_timeline(a, b, stand))


## Arrival from the east over the sea (land westbound), departure eastbound
## out over the sea again.
func _timeline(a: Vector3, b: Vector3, stand: Vector3) -> Array:
	var y := a.y
	var east := -PI * 0.5          # (yaw facing +x)
	var north := 0.0
	var tw := Vector3(stand.x, y, 395.0)   # taxiway abeam the stand
	var segs: Array = []
	var t := [0.0]   # (lambdas capture locals by value: keep the clock in an array)
	var add := func(dur: float, p0: Vector3, p1: Vector3, y0: float, y1: float) -> void:
		segs.append([t[0], t[0] + dur, p0, p1, y0, y1])
		t[0] += dur
	var west := PI * 0.5
	# Arrive over the open sea from the east, land westbound (never over the
	# city's towers), roll out, turn off onto the taxiway to the stand.
	add.call(40.0, b + Vector3(2600, 180, 0), b + Vector3(60, 14, 0), west, west)
	add.call(4.0, b + Vector3(60, 14, 0), b + Vector3(-120, 0.2, 0), west, west)
	add.call(16.0, b + Vector3(-120, 0.2, 0), Vector3(stand.x - 140.0, y + 0.2, a.z), west, west)
	add.call(10.0, Vector3(stand.x - 140.0, y + 0.2, a.z), Vector3(stand.x - 140.0, y + 0.2, 395.0), west, north)
	add.call(14.0, Vector3(stand.x - 140.0, y + 0.2, 395.0), tw + Vector3(0, 0.2, 0), north, east)
	add.call(8.0, tw + Vector3(0, 0.2, 0), stand + Vector3(0, 0.2, 10.0), east, north)
	add.call(90.0, stand + Vector3(0, 0.2, 10.0), stand + Vector3(0, 0.2, 10.0), north, north)   # turnaround
	add.call(10.0, stand + Vector3(0, 0.2, 10.0), tw + Vector3(0, 0.2, 0), north, east)   # push back + taxi
	add.call(18.0, tw + Vector3(0, 0.2, 0), Vector3(a.x + 40.0, y + 0.2, 395.0), east, -east)
	add.call(10.0, Vector3(a.x + 40.0, y + 0.2, 395.0), a + Vector3(40, 0.2, 0), -east, east)
	add.call(26.0, a + Vector3(40, 0.2, 0), a + Vector3(620, 0.2, 0), east, east)          # takeoff roll
	add.call(40.0, a + Vector3(620, 0.2, 0), b + Vector3(2400, 320, -400), east, east)     # climb out
	return segs


func _process(dt: float) -> void:
	_t += dt
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for i in _planes.size():
		var pl: Array = _planes[i]
		var node: Node3D = pl[0]
		var segs: Array = _paths[i]
		var total: float = (segs[segs.size() - 1] as Array)[1]
		var ct := fposmod(_t + float(pl[1]), CYCLE)
		node.visible = ct < total
		if not node.visible:
			continue
		for s: Array in segs:
			if ct >= float(s[0]) and ct < float(s[1]):
				var u := (ct - float(s[0])) / maxf(float(s[1]) - float(s[0]), 0.001)
				var e := u * u * (3.0 - 2.0 * u) if (s[2] as Vector3).y < 20.0 and (s[3] as Vector3).y < 20.0 else u
				var p := (s[2] as Vector3).lerp(s[3], e)
				var yaw := lerp_angle(float(s[4]), float(s[5]), smoothstep(0.0, 1.0, u))
				var d := (s[3] as Vector3) - (s[2] as Vector3)
				var pitch := clampf(atan2(d.y, Vector2(d.x, d.z).length() + 0.01) * 0.8, -0.12, 0.25)
				node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), p)
				break
		if node.global_position.distance_to(cam.global_position) > ACTIVE:
			node.visible = false
