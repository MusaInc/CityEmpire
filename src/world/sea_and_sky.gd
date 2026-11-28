class_name SeaAndSky
extends Node3D
## Life on the water and in the air round the island – all visual (no
## collision, no physics): nothing here can change a swing, a recorded
## course or a bot run.
##
##   * The port: container ships come in from the open sea up the strait to a
##     berth along the docks quay, lie there a while, are turned by their tugs
##     and steam back out to sea. More ships pass along the shipping lanes
##     east and north of the island.
##   * Boats: motor boats and yachts cruising loops round the bays, with a
##     white wake.
##   * The sky: a news helicopter circling the business district, an airliner
##     crossing high over the city every couple of minutes, and gulls wheeling
##     over the beach, the docks, the marina and behind the ships.
##   * Navigation lights (red / green / white, the helicopter's beacon) glow at
##     night (set_night).
##
## Meshes are procedural (SurfaceTool boxes and prisms, vertex colours): a
## ship is a few hundred triangles. Routes are checked against
## CityLayout.is_water when built; a route that would touch land is dropped.

const SEA_Y := -1.6              # the drawn sea surface (CityWorld._build_water)
const SHIP_SPEED := 7.0          # m/s at sea (~14 knots)
const BERTH_TIME := 75.0         # s alongside before the tugs turn her
const TURN_TIME := 40.0          # s to swing her round at the berth
const HULLS := [Color(0.12, 0.16, 0.24), Color(0.55, 0.1, 0.08), Color(0.1, 0.1, 0.11), Color(0.16, 0.3, 0.42),
	Color(0.2, 0.32, 0.22)]
const BOX_COLORS := [Color(0.72, 0.18, 0.12), Color(0.12, 0.32, 0.55), Color(0.85, 0.6, 0.12),
	Color(0.2, 0.45, 0.3), Color(0.82, 0.82, 0.8), Color(0.45, 0.22, 0.4), Color(0.9, 0.4, 0.12), Color(0.3, 0.3, 0.33)]
const WHITE := Color(0.93, 0.93, 0.9)

var layout: CityLayout
var rng := RandomNumberGenerator.new()
var _mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _wake_mat: StandardMaterial3D
var _ships: Array = []     # {node, path, s, state, t, speed, len, dir, bob}
var _boats: Array = []     # {node, c, r, a, w, bob}
var _heli: Node3D
var _heli_rotor: Node3D
var _heli_tail: Node3D
var _heli_a := 0.0
var _plane: Node3D
var _plane_t := 0.0
var _plane_from := Vector3.ZERO
var _plane_dir := Vector3.FORWARD
var _blinkers: Array[Node3D] = []
var _time := 0.0


func setup(l: CityLayout) -> void:
	layout = l
	rng.seed = l.seed * 53 + 11
	_materials()
	_port_ships()
	_lane_ships()
	_boats_on_loops()
	_helicopter()
	_airliner()
	_gulls()
	print("SeaAndSky: %d ships, %d boats, helicopter, airliner" % [_ships.size(), _boats.size()])


func set_night(n: float) -> void:
	if _lamp_mat:
		# Unshaded materials ignore emission_energy_multiplier; scale HDR albedo directly.
		var glow := lerpf(0.75, 3.6, n)
		_lamp_mat.albedo_color = Color(glow, glow, glow)
	if _wake_mat:
		# Dim unshaded foam wakes at night so they don't glow pure white on dark water.
		var wk := lerpf(1.0, 0.28, n)
		_wake_mat.albedo_color = Color(wk, wk, wk, 1.0)


# ------------------------------------------------------------ materials
func _materials() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.75
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.vertex_color_use_as_albedo = true
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	_lamp_mat.emission = Color(1, 1, 1)
	_lamp_mat.emission_energy_multiplier = 0.4
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wake_mat = StandardMaterial3D.new()
	_wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wake_mat.vertex_color_use_as_albedo = true
	_wake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


