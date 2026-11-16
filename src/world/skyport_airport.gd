class_name SkyportAirport
extends RefCounted
## Skyport's airport, built as part of the island's near content
## (SkyportIsland._start_near), in the island's LOCAL coordinates:
##  * the terminal as a glazed hall – full-height curtain wall with mullions
##    and transoms under the curved roof, a stone plinth, entrance pods on
##    the drop-off side – and jet bridges out to the four gate stands;
##  * airliners parked at the two gates the scripted traffic doesn't use,
##    a regional prop and a business jet on the hangar apron;
##  * a real control tower (octagonal shaft, flared glass cab, roof plant,
##    antennas) instead of a box;
##  * apron floodlight masts (32 m: swing anchors, clear of the taxi lanes);
##  * the Skyport Link: an elevated people mover from the bridge quay along
##    Skyport Avenue and Terminal Road to the terminal, on portal frames over
##    the pavements (never in a lane), two stations, a shuttle running it;
##  * the fuel farm, the airport fire station, a multi-storey car park.
## Everything static is merged per material; tall parts collide (layers 1|2:
## the web catches them).

const GLASS_COL := Color(0.5, 0.64, 0.7)
const STONE := Color(0.8, 0.78, 0.73)
const MULLION := Color(0.84, 0.85, 0.86)
const STANDS_AT := [1990.0, 2080.0, 2170.0, 2260.0]   # gate stands (x), facing the hall
const LINK_Y := 9.0                                   # guideway deck top above the ground
const LINK_W := 6.0


static func glass_material() -> StandardMaterial3D:
	var gm := StandardMaterial3D.new()
	gm.albedo_color = GLASS_COL
	gm.metallic = 0.45
	gm.roughness = 0.14
	return gm


## Box collision from a to c (w across, h up), into body.
static func _col(body: StaticBody3D, a: Vector3, c: Vector3, w: float, h: float) -> void:
	SkyportIsland._box_beam(body, a, c, w, h)


