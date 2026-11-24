class_name IslandLife
extends Node3D
## Small moving things that make Skyport Island look worked (part of its
## near content; all cheap transforms, no physics):
##   * moored boats bobbing at the marina's free berths (CraftModels);
##   * the two quay cranes' trolleys running out along their booms and back,
##     a container hanging under each;
##   * a baggage tug with two carts looping the terminal apron;
##   * a truck backing in and out of the distribution centre's bays.

var _boats: Array = []      # [Node3D, base Vector3, phase]
var _trolleys: Array = []   # [Node3D, x]
var _tug: Node3D
var _tug_yaw := 0.0
var _tug_init := false
var _truck: Node3D
var _t := 0.0


func setup(P: Dictionary) -> void:
	var berths: Array = P["berths"]
	var models := [["dart", Color(0.75, 0.2, 0.15)], ["swift", Color(0.1, 0.18, 0.32)], ["dart", Color(0.2, 0.45, 0.35)],
		["swift", Color(0.9, 0.9, 0.88)]]
	for i in models.size():
		var b: Array = berths[(i * 3 + 2) % berths.size()]   # (the far end of each pier; buyers' berths come first)
		var m: Array = models[i]
		var spec := SkyportPlay.craft_spec(String(m[0]))
		spec["paint"] = m[1]
		var n := CraftModels.build("boat", String(m[0]), spec)
		add_child(n)
		var base: Vector3 = (b[0] as Vector3) + Vector3(0, 0.05, 0)
		n.transform = Transform3D(Basis(Vector3.UP, float(b[1])), base)
		_boats.append([n, base, float(i) * 1.7])
	for cx: float in [2230.0, 2370.0]:
		var tr := _box_node(Vector3(4.0, 1.4, 4.0), Color(0.3, 0.3, 0.32))
		var cont := _box_node(Vector3(2.4, 2.6, 12.0), [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.6)][int(cx) % 2])
		cont.position += Vector3(0, -10.4, 0)
		tr.add_child(cont)
		add_child(tr)
		_trolleys.append([tr, cx])
	_tug = Node3D.new()
	_tug.add_child(_box_node(Vector3(1.8, 1.4, 3.0), Color(0.92, 0.75, 0.15)))
	for k in 2:
		var cart := _box_node(Vector3(1.6, 1.0, 2.6), Color(0.6, 0.62, 0.64))
		cart.position += Vector3(0, -0.2, 3.4 + k * 3.2)
		_tug.add_child(cart)
	add_child(_tug)
	_truck = Node3D.new()
	_truck.add_child(_box_node(Vector3(2.5, 3.2, 3.0), Color(0.85, 0.85, 0.86)))
	var trailer := _box_node(Vector3(2.5, 3.6, 12.0), Color(0.9, 0.9, 0.88))
	trailer.position += Vector3(0, 0.2, -7.8)   # (cab faces the road, trailer to the bay)
	_truck.add_child(trailer)
	add_child(_truck)


static func _box_node(size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	bm.material = m
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	return mi


func _process(dt: float) -> void:
	_t += dt
	var y := SkyportIsland.LAND_Y
	for b in _boats:
		var n: Node3D = b[0]
		var base: Vector3 = b[1]
		var ph: float = b[2]
		n.position = base + Vector3(0, 0.08 * sin(_t * 1.2 + ph) + 0.04 * sin(_t * 2.7 + ph), 0)
		n.rotation.z = 0.03 * sin(_t * 0.9 + ph)
		n.rotation.x = 0.02 * sin(_t * 1.4 + ph * 2.0)
	for tr in _trolleys:
		# Out along the boom over the water and back (a 40 s cycle).
		var u := 0.5 - 0.5 * cos(_t * TAU / 40.0 + float(tr[1]) * 0.01)
		(tr[0] as Node3D).position = Vector3(float(tr[1]), y + 41.0, lerpf(-275.0, -380.0, u))
	# Tug: smooth stadium loop along the stands and back along the terminal (90 s),
	# with semicircular 6 m turns at each end and interpolated yaw (no 90° corner snaps).
	var rad := 6.0
	var straight := 288.0
	var arc := PI * rad
	var total := 2.0 * (straight + arc)
	var dist := fposmod(_t / 90.0, 1.0) * total
	var pos := Vector3.ZERO
	var dir := Vector3.RIGHT
	if dist < straight:
		pos = Vector3(1996.0 + dist, y, 262.0)
		dir = Vector3(1.0, 0.0, 0.0)
	elif dist < straight + arc:
		var ang := (dist - straight) / rad
		pos = Vector3(2284.0 + sin(ang) * rad, y, 256.0 + cos(ang) * rad)
		dir = Vector3(cos(ang), 0.0, -sin(ang))
	elif dist < 2.0 * straight + arc:
		var u2 := dist - straight - arc
		pos = Vector3(2284.0 - u2, y, 250.0)
		dir = Vector3(-1.0, 0.0, 0.0)
	else:
		var ang2 := (dist - 2.0 * straight - arc) / rad
		pos = Vector3(1996.0 - sin(ang2) * rad, y, 256.0 - cos(ang2) * rad)
		dir = Vector3(-cos(ang2), 0.0, sin(ang2))
	var target_yaw := atan2(-dir.x, -dir.z)
	if not _tug_init:
		_tug_yaw = target_yaw
		_tug_init = true
	else:
		_tug_yaw = lerp_angle(_tug_yaw, target_yaw, 1.0 - exp(-dt * 4.5))
	_tug.transform = Transform3D(Basis(Vector3.UP, _tug_yaw), pos)
	# Truck: backs into a bay and pulls out again (60 s).
	var tt := fposmod(_t, 60.0)
	var k := smoothstep(0.0, 15.0, tt) * (1.0 - smoothstep(35.0, 50.0, tt))
	_truck.transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(2170, y, lerpf(-150.0, -72.0, k)))