# ------------------------------------------------------------ mesh kit
## Axis-aligned box (in the part's own frame) into a SurfaceTool.
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, xf := Transform3D.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, [Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]],
		[Vector3.LEFT, [Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]],
		[Vector3.UP, [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
		[Vector3.DOWN, [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
		[Vector3.BACK, [Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)]],
		[Vector3.FORWARD, [Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)]],
	]
	for f in faces:
		var n: Vector3 = xf.basis * (f[0] as Vector3)
		var q: Array = f[1]
		var p: Array = []
		for v: Vector3 in q:
			p.append(xf * (c + v * h))
		for idx in [0, 2, 1, 0, 3, 2]:  # (front faces wind clockwise)
			st.set_color(col)
			st.set_normal(n.normalized())
			st.add_vertex(p[idx])


## A vertical prism over a convex outline (xz), y0..y1.
static func _prism(st: SurfaceTool, pts: PackedVector2Array, y0: float, y1: float, col: Color, top_col := Color.TRANSPARENT) -> void:
	var n := pts.size()
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= n
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var nrm := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		if Vector2(nrm.x, nrm.z).dot((a + b) * 0.5 - c) < 0.0:
			nrm = -nrm
		var quad := [Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y)]
		var order := [0, 1, 2, 0, 2, 3]
		if ((quad[1] as Vector3) - quad[0]).cross((quad[2] as Vector3) - quad[0]).dot(nrm) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for idx in order:
			st.set_color(col)
			st.set_normal(nrm)
			st.add_vertex(quad[idx])
		# Deck: a fan from the centre.
		var tc := top_col if top_col.a > 0.0 else col
		var t := [Vector3(c.x, y1, c.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y)]
		var to := [0, 1, 2] if ((t[1] as Vector3) - t[0]).cross((t[2] as Vector3) - t[0]).y < 0.0 else [0, 2, 1]
		for idx in to:
			st.set_color(tc)
			st.set_normal(Vector3.UP)
			st.add_vertex(t[idx])