static func _ring(c: Vector2, r: float, n: int, phase := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * (i + phase) / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


# ------------------------------------------------------------- terminal
## The hall's curtain wall (glass), mullions, transoms, plinth and entrance
## pods. The roof and its columns are SkyportIsland's.
static func build_terminal(isl: SkyportIsland, target: Node3D, body: StaticBody3D) -> void:
	var Y := SkyportIsland.LAND_Y
	var hall := Rect2(1962, 168, 296, 68)
	var ring := [Vector2(hall.position.x, hall.position.y), Vector2(hall.end.x, hall.position.y),
		Vector2(hall.end.x, hall.end.y), Vector2(hall.position.x, hall.end.y)]
	var g := SurfaceTool.new()
	g.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := BuildingMesher.new()
	for k in 4:
		var p0: Vector2 = ring[k]
		var p1: Vector2 = ring[(k + 1) % 4]
		var L := p0.distance_to(p1)
		var steps := maxi(1, ceili(L / 6.0))
		for s2 in steps:
			var a2 := p0.lerp(p1, float(s2) / steps)
			var b2 := p0.lerp(p1, float(s2 + 1) / steps)
			var ya := SkyportIsland.terminal_roof_y(a2.x, a2.y) - 0.3
			var yb := SkyportIsland.terminal_roof_y(b2.x, b2.y) - 0.3
			var A0 := Vector3(a2.x, Y + 0.7, a2.y)
			var B0 := Vector3(b2.x, Y + 0.7, b2.y)
			var A1 := Vector3(a2.x, ya, a2.y)
			var B1 := Vector3(b2.x, yb, b2.y)
			for v: Vector3 in [A0, A1, B1, A0, B1, B0, A0, B1, A1, A0, B0, B1]:
				g.add_vertex(v)
			# Mullion at each panel joint (proud of the glass), full height.
			m.beam(Vector3(a2.x, Y + 0.7, a2.y), Vector3(a2.x, ya, a2.y), 0.42, 0.42, MULLION)
		# Transoms: the mezzanine line and the head of the doors.
		for ty: float in [4.6, 9.8]:
			m.beam(Vector3(p0.x, Y + ty, p0.y), Vector3(p1.x, Y + ty, p1.y), 0.36, 0.5, MULLION)
	# Plinth (pale stone) all round.
	m.solid(hall.position.x - 0.6, hall.position.y - 0.6, hall.end.x + 0.6, hall.end.y + 0.6, Y, Y + 0.7, STONE)
	# Entrance pods on the drop-off side: dark glazed vestibules with a lit
	# fascia band, in pairs.
	for x: float in [2010.0, 2056.0, 2142.0, 2188.0, 2234.0]:
		m.solid(x - 3.0, hall.position.y - 3.2, x + 3.0, hall.position.y, Y, Y + 3.6, Color(0.16, 0.2, 0.24))
		m.solid(x - 3.3, hall.position.y - 3.5, x + 3.3, hall.position.y, Y + 3.6, Y + 4.3, Color(0.92, 0.92, 0.9))
	# Airside: the gate lounge floor shows as a dark band behind the glass at
	# the jet bridges' level (the bridges plug into it).
	m.solid(hall.position.x, hall.end.y - 0.4, hall.end.x, hall.end.y + 0.2, Y + 4.2, Y + 4.6, Color(0.5, 0.52, 0.55))
	var gl := MeshInstance3D.new()
	gl.name = "TerminalGlazing"
	g.generate_normals()
	gl.mesh = g.commit()
	gl.material_override = glass_material()
	gl.visibility_range_end = 2000.0
	target.add_child(gl)
	# Jet bridges: a fixed link out of the hall under the roof, the
	# telescoping tunnel to a rotunda leg on wheels, and the cab at the
	# aircraft's front door (parked noses sit at z ≈ 292).
	for sx: float in STANDS_AT:
		var x := sx - 4.2
		var h0 := Y + 4.4
		var p0 := Vector3(x, h0, hall.end.y)
		var p1 := Vector3(x, h0, 252.0)
		var p2 := Vector3(x + 1.0, h0 - 0.4, 284.0)
		m.beam(p0 + Vector3(0, 1.6, 0), p1 + Vector3(0, 1.6, 0), 3.4, 3.2, Color(0.78, 0.8, 0.82))
		m.beam(p1 + Vector3(0, 1.6, 0), p2 + Vector3(0, 1.6, 0), 3.0, 3.0, Color(0.7, 0.72, 0.74))
		m.beam(p1, p1 - Vector3(0, h0 - Y, 0), 1.2, 1.2, Color(0.5, 0.52, 0.55))                 # fixed leg
		m.beam(p2 + Vector3(0, 0.2, -2.0), Vector3(p2.x, Y, p2.z - 2.0), 0.9, 0.9, Color(0.5, 0.52, 0.55))  # drive leg
		m.solid(p2.x - 1.6, p2.z - 3.0, p2.x + 1.6, p2.z - 1.0, Y, Y + 0.9, Color(0.2, 0.2, 0.22))           # bogie
		m.solid(p2.x - 2.2, p2.z - 0.5, p2.x + 2.2, p2.z + 3.2, p2.y, p2.y + 3.4, Color(0.62, 0.64, 0.66))  # cab
		_col(body, p0 + Vector3(0, 1.6, 0), p1 + Vector3(0, 1.6, 0), 3.4, 3.2)
		_col(body, p1 + Vector3(0, 1.6, 0), p2 + Vector3(0, 1.6, 0), 3.0, 3.0)
	isl._mesh_into(m, "Terminal", target, 0.0, 1800.0)


## Parked aircraft: airliners at the gates the scripted traffic leaves free,
## a regional prop and a business jet on the hangar apron.
static func build_parked(P: Dictionary, target: Node3D, isl: SkyportIsland) -> void:
	var stands: Array = P["stands"]
	var Y := SkyportIsland.LAND_Y
	var specs := [
		[0, "liner", {"size": Vector3(34, 9, 37), "jet": true, "paint": Color(0.95, 0.95, 0.96), "trim": Color(0.1, 0.45, 0.42)}],
		[2, "liner", {"size": Vector3(36, 9, 40), "jet": true, "paint": Color(0.94, 0.94, 0.93), "trim": Color(0.85, 0.42, 0.12)}],
		[4, "regional", {"size": Vector3(27, 7, 24), "twin": true, "high_wing": true, "paint": Color(0.93, 0.93, 0.94), "trim": Color(0.2, 0.3, 0.55)}],
		[5, "bizjet", {"size": Vector3(16, 5, 19), "jet": true, "paint": Color(0.96, 0.96, 0.97), "trim": Color(0.25, 0.25, 0.28)}],
	]
	for sp: Array in specs:
		var st: Array = stands[int(sp[0])]
		var pos: Vector3 = st[0]
		var node: Node3D = load("res://src/vehicle/craft_models.gd").build("plane", String(sp[1]), sp[2])   # (loaded, not linked: tools load the island without the game)
		node.name = "Parked_%d" % int(sp[0])
		if int(sp[0]) < 4:
			node.position = Vector3(pos.x, Y + 0.02, pos.z + 10.0)
			node.rotation.y = 0.0
		else:
			node.position = Vector3(pos.x, Y + 0.02, pos.z - 6.0)
			node.rotation.y = PI
		target.add_child(node)
	# Ground equipment round the gate airliners: a belt loader, a catering
	# truck lifted to the rear door, a fuel bowser under the wing.
	var m := BuildingMesher.new()
	for k: int in [0, 2]:
		var p: Vector3 = (stands[k] as Array)[0]
		var cz := p.z + 10.0
		m.solid(p.x + 2.6, cz - 6.0, p.x + 4.2, cz + 1.0, Y, Y + 1.2, Color(0.9, 0.72, 0.12))          # belt loader
		m.beam(Vector3(p.x + 3.4, Y + 1.2, cz - 5.0), Vector3(p.x + 2.2, Y + 2.6, cz + 0.5), 1.0, 0.25, Color(0.2, 0.2, 0.2))
		m.solid(p.x + 2.3, cz + 11.0, p.x + 5.0, cz + 18.0, Y, Y + 1.4, Color(0.92, 0.92, 0.9))        # catering truck
		m.solid(p.x + 2.4, cz + 11.5, p.x + 4.9, cz + 16.0, Y + 1.4, Y + 4.6, Color(0.95, 0.95, 0.95))
		m.solid(p.x - 13.0, cz - 2.0, p.x - 10.0, cz + 6.0, Y, Y + 2.6, Color(0.85, 0.85, 0.82))       # bowser
		m.solid(p.x - 13.0, cz - 3.4, p.x - 10.0, cz - 2.0, Y, Y + 2.2, Color(0.75, 0.15, 0.12))
	isl._mesh_into(m, "GateEquipment", target, 0.0, 900.0)


# ----------------------------------------------------------- the tower
static func build_tower(target: Node3D, isl: SkyportIsland) -> void:
	var Y := SkyportIsland.LAND_Y
	var c := Vector2(2291, 205)
	var m := BuildingMesher.new()
	var conc := Color(0.86, 0.85, 0.82)
	# Base block: the approach-control building the shaft rises from.
	m.solid(2274, 190, 2308, 220, Y, Y + 7.5, Color(0.78, 0.77, 0.74))
	m.solid(2273, 189, 2309, 221, Y + 7.5, Y + 8.1, Color(0.9, 0.9, 0.88))
	m.solid(2274.4, 189.6, 2307.6, 190.0, Y + 1.2, Y + 6.6, Color(0.2, 0.26, 0.3))   # ribbon window
	# Shaft: octagonal, a slight taper in two steps, a vertical service
	# slot (darker) up one face.
	m.prism(_ring(c, 4.6, 8, 0.5), Y + 8.1, Y + 30.0, conc)
	m.prism(_ring(c, 4.2, 8, 0.5), Y + 30.0, Y + 52.0, conc)
	m.solid(c.x - 0.7, c.y - 4.5, c.x + 0.7, c.y - 4.0, Y + 8.1, Y + 52.0, Color(0.32, 0.36, 0.4))
	# Flared underside to the cab: two widening rings.
	m.prism(_ring(c, 6.0, 8, 0.5), Y + 52.0, Y + 53.2, conc)
	m.prism(_ring(c, 8.2, 8, 0.5), Y + 53.2, Y + 54.4, Color(0.92, 0.92, 0.9))
	# Cab roof (oversailing), plant, antennas and a radar.
	m.prism(_ring(c, 9.0, 8, 0.5), Y + 60.6, Y + 61.6, Color(0.92, 0.92, 0.9))
	m.prism(_ring(c, 4.0, 8, 0.5), Y + 61.6, Y + 63.4, Color(0.7, 0.71, 0.72))
	m.beam(Vector3(c.x + 2.0, Y + 63.4, c.y), Vector3(c.x + 2.0, Y + 72.0, c.y), 0.3, 0.3, Color(0.85, 0.2, 0.15))
	m.beam(Vector3(c.x - 2.2, Y + 63.4, c.y + 1.0), Vector3(c.x - 2.2, Y + 68.0, c.y + 1.0), 0.22, 0.22, Color(0.8, 0.8, 0.8))
	m.beam(Vector3(c.x - 1.5, Y + 64.6, c.y - 2.0), Vector3(c.x + 1.5, Y + 64.6, c.y - 2.0), 0.4, 1.4, Color(0.9, 0.9, 0.9))
	isl._mesh_into(m, "Tower", target, 0.0, 4000.0)
	# The cab glass: an outward-leaning octagonal frustum (controllers look
	# down onto the apron), its frames.
	var g := SurfaceTool.new()
	g.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := _ring(c, 7.4, 8, 0.5)
	var hi := _ring(c, 8.6, 8, 0.5)
	var y0 := Y + 54.4
	var y1 := Y + 60.6
	var fr := BuildingMesher.new()
	for i in 8:
		var j := (i + 1) % 8
		var a0 := Vector3(lo[i].x, y0, lo[i].y)
		var b0 := Vector3(lo[j].x, y0, lo[j].y)
		var a1 := Vector3(hi[i].x, y1, hi[i].y)
		var b1 := Vector3(hi[j].x, y1, hi[j].y)
		for v: Vector3 in [a0, a1, b1, a0, b1, b0, a0, b1, a1, a0, b0, b1]:
			g.add_vertex(v)
		fr.beam(a0, a1, 0.25, 0.25, Color(0.25, 0.27, 0.3))
	g.generate_normals()
	var gi := MeshInstance3D.new()
	gi.name = "TowerCab"
	gi.mesh = g.commit()
	gi.material_override = glass_material()
	gi.visibility_range_end = 4000.0
	target.add_child(gi)
	isl._mesh_into(fr, "TowerFrames", target, 0.0, 1500.0)


# ------------------------------------------------------- floodlight masts
static func mast_points() -> Array:
	var pts: Array = []
	for x: float in [1945.0, 2035.0, 2125.0, 2215.0, 2305.0]:
		pts.append(Vector2(x, 336.0))
	for x: float in [1600.0, 1750.0, 1850.0]:
		pts.append(Vector2(x, 372.0))
	pts.append(Vector2(2420.0, 336.0))
	return pts


static func build_masts(target: Node3D, body: StaticBody3D, isl: SkyportIsland) -> void:
	var Y := SkyportIsland.LAND_Y
	var m := BuildingMesher.new()
	var steel := Color(0.62, 0.64, 0.66)
	for p: Vector2 in mast_points():
		var foot := Vector3(p.x, Y, p.y)
		var top := Vector3(p.x, Y + 32.0, p.y)
		m.solid(p.x - 1.2, p.y - 1.2, p.x + 1.2, p.y + 1.2, Y, Y + 0.8, Color(0.75, 0.75, 0.72))   # plinth
		m.beam(foot, top, 0.9, 0.9, steel)
		# Head frame: a lamp bar with six lamps and a service cage.
		m.beam(top + Vector3(-3.0, 0.4, 0), top + Vector3(3.0, 0.4, 0), 0.4, 0.4, steel)
		m.beam(top + Vector3(-3.0, 1.8, 0), top + Vector3(3.0, 1.8, 0), 0.4, 0.4, steel)
		for k in 6:
			var lx := -2.5 + k * 1.0
			m.solid(p.x + lx - 0.38, p.y - 0.9, p.x + lx + 0.38, p.y - 0.2, Y + 32.6, Y + 33.6, Color(0.95, 0.95, 0.85))
		m.solid(p.x - 1.0, p.y - 1.0, p.x + 1.0, p.y + 1.0, Y + 31.0, Y + 31.2, steel)
		_col(body, foot, top + Vector3(0, 2.0, 0), 0.9, 0.9)
		_col(body, top + Vector3(-3.0, 1.1, 0), top + Vector3(3.0, 1.1, 0), 1.0, 1.8)
	isl._mesh_into(m, "FloodMasts", target, 0.0, 2600.0)


# -------------------------------------------------------- Skyport Link
## The people mover's centreline (local, y = deck top): from the station over
## Skyport Avenue by the bridges, along the avenue, round onto Terminal Road
## and down to the terminal station.
static func link_path() -> PackedVector3Array:
	var Y := SkyportIsland.LAND_Y + LINK_Y
	var z0 := SkyportIsland.PIVOT.y
	var pts := PackedVector3Array()
	pts.append(Vector3(1498.0, Y, z0))
	pts.append(Vector3(1866.0, Y, z0))
	# A 24 m radius curve onto Terminal Road (x 1890).
	var cc := Vector2(1866.0, z0 + 24.0)
	for k in range(1, 8):
		var a := -PI * 0.5 + (PI * 0.5) * k / 8.0
		pts.append(Vector3(cc.x + cos(a) * 24.0, Y, cc.y + sin(a) * 24.0))
	pts.append(Vector3(1890.0, Y, z0 + 24.0))
	pts.append(Vector3(1890.0, Y, 96.0))
	# Ease across to the terminal station beside the hall's west end.
	pts.append(Vector3(1896.0, Y, 112.0))
	pts.append(Vector3(1912.0, Y, 122.0))
	pts.append(Vector3(1944.0, Y, 126.0))
	return pts


## Stations: [name, centre on the path (local), length].
const LINK_STATIONS := [["Skyport Quay", Vector2(1520.0, -36.0), 40.0], ["Terminal", Vector2(1928.0, 125.0), 34.0]]


## Is local (x, z) on a road's surface (+ margin)?
static func _on_road(P: Dictionary, q: Vector2, margin: float) -> bool:
	for r: Array in P["roads"]:
		if r[3]:
			continue
		var pts: PackedVector3Array = r[1]
		var hw := float(r[2]) * 0.5 + margin
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < hw:
				return true
	return false


static func build_link(P: Dictionary, target: Node3D, body: StaticBody3D, isl: SkyportIsland) -> Node3D:
	var Y := SkyportIsland.LAND_Y
	var path := link_path()
	var m := BuildingMesher.new()
	var conc := Color(0.82, 0.81, 0.78)
	var steel := Color(0.88, 0.89, 0.9)
	# Deck: a box girder with low parapets, segment by segment.
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var d := (b - a).normalized()
		var ext := d * 0.25
		var side := Vector3(-d.z, 0.0, d.x)
		m.beam(a - ext + Vector3.DOWN * 0.9, b + ext + Vector3.DOWN * 0.9, LINK_W, 1.8, conc)
		for sg: float in [-1.0, 1.0]:
			m.beam(a + side * sg * (LINK_W * 0.5 - 0.2) + Vector3.UP * 0.5 - ext, b + side * sg * (LINK_W * 0.5 - 0.2) + Vector3.UP * 0.5 + ext,
				0.3, 1.0, steel)
		m.beam(a + Vector3.UP * 0.06 - ext, b + Vector3.UP * 0.06 + ext, 1.6, 0.12, Color(0.4, 0.42, 0.44))   # guide rail
		_col(body, a - ext + Vector3.DOWN * 0.9, b + ext + Vector3.DOWN * 0.9, LINK_W, 1.8)
	# Supports every ~34 m along the path: a portal frame whose legs stand on
	# the pavements either side (13.5 m out: clear of every lane), or a
	# single central column where the path is off the road.
	var total := 0.0
	var seg_len: Array = []
	for i in path.size() - 1:
		seg_len.append(path[i].distance_to(path[i + 1]))
		total += float(seg_len[-1])
	var s := 10.0
	while s < total - 4.0:
		var at := _along(path, seg_len, s)
		var p: Vector3 = at[0]
		var d: Vector3 = at[1]
		var side := Vector3(-d.z, 0.0, d.x)
		var c2 := Vector2(p.x, p.z)
		var top := p + Vector3.DOWN * 1.8
		if not _on_road(P, c2, 1.0):
			m.beam(Vector3(p.x, Y, p.z), top, 1.6, 1.6, conc)
			m.beam(top + side * 2.2, top - side * 2.2, 1.0, 1.4, conc)
			_col(body, Vector3(p.x, Y, p.z), top, 1.6, 1.6)
		else:
			var l1 := c2 + Vector2(side.x, side.z) * 13.5
			var l2 := c2 - Vector2(side.x, side.z) * 13.5
			if not _on_road(P, l1, 0.4) and not _on_road(P, l2, 0.4):
				for l: Vector2 in [l1, l2]:
					m.beam(Vector3(l.x, Y, l.y), Vector3(l.x, top.y, l.y), 1.0, 1.0, conc)
					_col(body, Vector3(l.x, Y, l.y), Vector3(l.x, top.y, l.y), 1.0, 1.0)
				m.beam(Vector3(l1.x, top.y - 0.6, l1.y), Vector3(l2.x, top.y - 0.6, l2.y), 1.2, 1.4, conc)
				_col(body, Vector3(l1.x, top.y - 0.6, l1.y), Vector3(l2.x, top.y - 0.6, l2.y), 1.2, 1.4)
		s += 34.0
	# Stations: a wider platform deck, a glazed shelter under a light canopy
	# and a stair/lift core down to the pavement.
	for stn: Array in LINK_STATIONS:
		var sc: Vector2 = stn[1]
		var half := float(stn[2]) * 0.5
		var near_s := _nearest_s(path, seg_len, sc)
		var at2 := _along(path, seg_len, near_s)
		var dir: Vector3 = at2[1]
		var side := Vector3(-dir.z, 0.0, dir.x)
		var p0: Vector3 = (at2[0] as Vector3) - dir * half
		var p1: Vector3 = (at2[0] as Vector3) + dir * half
		for sg: float in [-1.0, 1.0]:
			var o := side * sg * 5.0
			m.beam(p0 + o + Vector3.DOWN * 0.25, p1 + o + Vector3.DOWN * 0.25, 4.0, 0.5, Color(0.7, 0.7, 0.68))   # platform
			_col(body, p0 + o + Vector3.DOWN * 0.25, p1 + o + Vector3.DOWN * 0.25, 4.0, 0.5)
			m.beam(p0 + side * sg * 7.0 + Vector3.UP * 0.6, p1 + side * sg * 7.0 + Vector3.UP * 0.6, 0.15, 1.1, steel)  # railing
			var k := 0.0
			while k <= 1.0:
				var cp := p0.lerp(p1, k) + side * sg * 6.6
				m.beam(cp, cp + Vector3.UP * 4.4, 0.25, 0.25, steel)
				k += 0.25
		m.beam(p0 + Vector3.UP * 4.6, p1 + Vector3.UP * 4.6, 15.0, 0.35, Color(0.95, 0.95, 0.95))   # canopy
		_col(body, p0 + Vector3.UP * 4.6, p1 + Vector3.UP * 4.6, 15.0, 0.35)
		# Lift and stair core at one end, off the road where possible.
		var core := Vector2(p0.x, p0.z) + Vector2(side.x, side.z) * 10.5
		if _on_road(P, core, 0.5):
			core = Vector2(p0.x, p0.z) - Vector2(side.x, side.z) * 15.0
		m.solid(core.x - 2.6, core.y - 2.6, core.x + 2.6, core.y + 2.6, Y, p0.y + 5.0, Color(0.32, 0.4, 0.46))
		CityWorld._add_box(body, AABB(Vector3(core.x - 2.6, Y, core.y - 2.6), Vector3(5.2, p0.y + 5.0 - Y, 5.2)))
	isl._mesh_into(m, "SkyportLink", target, 0.0, 2600.0)
	var shuttle := LinkShuttle.new()
	shuttle.name = "LinkShuttle"
	target.add_child(shuttle)
	shuttle.setup(path)
	shuttle.set_material(isl._bmat())
	return shuttle


static func _along(path: PackedVector3Array, seg_len: Array, s: float) -> Array:
	var acc := 0.0
	for i in seg_len.size():
		var L: float = seg_len[i]
		if s <= acc + L or i == seg_len.size() - 1:
			var t := clampf((s - acc) / maxf(L, 0.001), 0.0, 1.0)
			return [path[i].lerp(path[i + 1], t), (path[i + 1] - path[i]).normalized()]
		acc += L
	return [path[-1], Vector3.RIGHT]


static func _nearest_s(path: PackedVector3Array, seg_len: Array, q: Vector2) -> float:
	var best := 0.0
	var bd := INF
	var acc := 0.0
	for i in seg_len.size():
		var a := Vector2(path[i].x, path[i].z)
		var b := Vector2(path[i + 1].x, path[i + 1].z)
		var c := Geometry2D.get_closest_point_to_segment(q, a, b)
		var d := c.distance_to(q)
		if d < bd:
			bd = d
			best = acc + c.distance_to(a)
		acc += float(seg_len[i])
	return best


## The shuttle: two linked cars running end to end with a dwell at each
## station (eased), drawn from one mesh per car; animated only nearby.
class LinkShuttle extends Node3D:
	var path := PackedVector3Array()
	var seg := []
	var total := 0.0
	var cars: Array = []
	var t := 0.0
	const RUN := 50.0      # s per trip
	const DWELL := 14.0

	func setup(p: PackedVector3Array) -> void:
		path = p
		for i in path.size() - 1:
			seg.append(path[i].distance_to(path[i + 1]))
			total += float(seg[-1])
		var m := BuildingMesher.new()
		var white := Color(0.95, 0.95, 0.96)
		m.solid(-5.4, -1.45, 5.4, 1.45, 0.2, 3.3, white)
		m.solid(-5.45, -1.5, 5.45, 1.5, 1.6, 2.5, Color(0.12, 0.17, 0.22))    # window band
		m.solid(-5.46, -1.52, 5.46, 1.52, 0.7, 1.0, Color(0.1, 0.4, 0.62))    # livery stripe
		m.solid(-5.0, -1.0, 5.0, 1.0, 3.3, 3.6, Color(0.8, 0.8, 0.82))
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays())
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.visibility_range_end = 900.0
			add_child(mi)
			cars.append(mi)

	func set_material(mat: Material) -> void:
		for c: MeshInstance3D in cars:
			c.material_override = mat

	func _process(dt: float) -> void:
		t = fmod(t + dt, (RUN + DWELL) * 2.0)
		var cyc := RUN + DWELL
		var u := 0.0
		var ph := fmod(t, cyc)
		if ph > DWELL:
			var x := (ph - DWELL) / RUN
			u = x * x * (3.0 - 2.0 * x)
		var s := u * (total - 30.0) + 15.0 if t < cyc else (1.0 - u) * (total - 30.0) + 15.0
		for k in cars.size():
			var sk := s - 5.6 + k * 11.2
			var a := SkyportAirport._along(path, seg, sk - 4.0)
			var b := SkyportAirport._along(path, seg, sk + 4.0)
			var pa: Vector3 = a[0]
			var pb: Vector3 = b[0]
			var mid := (pa + pb) * 0.5
			var d := (pb - pa).normalized()
			var mi: MeshInstance3D = cars[k]
			mi.transform = Transform3D(Basis(d, Vector3.UP, d.cross(Vector3.UP)), mid + Vector3.UP * 0.1)


