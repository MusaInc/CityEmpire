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
		n.global_transform = Transform3D(Basis(Vector3.UP, float(b[1])), base)
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
		(tr[0] as Node3D).position = Vector3(float(tr[1]), y + 41.0, lerpf(-575.0, -680.0, u))
	# Tug: a loop along the stands and back along the terminal (90 s).
	var a := fposmod(_t / 90.0, 1.0)
	var pts := [Vector3(1990, y, 262), Vector3(2290, y, 262), Vector3(2290, y, 250), Vector3(1990, y, 250)]
	var seglen := [300.0, 12.0, 300.0, 12.0]
	var dist := a * 624.0
	var i := 0
	while i < 3 and dist > seglen[i]:
		dist -= seglen[i]
		i += 1
	var p0: Vector3 = pts[i]
	var p1: Vector3 = pts[(i + 1) % 4]
	var dir := (p1 - p0).normalized()
	_tug.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p0 + dir * dist)
	# Truck: backs into a bay and pulls out again (60 s).
	var tt := fposmod(_t, 60.0)
	var k := smoothstep(0.0, 15.0, tt) * (1.0 - smoothstep(35.0, 50.0, tt))
	_truck.global_transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(2060, y, lerpf(-128.0, -153.0, k)))