func _mesh_node(st: SurfaceTool, mat: Material, name_: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


## A hull outline: straight sides, a pointed bow at -Z, a squarer stern.
static func _hull_outline(length: float, beam: float, bow := 0.18) -> PackedVector2Array:
	var h := length * 0.5
	var b := beam * 0.5
	return PackedVector2Array([Vector2(0, -h), Vector2(b, -h + length * bow), Vector2(b, h - 2.0),
		Vector2(b * 0.85, h), Vector2(-b * 0.85, h), Vector2(-b, h - 2.0), Vector2(-b, -h + length * bow)])


const CARGO_SHIP_GLB := "res://assets/models/cargo_ship.glb"
static var _cargo_ship_scene: PackedScene


# ------------------------------------------------------------ ships
## A detailed container ship (Blender GLB, canonical 100 m length) facing -Z,
## waterline at y = 0, with navigation lights and speed-reactive water wake.
func _container_ship(length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Ship"
	var scale_k := length / 100.0
	var beam := 16.5 * scale_k
	if _cargo_ship_scene == null and ResourceLoader.exists(CARGO_SHIP_GLB):
		_cargo_ship_scene = load(CARGO_SHIP_GLB) as PackedScene
	if _cargo_ship_scene:
		var model := _cargo_ship_scene.instantiate() as Node3D
		model.name = "Hull"
		model.scale = Vector3(scale_k, scale_k, scale_k)
		VehicleTex.dress(model, "cargo_ship")
		# Disable shadows on distant ocean vessels for mobile GPU efficiency.
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(model)
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hull: Color = HULLS[rng.randi() % HULLS.size()]
		_prism(st, _hull_outline(length, beam + 0.3), -3.0, 1.2, Color(0.55, 0.12, 0.1))
		_prism(st, _hull_outline(length, beam), 1.2, 7.0, hull, Color(0.32, 0.3, 0.28))
		root.add_child(_mesh_node(st, _mat, "Hull"))
	var sz := 29.0 * scale_k
	var lamps := SurfaceTool.new()
	lamps.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(lamps, Vector3(beam * 0.5 + 1.1 * scale_k, 15.8 * scale_k, sz - 2.0 * scale_k), Vector3(0.6, 0.6, 0.6), Color(0.1, 0.9, 0.2))   # starboard green
	_box(lamps, Vector3(-beam * 0.5 - 1.1 * scale_k, 15.8 * scale_k, sz - 2.0 * scale_k), Vector3(0.6, 0.6, 0.6), Color(0.95, 0.1, 0.08))  # port red
	_box(lamps, Vector3(0, 20.1 * scale_k, sz - 1.2 * scale_k), Vector3(0.7, 0.7, 0.7), Color(1, 1, 0.92))   # masthead
	_box(lamps, Vector3(0, 7.2 * scale_k, length * 0.49), Vector3(0.7, 0.7, 0.5), Color(1, 1, 0.92))  # stern
	_box(lamps, Vector3(0, 13.5 * scale_k, -length * 0.45), Vector3(0.6, 0.6, 0.6), Color(1, 1, 0.92))  # bow
	root.add_child(_mesh_node(lamps, _lamp_mat, "Lights"))
	root.add_child(_wake(beam * 1.15, length * 1.75, length * 0.48))
	return root


## A realistic dual-layer V foam wake (bow Kelvin wave + twin stern propwash)
## trailing astern (z > 0 is behind). Scaled smoothly by vessel speed.
func _wake(width: float, length: float, start: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Color(0.95, 0.98, 1.0, 0.34)
	var mid := Color(0.92, 0.96, 1.0, 0.16)
	var b := Color(0.90, 0.95, 1.0, 0.0)
	var y := 0.16
	# Outer Kelvin V wake
	var pts := [
		Vector3(-width * 0.38, y, start - 2.0), Vector3(width * 0.38, y, start - 2.0),
		Vector3(width * 0.92, y, start + length * 0.45), Vector3(-width * 0.92, y, start + length * 0.45),
		Vector3(width * 1.45, y, start + length), Vector3(-width * 1.45, y, start + length),
	]
	var cols := [a, a, mid, mid, b, b]
	for idx in [0, 1, 2, 0, 2, 3, 3, 2, 4, 3, 4, 5]:
		st.set_color(cols[idx])
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[idx])
	# Brighter inner stern propwash core
	var c_in := Color(1.0, 1.0, 1.0, 0.42)
	var c_out := Color(1.0, 1.0, 1.0, 0.0)
	var p2 := [
		Vector3(-width * 0.18, y + 0.03, start - 1.0), Vector3(width * 0.18, y + 0.03, start - 1.0),
		Vector3(width * 0.34, y + 0.03, start + length * 0.65), Vector3(-width * 0.34, y + 0.03, start + length * 0.65),
	]
	var c2 := [c_in, c_in, c_out, c_out]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(c2[idx])
		st.set_normal(Vector3.UP)
		st.add_vertex(p2[idx])
	var mi := _mesh_node(st, _wake_mat, "Wake")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Smooth Catmull-Rom maritime spline so ships follow realistic wide turning arcs.
static func _smooth_path(pts: PackedVector3Array, step := 24.0) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector3Array()
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		var seg_len := p1.distance_to(p2)
		var steps := maxi(2, int(ceil(seg_len / step)))
		for k in steps:
			var t := float(k) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			q.y = 0.0
			out.append(q)
	out.append(pts[-1])
	return out


## Full-hull clearance check: tests the ship's ENTIRE rectangular footprint
## (bow, stern, port/starboard quarters + safety margin) against all landmasses
## (Commercial Island, Westbank, Skyport Island, Landforms) AND suspension bridge piers.
func _hull_water_ok(p: Vector3, yaw: float, length: float, beam: float, margin: float) -> bool:
	var hl := length * 0.5 + margin
	var hb := beam * 0.5 + margin
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	for zi: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for xi: float in [-1.0, 0.0, 1.0]:
			var pt: Vector3 = p + fwd * (zi * hl) + right * (xi * hb)
			if not layout.is_water(pt):
				return false
			# Keep clear of the suspension bridge tower piers at x = -80 and -340, z = -17.
			if absf(pt.z - CityLayout.BRIDGE_Z) < 28.0:
				for tx: float in CityLayout.BRIDGE_TOWERS:
					if absf(pt.x - tx) < 24.0:
						return false
	return true


## Validate an entire maritime route accounting for full hull dimensions + shoreline margin.
func _route_ok_hull(pts: PackedVector3Array, length: float, beam: float, margin: float) -> bool:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		var yaw := atan2(-d.x, -d.z)
		var n := maxi(1, int(ceil(a.distance_to(b) / 20.0)))
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			if not _hull_water_ok(p, yaw, length, beam, margin):
				return false
	return true


func _add_ship(path: PackedVector3Array, length: float, mode: String, start_s := 0.0) -> void:
	var node := _container_ship(length)
	add_child(node)
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	_ships.append({"node": node, "path": path, "total": total, "s": clampf(start_s, 0.0, total), "dir": 1.0, "state": "sail",
		"t": 0.0, "mode": mode, "len": length, "beam": 16.5 * (length / 100.0), "yaw": 0.0,
		"phase": rng.randf() * TAU, "speed": SHIP_SPEED})
	_place_ship(_ships[-1], 0.0, true)


## The port: a 104 m coastal container feeder working the docks quay berth.
## Approaches straight down the deep-water strait centre (x = -210, dead centre
## between the suspension bridge towers, air-draft < 20.5 m clearing the 22 m
## railway bridge), eases parallel alongside the quay, and backs astern out into
## the strait before heading north to sea (never swinging its hull into land).
func _port_ships() -> void:
	var ship_len := 104.0
	var ship_beam := 16.5 * (ship_len / 100.0)
	var berth_x := CityLayout.RIVER_EDGE - (ship_beam * 0.5 + 8.0)   # parallel alongside quay with clean fender gap
	var raw := PackedVector3Array([
		Vector3(2600, 0, -1450),
		Vector3(600, 0, -1400),
		Vector3(-210, 0, -1100),
		Vector3(-210, 0, -450),
		Vector3(-210, 0, 120),
		Vector3(-120, 0, 310),
		Vector3(berth_x, 0, 405),
		Vector3(berth_x, 0, 455),
	])
	var path := _smooth_path(raw, 22.0)
	# Validate every point up to the quay approach with full hull footprint.
	if _route_ok_hull(path.slice(0, maxi(2, path.size() - 3)), ship_len, ship_beam, 6.0):
		_add_ship(path, ship_len, "port", 1650.0)
	else:
		push_warning("SeaAndSky: port route failed full-hull clearance; skipping port ship")


## Open-ocean shipping lanes well clear of Commercial Island, Westbank, and Skyport Island.
func _lane_ships() -> void:
	var lanes := [
		[PackedVector3Array([Vector3(2400, 0, -3200), Vector3(2400, 0, 3200)]), 0.0],
		[PackedVector3Array([Vector3(2750, 0, 3200), Vector3(2750, 0, -3200)]), 2400.0],
		[PackedVector3Array([Vector3(3200, 0, -1550), Vector3(-220, 0, -1550)]), 1200.0],
		[PackedVector3Array([Vector3(1400, 0, 2650), Vector3(3200, 0, 2650)]), 600.0],
	]
	for ln in lanes:
		var pth: PackedVector3Array = ln[0]
		var slen := rng.randf_range(165.0, 210.0)
		var sbeam := 16.5 * (slen / 100.0)
		if _route_ok_hull(pth, slen, sbeam, 35.0):
			_add_ship(pth, slen, "lane", ln[1])


func _place_ship(sh: Dictionary, dt: float, snap := false) -> void:
	var path: PackedVector3Array = sh["path"]
	var s: float = sh["s"]
	var p := path[0]
	var tangent := Vector3.FORWARD
	var acc := 0.0
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if s <= acc + seg or i == path.size() - 2:
			var k := clampf((s - acc) / maxf(seg, 0.001), 0.0, 1.0)
			p = path[i].lerp(path[i + 1], k)
			tangent = (path[i + 1] - path[i]).normalized()
			break
		acc += seg
	# Port ship backs astern off the quay while close to the berth (keeping its
	# hull parallel to the shore) and only rotates once clear in the wide strait.
	var reverse_astern := String(sh["mode"]) == "port" and float(sh["dir"]) < 0.0 and (float(sh["total"]) - s) < 340.0
	var want_yaw := atan2(-tangent.x, -tangent.z) if (float(sh["dir"]) > 0.0 or reverse_astern) else atan2(tangent.x, tangent.z)
	var y: float = sh["yaw"]
	if snap:
		y = want_yaw
	else:
		var rate := deg_to_rad(5.5) if String(sh["state"]) != "turn" else deg_to_rad(7.0)
		y += clampf(wrapf(want_yaw - y, -PI, PI), -rate * dt, rate * dt)
	sh["yaw"] = y
	# Subtle realistic buoyancy: coupled heave, pitch, and gentle roll (calmer when berthed).
	var ph: float = sh["phase"] + _time * 0.42
	var calm := 0.35 if String(sh["state"]) == "berth" else 1.0
	var pitch := sin(ph * 0.95) * 0.010 * calm
	var roll := sin(ph * 0.68 + 0.9) * 0.018 * calm
	var heave := sin(ph * 1.15) * 0.20 * calm
	var n: Node3D = sh["node"]
	n.transform = Transform3D(Basis.from_euler(Vector3(pitch, y, roll)),
		Vector3(p.x, SEA_Y + heave, p.z))
	var wake := n.get_node_or_null("Wake") as Node3D
	if wake:
		var sp_k := clampf(float(sh["speed"]) / SHIP_SPEED, 0.0, 1.0)
		wake.visible = String(sh["state"]) == "sail" and sp_k > 0.12 and not reverse_astern
		wake.scale = Vector3(lerpf(0.65, 1.0, sp_k), 1.0, lerpf(0.35, 1.0, sp_k))


func _update_ship(sh: Dictionary, dt: float) -> void:
	var total: float = sh["total"]
	match String(sh["state"]):
		"sail":
			var s: float = sh["s"]
			var to_end := (total - s) if float(sh["dir"]) > 0.0 else s
			var spd := SHIP_SPEED
			if sh["mode"] == "port":
				# Realistic port speed profile: slow tug-assisted docking & astern undocking.
				var dist_berth := total - s
				spd = lerpf(1.4, SHIP_SPEED, clampf(dist_berth / 480.0, 0.0, 1.0))
				if float(sh["dir"]) < 0.0 and dist_berth < 340.0:
					spd = minf(spd, 3.8)
			sh["speed"] = spd
			sh["s"] = clampf(s + spd * dt * float(sh["dir"]), 0.0, total)
			if to_end <= 0.05:
				if sh["mode"] == "lane":
					sh["s"] = 0.0
					_place_ship(sh, 0.0, true)
					return
				if float(sh["dir"]) > 0.0:
					sh["state"] = "berth"
					sh["t"] = 0.0
				else:
					sh["state"] = "away"
					sh["t"] = 0.0
		"berth":
			sh["speed"] = 0.0
			sh["t"] = float(sh["t"]) + dt
			if float(sh["t"]) > BERTH_TIME:
				# Back astern off the quay into the deep-water channel (never spin into land).
				sh["state"] = "sail"
				sh["dir"] = -1.0
				sh["t"] = 0.0
		"away":
			sh["t"] = float(sh["t"]) + dt
			if float(sh["t"]) > 90.0:
				sh["state"] = "sail"
				sh["dir"] = 1.0
				sh["s"] = 0.0
				_place_ship(sh, 0.0, true)
				return
	_place_ship(sh, dt)


# ------------------------------------------------------------ boats
func _motorboat(length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Boat"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hull: Color = WHITE if rng.randf() < 0.7 else [Color(0.15, 0.25, 0.45), Color(0.6, 0.12, 0.1)][rng.randi() % 2]
	_prism(st, _hull_outline(length, length * 0.34, 0.3), -0.4, 1.0, hull, Color(0.7, 0.6, 0.45))
	_box(st, Vector3(0, 1.7, length * 0.08), Vector3(length * 0.24, 1.4, length * 0.3), WHITE)
	_box(st, Vector3(0, 1.75, length * 0.08 - length * 0.15), Vector3(length * 0.23, 0.8, 0.15), Color(0.1, 0.13, 0.16))
	root.add_child(_mesh_node(st, _mat, "Hull"))
	root.add_child(_wake(length * 0.4, length * 4.0, length * 0.5))
	return root


func _yacht(length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Boat"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(st, _hull_outline(length, length * 0.3, 0.32), -0.5, 0.9, WHITE, Color(0.72, 0.6, 0.42))
	_box(st, Vector3(0, 1.3, length * 0.1), Vector3(length * 0.2, 0.8, length * 0.25), WHITE)
	var mast_h := length * 1.35
	_box(st, Vector3(0, 0.9 + mast_h * 0.5, -length * 0.08), Vector3(0.18, mast_h, 0.18), Color(0.8, 0.8, 0.8))
	# Mainsail and jib: flat triangles (both sides).
	var sail := Color(0.97, 0.96, 0.92) if rng.randf() < 0.8 else Color(0.9, 0.35, 0.25)
	for tri in [[Vector3(0, 1.6, -length * 0.08), Vector3(0, 0.9 + mast_h * 0.95, -length * 0.08), Vector3(0, 1.6, length * 0.38)],
			[Vector3(0, 1.4, -length * 0.12), Vector3(0, 0.9 + mast_h * 0.8, -length * 0.1), Vector3(0, 1.2, -length * 0.48)]]:
		for side in [1.0, -1.0]:
			for v: Vector3 in (tri if side > 0.0 else [tri[0], tri[2], tri[1]]):
				st.set_color(sail)
				st.set_normal(Vector3(side, 0, 0))
				st.add_vertex(v)
	root.add_child(_mesh_node(st, _mat, "Hull"))
	root.add_child(_wake(length * 0.3, length * 2.5, length * 0.5))
	return root


## Loops in the bays: each an ellipse checked against the coast (shrunk until
## it fits, or dropped).
func _boats_on_loops() -> void:
	var loops := [
		[Vector2(1230, -120), Vector2(140, 320)], [Vector2(1190, 380), Vector2(110, 160)],
		[Vector2(380, -880), Vector2(230, 90)], [Vector2(-210, -330), Vector2(110, 170)],
		[Vector2(-200, 230), Vector2(90, 150)], [Vector2(330, 860), Vector2(260, 110)],
		[Vector2(800, -860), Vector2(160, 80)], [Vector2(-230, 900), Vector2(120, 200)],
	]
	for lp in loops:
		var c: Vector2 = lp[0]
		var r: Vector2 = lp[1]
		var ok := false
		for shrink in [1.0, 0.75, 0.55]:
			ok = true
			for i in 24:
				var a := TAU * i / 24.0
				var p: Vector2 = c + Vector2(cos(a) * r.x, sin(a) * r.y) * shrink
				if not layout.is_water(Vector3(p.x, 0, p.y)) or not layout.is_water(Vector3(p.x + 12, 0, p.y)) \
						or not layout.is_water(Vector3(p.x - 12, 0, p.y)):
					ok = false
					break
			if ok:
				r *= shrink
				break
		if not ok:
			continue
		var yacht := rng.randf() < 0.45
		var length := rng.randf_range(9.0, 14.0) if yacht else rng.randf_range(7.0, 12.0)
		var node := _yacht(length) if yacht else _motorboat(length)
		add_child(node)
		var spd := rng.randf_range(4.0, 6.0) if yacht else rng.randf_range(9.0, 15.0)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		# Angular speed from the mean radius (close enough on an ellipse).
		_boats.append({"node": node, "c": c, "r": r, "a": rng.randf() * TAU, "w": dir * spd / ((r.x + r.y) * 0.5),
			"phase": rng.randf() * TAU, "heel": 0.12 if yacht else 0.04})


func _update_boat(b: Dictionary, dt: float) -> void:
	var a: float = b["a"] + float(b["w"]) * dt
	b["a"] = a
	var c: Vector2 = b["c"]
	var r: Vector2 = b["r"]
	var p := c + Vector2(cos(a) * r.x, sin(a) * r.y)
	var w: float = b["w"]
	var v := Vector2(-sin(a) * r.x, cos(a) * r.y) * signf(w)
	var yaw := atan2(-v.x, -v.y)
	var ph: float = b["phase"] + _time * 1.7
	var heel := float(b["heel"]) * signf(w)
	(b["node"] as Node3D).transform = Transform3D(Basis.from_euler(Vector3(0.03 + sin(ph) * 0.03, yaw, heel + sin(ph * 0.8) * 0.04)),
		Vector3(p.x, SEA_Y + 0.1 + sin(ph * 1.2) * 0.15, p.y))


# ------------------------------------------------------------ aircraft
func _helicopter() -> void:
	var root := Node3D.new()
	root.name = "Helicopter"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.12, 0.2, 0.42)
	_box(st, Vector3(0, 0, 0), Vector3(2.4, 2.4, 5.2), body)                       # cabin
	_box(st, Vector3(0, 0.3, -2.7), Vector3(2.0, 1.6, 0.6), Color(0.12, 0.16, 0.2))  # windscreen
	_box(st, Vector3(0, 0.5, 5.6), Vector3(0.6, 0.7, 6.5), body)                   # tail boom
	_box(st, Vector3(0, 1.5, 8.6), Vector3(0.3, 2.4, 1.2), WHITE)                  # fin
	_box(st, Vector3(0, -0.2, 1.0), Vector3(2.45, 0.5, 2.4), WHITE)                # livery band
	for x in [-1.1, 1.1]:
		_box(st, Vector3(x, -1.75, 0.0), Vector3(0.15, 0.15, 4.4), Color(0.2, 0.2, 0.2))  # skids
		_box(st, Vector3(x, -1.4, 0.0), Vector3(0.12, 0.7, 0.12), Color(0.2, 0.2, 0.2))
	_box(st, Vector3(0, 1.55, 0.3), Vector3(0.4, 0.7, 0.4), Color(0.2, 0.2, 0.2))  # mast
	root.add_child(_mesh_node(st, _mat, "Body"))
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 1.95, 0.3)
	var rs := SurfaceTool.new()
	rs.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(rs, Vector3.ZERO, Vector3(11.0, 0.08, 0.35), Color(0.15, 0.15, 0.15))
	_box(rs, Vector3.ZERO, Vector3(0.35, 0.08, 11.0), Color(0.15, 0.15, 0.15))
	rotor.add_child(_mesh_node(rs, _mat, "Rotor"))
	root.add_child(rotor)
	var tail := Node3D.new()
	tail.position = Vector3(0.35, 1.6, 8.8)
	var ts := SurfaceTool.new()
	ts.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(ts, Vector3.ZERO, Vector3(0.06, 1.8, 0.2), Color(0.15, 0.15, 0.15))
	tail.add_child(_mesh_node(ts, _mat, "TailRotor"))
	root.add_child(tail)
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(ls, Vector3(0, -1.3, 0), Vector3(0.35, 0.25, 0.35), Color(1, 0.1, 0.05))
	var beacon := _mesh_node(ls, _lamp_mat, "Beacon")
	root.add_child(beacon)
	_blinkers.append(beacon)
	add_child(root)
	_heli = root
	_heli_rotor = rotor
	_heli_tail = tail


func _airliner() -> void:
	var root := Node3D.new()
	root.name = "Airliner"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3.ZERO, Vector3(4.0, 4.2, 38.0), WHITE)                        # fuselage
	_box(st, Vector3(0, -0.4, -19.5), Vector3(3.2, 3.2, 2.0), WHITE)               # nose
	_box(st, Vector3(0, 0.6, -20.3), Vector3(2.0, 1.2, 0.6), Color(0.15, 0.18, 0.22))
	_box(st, Vector3(0, -0.8, 1.0), Vector3(36.0, 0.5, 6.0), Color(0.85, 0.86, 0.88))  # wings
	_box(st, Vector3(0, 0.6, 18.0), Vector3(12.0, 0.35, 3.0), Color(0.85, 0.86, 0.88))  # tailplane
	_box(st, Vector3(0, 4.2, 17.5), Vector3(0.4, 6.5, 4.0), Color(0.75, 0.16, 0.12))   # fin
	for x in [-7.5, 7.5]:
		_box(st, Vector3(x, -2.0, -1.0), Vector3(2.0, 2.0, 4.5), Color(0.6, 0.62, 0.66))  # engines
	root.add_child(_mesh_node(st, _mat, "Body"))
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(ls, Vector3(18.0, -0.6, 1.0), Vector3(0.6, 0.6, 0.6), Color(0.1, 0.9, 0.2))
	_box(ls, Vector3(-18.0, -0.6, 1.0), Vector3(0.6, 0.6, 0.6), Color(0.95, 0.1, 0.08))
	var strobe := _mesh_node(ls, _lamp_mat, "NavLights")
	root.add_child(strobe)
	var bs := SurfaceTool.new()
	bs.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(bs, Vector3(0, -2.3, 0), Vector3(0.6, 0.4, 0.6), Color(1, 0.15, 0.1))
	var beacon := _mesh_node(bs, _lamp_mat, "Beacon")
	root.add_child(beacon)
	_blinkers.append(beacon)
	add_child(root)
	_plane = root
	_next_flight()


## A straight pass high over the island on a random heading.
func _next_flight() -> void:
	var ang := rng.randf() * TAU
	var d := Vector3(cos(ang), 0, sin(ang))
	var mid := Vector3(540.0 + rng.randf_range(-300, 300), rng.randf_range(650.0, 950.0), rng.randf_range(-300, 300))
	_plane_from = mid - d * 3200.0
	_plane_dir = d
	_plane_t = -rng.randf_range(10.0, 50.0)  # (a gap between flights)


# ------------------------------------------------------------ gulls
## Bigger, white birds wheeling over the shore, reusing the flock shader.
func _gulls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[Vector3(0, 0, -0.3), Vector3(0.09, 0, 0.0), Vector3(0, 0, 0.32)],
			[Vector3(0, 0, -0.3), Vector3(0, 0, 0.32), Vector3(-0.09, 0, 0.0)],
			[Vector3(0.07, 0, -0.1), Vector3(0.45, 0.06, 0.0), Vector3(0.07, 0, 0.12)],
			[Vector3(0.45, 0.06, 0.0), Vector3(0.75, -0.02, 0.08), Vector3(0.4, 0.05, 0.1)],
			[Vector3(-0.07, 0, -0.1), Vector3(-0.07, 0, 0.12), Vector3(-0.45, 0.06, 0.0)],
			[Vector3(-0.45, 0.06, 0.0), Vector3(-0.4, 0.05, 0.1), Vector3(-0.75, -0.02, 0.08)]]:
		for v in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/world/shaders/birds.gdshader")
	mat.set_shader_parameter("tint", Color(0.88, 0.88, 0.86))
	mesh.surface_set_material(0, mat)
	var spots := [Vector3(380, 22, -720), Vector3(170, 26, 470), Vector3(-60, 18, 200), Vector3(20, 30, 540),
		Vector3(1080, 24, -60), Vector3(620, 30, -700), Vector3(-200, 28, -260)]
	for h: Vector3 in spots:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		var n := rng.randi_range(7, 14)
		mm.instance_count = n
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var base_r := rng.randf_range(18.0, 40.0)
		for i in n:
			var c := h + Vector3(rng.randf_range(-6, 6), rng.randf_range(-5, 8), rng.randf_range(-6, 6))
			mm.set_instance_transform(i, Transform3D(Basis(), c))
			mm.set_instance_custom_data(i, Color(base_r + rng.randf_range(-8.0, 8.0), dir * rng.randf_range(0.25, 0.4),
				rng.randf() * TAU, rng.randf_range(1.0, 3.5)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Gulls"
		mmi.multimesh = mm
		mmi.extra_cull_margin = 60.0
		mmi.visibility_range_end = 520.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# ------------------------------------------------------------ update
func _process(dt: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.global_position.y < -100.0:
		return
	dt = minf(dt, 0.1)
	_time += dt
	for sh in _ships:
		_update_ship(sh, dt)
	for b in _boats:
		_update_boat(b, dt)
	if _heli:
		_heli_a += dt * 32.0 / 260.0
		var c := Vector3(CityLayout.CBD_CENTER.x, 0, CityLayout.CBD_CENTER.y)
		var p := c + Vector3(cos(_heli_a) * 260.0, 235.0 + sin(_heli_a * 2.0) * 12.0, sin(_heli_a) * 260.0)
		var v := Vector3(-sin(_heli_a), 0, cos(_heli_a))
		var yaw := atan2(-v.x, -v.z)
		_heli.transform = Transform3D(Basis.from_euler(Vector3(-0.08, yaw, 0.16)), p)
		_heli_rotor.rotate_y(dt * 28.0)
		_heli_tail.rotate_x(dt * 45.0)
	if _plane:
		_plane_t += dt
		_plane.visible = _plane_t > 0.0
		if _plane_t > 0.0:
			_plane.transform = Transform3D(Basis(Vector3.UP, atan2(-_plane_dir.x, -_plane_dir.z)), _plane_from + _plane_dir * 70.0 * _plane_t)
			if _plane_t * 70.0 > 6400.0:
				_next_flight()
	var on := fmod(_time, 1.2) < 0.12
	for bl in _blinkers:
		bl.visible = on