# ------------------------------------------- fuel farm, fire, car park
## Fuel farm: four tanks in a bunded compound off the end of Skyport
## Avenue, south of the industrial estate (clear of the runway approach).
static func fuel_tanks() -> Array:
	return [Vector2(2492, -96), Vector2(2524, -96), Vector2(2492, -62), Vector2(2524, -62)]


static func build_fuel_farm(target: Node3D, body: StaticBody3D, isl: SkyportIsland) -> void:
	var Y := SkyportIsland.LAND_Y
	var m := BuildingMesher.new()
	var o := SkyportIsland.outline()
	for c: Vector2 in fuel_tanks():
		if not Geometry2D.is_point_in_polygon(c, o):
			continue
		m.prism(_ring(c, 11.0, 16), Y, Y + 12.0, Color(0.9, 0.9, 0.88))
		m.prism(_ring(c, 11.05, 16), Y + 5.6, Y + 6.2, Color(0.75, 0.2, 0.15))   # band
		m.prism(_ring(c, 9.0, 16), Y + 12.0, Y + 13.0, Color(0.82, 0.82, 0.8))   # roof
		m.beam(Vector3(c.x + 10.6, Y, c.y), Vector3(c.x + 10.6, Y + 12.4, c.y), 0.3, 0.6, Color(0.4, 0.42, 0.44))  # ladder
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 11.0
		cy.height = 13.0
		cs.shape = cy
		cs.position = Vector3(c.x, Y + 6.5, c.y)
		body.add_child(cs)
	# Bund wall round the compound, pipe rack to the apron road.
	var r := Rect2(2474, -114, 68, 70)
	for e: Array in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		m.beam(Vector3(a.x, Y + 0.6, a.y), Vector3(b.x, Y + 0.6, b.y), 0.5, 1.2, Color(0.72, 0.71, 0.68))
	m.beam(Vector3(2474, Y + 3.0, -40), Vector3(2380, Y + 3.0, -40), 0.6, 0.6, Color(0.55, 0.56, 0.58))
	var x := 2470.0
	while x > 2380.0:
		m.beam(Vector3(x, Y, -40), Vector3(x, Y + 3.0, -40), 0.3, 0.3, Color(0.4, 0.42, 0.44))
		x -= 15.0
	isl._mesh_into(m, "FuelFarm", target, 0.0, 2600.0)


## Car park: four open decks on columns beside the terminal (cars on them),
## each deck walkable.
static func build_car_park(target: Node3D, body: StaticBody3D, isl: SkyportIsland) -> void:
	var Y := SkyportIsland.LAND_Y
	var r := Rect2(1968, 62, 84, 64)
	var m := BuildingMesher.new()
	var conc := Color(0.74, 0.73, 0.7)
	var deck := Color(0.46, 0.47, 0.48)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	var car_cols := [Color(0.85, 0.85, 0.86), Color(0.15, 0.16, 0.18), Color(0.55, 0.12, 0.12), Color(0.2, 0.3, 0.5), Color(0.6, 0.62, 0.64)]
	for lvl in 4:
		var y := Y + 3.2 * (lvl + 1)
		m.solid(r.position.x, r.position.y, r.end.x, r.end.y, y - 0.35, y, deck)
		# Bay lines either side of the centre aisle.
		var bx := r.position.x + 2.6
		while bx < r.end.x - 2.0:
			for row2: Array in [[r.position.y + 1.2, r.position.y + 10.8], [r.end.y - 10.8, r.end.y - 1.2]]:
				m.solid(bx - 0.06, float(row2[0]), bx + 0.06, float(row2[1]), y, y + 0.02, Color(0.92, 0.92, 0.88))
			bx += 2.8
		CityWorld._add_box(body, AABB(Vector3(r.position.x, y - 0.35, r.position.y), Vector3(r.size.x, 0.35, r.size.y)))
		# Parapet bands (the car park's horizontal stripes) with a gap at the
		# ramp end.
		m.solid(r.position.x, r.position.y - 0.2, r.end.x, r.position.y, y, y + 1.1, Color(0.85, 0.84, 0.8))
		m.solid(r.position.x, r.end.y, r.end.x, r.end.y + 0.2, y, y + 1.1, Color(0.85, 0.84, 0.8))
		m.solid(r.end.x, r.position.y, r.end.x + 0.2, r.end.y, y, y + 1.1, Color(0.85, 0.84, 0.8))
		# Parked cars in two rows (not on the top deck's ends).
		for row: float in [r.position.y + 6.0, r.end.y - 6.0]:
			var x := r.position.x + 4.0
			while x < r.end.x - 4.0:
				if rng.randf() < 0.72:
					var cc: Color = car_cols[rng.randi() % car_cols.size()]
					m.solid(x - 1.0, row - 2.2, x + 1.0, row + 2.2, y, y + 0.9, cc)
					m.solid(x - 0.85, row - 1.2, x + 0.85, row + 1.0, y + 0.9, y + 1.45, cc.darkened(0.35))
				x += 2.8
	# Columns on a 12 m grid; the lift core; the up-ramp on the west side.
	var cx := r.position.x + 1.0
	while cx < r.end.x:
		for cz: float in [r.position.y + 1.0, r.get_center().y, r.end.y - 1.0]:
			m.solid(cx - 0.4, cz - 0.4, cx + 0.4, cz + 0.4, Y, Y + 12.8, conc)
			CityWorld._add_box(body, AABB(Vector3(cx - 0.4, Y, cz - 0.4), Vector3(0.8, 12.8, 0.8)))
		cx += 12.0
	m.solid(r.position.x - 6.0, r.position.y + 20, r.position.x, r.position.y + 28, Y, Y + 15.5, Color(0.3, 0.38, 0.45))
	CityWorld._add_box(body, AABB(Vector3(r.position.x - 6.0, Y, r.position.y + 20), Vector3(6.0, 15.5, 8.0)))
	isl._mesh_into(m, "CarPark", target, 0.0, 1800.0)
