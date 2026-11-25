class_name SkyportDistrict
extends RefCounted
## Skyport Airport's finished district (2026-11-25 overhaul), built in the
## island's LOCAL frame as part of its near content, from the Blender prop
## kit (SkyportKit, tools/blender/build_skyport.py) placed as MultiMeshes:
##  * the terminal as a real, walk-in building: stone floor, the curtain wall
##    (see-through now) with doors at the entrance pods, check-in islands,
##    departures boards, security lanes behind a glass line, airside shops
##    and cafés, gate seating and desks, the gate balcony the jet bridges
##    plug into (stairs down), baggage reclaim, ceiling luminaires;
##  * airside: Blender jet bridges, a serviced turnaround round every parked
##    airliner (belt loaders, catering, bowser, tug + carts, GPU, pushback),
##    staged equipment behind the restraint line, a freighter on the cargo
##    apron, stairs + apron bus at the remote stand, stand boards; runway
##    edge / threshold / end lights, blue taxiway edge lights, approach bars,
##    windsocks, a turning radar; the security fence (airside line and the
##    airfield's coast) with a gatehouse on the service road;
##  * landside: overhead direction gantries, taxi rank and bus stop, trolley
##    bays, flags, car-park barrier, the fuel station and the rental car
##    centre on the avenue, airport hotels (records in SkyportIsland);
##  * life: tugs, an apron bus, a follow-me car and a bowser on loops, the
##    radar turning, apron floodlights at night (Movers).
## Collision only where you can walk into something tall.

const Y := SkyportIsland.LAND_Y
const HALL := Rect2(1962, 168, 296, 68)
const DOORS := [2010.0, 2056.0, 2142.0, 2188.0, 2234.0]
const FLOOR := 0.06                     # hall floor finish above LAND_Y
const BALCONY_Y := 4.4                  # gate level (the jet bridges' floor)
const BALCONY_Z := 230.0
const SECURITY_Z := 204.0
const LANES := [2096.0, 2101.0, 2106.0, 2111.0, 2116.0, 2121.0, 2126.0, 2131.0]
const FUEL := Vector2(2342.0, 2.0)      # fuel station canopy centre
const RENTAL := Rect2(2282, 44, 128, 92)
const MRO := [2470.0, 196.0, 2546.0, 288.0]

const TERMINAL_GLASS := Color(0.66, 0.78, 0.84, 0.3)


static func at(x: float, z: float, yaw := 0.0, y := Y) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


static func _box(body: StaticBody3D, x0: float, z0: float, x1: float, z1: float, y0: float, y1: float) -> void:
	CityWorld._add_box(body, AABB(Vector3(minf(x0, x1), y0, minf(z0, z1)), Vector3(absf(x1 - x0), y1 - y0, absf(z1 - z0))))


static func terminal_glass() -> StandardMaterial3D:
	var gm := StandardMaterial3D.new()
	gm.albedo_color = TERMINAL_GLASS
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.metallic = 0.25
	gm.roughness = 0.06
	gm.metallic_specular = 0.7
	gm.cull_mode = BaseMaterial3D.CULL_BACK
	return gm


static func _label(target: Node3D, text: String, at3: Vector3, yaw: float, height: float, col := Color("f3efe6"), rng := 260.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = preload("res://assets/fonts/brand/Oswald.ttf")
	l.font_size = 128
	l.outline_size = 0
	l.modulate = col
	l.pixel_size = height / 128.0
	l.position = at3
	l.rotation.y = yaw
	l.visibility_range_end = rng
	l.shaded = false
	target.add_child(l)


# ================================================================ terminal
## The hall's walk-in interior and its collision (the hall's record no
## longer collides: SkyportIsland skips "walkin" buildings).
static func build_terminal_interior(target: Node3D, body: StaticBody3D, isl: SkyportIsland) -> void:
	var m := BuildingMesher.new()
	var H := HALL
	var stone := Color(0.8, 0.78, 0.74)
	# Floor finish: pale terrazzo with darker bands at the entrances and
	# under the security line.
	m.solid(H.position.x - 0.6, H.position.y - 0.6, H.end.x + 0.6, H.end.y + 0.6, Y, Y + FLOOR, stone)
	for x: float in DOORS:
		m.solid(x - 4.0, H.position.y + 0.1, x + 4.0, H.position.y + 6.0, Y + FLOOR, Y + FLOOR + 0.01, Color(0.42, 0.43, 0.45))
	m.solid(H.position.x + 0.2, SECURITY_Z - 0.6, H.end.x - 0.2, SECURITY_Z + 0.6, Y + FLOOR, Y + FLOOR + 0.01, Color(0.36, 0.38, 0.42))
	# Curtain wall collision: landside face with gaps at the doors, the
	# other three faces whole.
	var gaps: Array = DOORS.duplicate()
	var x0 := H.position.x
	for g: float in gaps:
		_box(body, x0, H.position.y - 0.25, g - 1.6, H.position.y + 0.25, Y, Y + 14.0)
		x0 = g + 1.6
	_box(body, x0, H.position.y - 0.25, H.end.x, H.position.y + 0.25, Y, Y + 14.0)
	_box(body, H.position.x, H.end.y - 0.25, H.end.x, H.end.y + 0.25, Y, Y + 14.0)
	_box(body, H.position.x - 0.25, H.position.y, H.position.x + 0.25, H.end.y, Y, Y + 14.0)
	_box(body, H.end.x - 0.25, H.position.y, H.end.x + 0.25, H.end.y, Y, Y + 14.0)
	# Entrance pods (vestibules): their side walls and front with the door.
	for x: float in DOORS:
		for sx: float in [-4.0, 4.0]:
			_box(body, x + sx - 0.1, H.position.y - 4.0, x + sx + 0.1, H.position.y, Y, Y + 3.6)
		_box(body, x - 4.0, H.position.y - 4.1, x - 1.6, H.position.y - 3.9, Y, Y + 3.6)
		_box(body, x + 1.6, H.position.y - 4.1, x + 4.0, H.position.y - 3.9, Y, Y + 3.6)
	var K := {}   # kit name -> [Transform3D]
	var put := func(name: String, xf: Transform3D) -> void:
		if not K.has(name):
			K[name] = []
		(K[name] as Array).append(xf)
	var fy := Y + FLOOR
	for x: float in DOORS:
		put.call("entrance_pod", at(x, H.position.y, PI, Y))
	# --- Departures (west): three check-in islands facing the doors.
	for cx: float in [1992.0, 2032.0, 2072.0]:
		put.call("checkin_island", at(cx, 190.0, PI, fy))
		_box(body, cx - 12.0, 189.6, cx + 12.0, 192.5, Y, Y + 1.1)
		_box(body, cx - 12.0, 191.8, cx + 12.0, 192.4, Y, Y + 4.3)
	for fx: float in [2012.0, 2052.0]:
		put.call("fids_board", at(fx, 181.0, 0.0, fy))
		_box(body, fx - 1.3, 180.75, fx + 1.3, 181.25, Y, Y + 3.4)
	# --- Security: eight lanes behind the glass line.
	for lx: float in LANES:
		put.call("security_lane", at(lx, SECURITY_Z - 1.0, 0.0, fy))
		_box(body, lx - 0.55, SECURITY_Z - 4.2, lx + 0.55, SECURITY_Z + 2.2, Y, Y + 1.6)
	# The glass line (1.1 m balustrade glass up to a 2.4 m screen), open at
	# each lane's arch, with a lit sign band over the lanes.
	var gl := SurfaceTool.new()
	gl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var openings: Array = []
	for lx: float in LANES:
		openings.append(lx + 1.9)
	openings.append(H.end.x - 8.0)   # (arrivals: the way out from the gates)
	var sx0 := H.position.x
	for o: float in openings:
		var o0: float = o - (0.55 if o < H.end.x - 10.0 else 2.0)
		var o1: float = o + (0.55 if o < H.end.x - 10.0 else 2.0)
		if o0 > sx0 + 0.05:
			_glass_panel(gl, Vector3(sx0, fy, SECURITY_Z), Vector3(o0, fy, SECURITY_Z), 2.4)
			_box(body, sx0, SECURITY_Z - 0.1, o0, SECURITY_Z + 0.1, Y, Y + 2.4)
			m.solid(sx0, SECURITY_Z - 0.06, o0, SECURITY_Z + 0.06, fy + 2.38, fy + 2.5, Color(0.7, 0.72, 0.74))
		sx0 = o1
	_glass_panel(gl, Vector3(sx0, fy, SECURITY_Z), Vector3(H.end.x, fy, SECURITY_Z), 2.4)
	_box(body, sx0, SECURITY_Z - 0.1, H.end.x, SECURITY_Z + 0.1, Y, Y + 2.4)
	m.solid(LANES[0] - 3.0, SECURITY_Z - 0.3, LANES[-1] + 4.5, SECURITY_Z + 0.3, fy + 3.2, fy + 4.0, Color(0.12, 0.17, 0.24))
	_label(target, "SECURITY  ·  ALL GATES", Vector3((LANES[0] + LANES[-1]) * 0.5 + 0.8, fy + 3.6, SECURITY_Z - 0.32), PI, 0.55, Color("f2c230"))
	# --- Airside: shops and cafés facing the security line.
	var units := [[1984.0, "shop_unit", "DUTY FREE"], [1998.0, "cafe_unit", "ESPRESSO BAR"], [2048.0, "shop_unit", "SKYPORT STYLE"],
		[2062.0, "shop_unit", "BOOKS & NEWS"], [2150.0, "cafe_unit", "THE TERRACE"], [2164.0, "shop_unit", "TECH & TRAVEL"],
		[2204.0, "shop_unit", "FRAGRANCE"], [2218.0, "cafe_unit", "NOODLE BAR"]]
	for u: Array in units:
		var ux: float = u[0]
		put.call(String(u[1]), at(ux, 212.0, PI, fy))
		var deep := 7.0 if String(u[1]) == "shop_unit" else 5.0
		_box(body, ux - 5.0, 212.0 + deep - 0.3, ux + 5.0, 212.0 + deep, Y, Y + 4.6)
		for sxx: float in [-5.0, 5.0]:
			_box(body, ux + sxx - 0.15, 212.0, ux + sxx + 0.15, 212.0 + deep, Y, Y + 4.6)
		_label(target, String(u[2]), Vector3(ux, fy + 4.1, 211.74), PI, 0.4, Color("1d1a16"), 160.0)
	# Gate seating (facing the apron), gate desks, planters.
	for gi in SkyportAirport.STANDS_AT.size():
		var gx: float = float(SkyportAirport.STANDS_AT[gi]) - 4.2
		for row in 2:
			for k in [-3, -2, -1, 1, 2, 3]:
				put.call("seat_row", at(gx + k * 4.2, 222.5 + row * 2.2, 0.0, fy))
		put.call("gate_desk", at(gx, 227.2, 0.0, fy))
		_label(target, "A%02d" % (gi + 1), Vector3(gx + 1.6, fy + 2.8, 227.08), PI, 0.5, Color("ffffff"), 120.0)
	for px: float in [2000.0, 2040.0, 2094.0, 2142.0, 2186.0, 2240.0]:
		put.call("indoor_planter", at(px, 176.0 if px < 2090.0 or px > 2190.0 else 200.0, 0.0, fy))
	put.call("info_desk", at(2112.0, 182.0, 0.0, fy))
	_box(body, 2110.0, 180.0, 2114.0, 184.0, Y, Y + 1.1)
	# --- Arrivals (east): reclaim carousels, the meeting point.
	for cx: float in [2166.0, 2204.0, 2240.0]:
		put.call("carousel", at(cx, 192.0, 0.0, fy))
		_box(body, cx - 7.0, 190.1, cx + 7.0, 193.9, Y, Y + 0.6)
		_label(target, "BELT %d" % (int((cx - 2128.0) / 37.0)), Vector3(cx, fy + 2.4, 193.07), 0.0, 0.3, Color("ffffff"), 80.0)
	put.call("fids_board", at(2150.0, 181.0, 0.0, fy))
	for tx: float in [2030.0, 2098.0, 2128.0, 2212.0]:
		put.call("trolley_bay", at(tx, 174.0, PI * 0.5, fy))
	# Hanging zone signs (dark boards on rods).
	for zs: Array in [[2032.0, 192.6, "DEPARTURES  ·  CHECK-IN A–H"], [2204.0, 186.0, "ARRIVALS  ·  BAGGAGE RECLAIM"]]:
		var sxx: float = zs[0]
		var szz: float = zs[1]
		m.solid(sxx - 15.0, szz - 0.12, sxx + 15.0, szz + 0.12, fy + 8.2, fy + 9.8, Color(0.1, 0.14, 0.2))
		for rx: float in [-12.0, 12.0]:
			m.beam(Vector3(sxx + rx, fy + 9.8, szz), Vector3(sxx + rx, fy + 16.0, szz), 0.05, 0.05, Color(0.6, 0.62, 0.64))
		_label(target, String(zs[2]), Vector3(sxx, fy + 9.0, szz - 0.14), PI, 1.0, Color("f2c230"), 300.0)
	# --- Gate balcony: the floor the jet bridges plug into, glass
	# balustrade, a stair down at every gate.
	var bz := BALCONY_Z
	m.solid(H.position.x + 0.3, bz, H.end.x - 0.3, H.end.y - 0.3, Y + BALCONY_Y - 0.35, Y + BALCONY_Y, Color(0.86, 0.86, 0.85))
	m.solid(H.position.x + 0.3, bz - 0.05, H.end.x - 0.3, bz + 0.05, Y + BALCONY_Y - 0.6, Y + BALCONY_Y - 0.35, Color(0.65, 0.66, 0.68))
	_box(body, H.position.x + 0.3, bz, H.end.x - 0.3, H.end.y - 0.3, Y + BALCONY_Y - 0.35, Y + BALCONY_Y)
	_glass_panel(gl, Vector3(H.position.x + 0.3, Y + BALCONY_Y, bz), Vector3(H.end.x - 0.3, Y + BALCONY_Y, bz), 1.1)
	m.solid(H.position.x + 0.3, bz - 0.05, H.end.x - 0.3, bz + 0.05, Y + BALCONY_Y + 1.08, Y + BALCONY_Y + 1.16, Color(0.75, 0.76, 0.78))
	for gi in SkyportAirport.STANDS_AT.size():
		var gx: float = float(SkyportAirport.STANDS_AT[gi]) + 14.0
		var steps := 16
		for k in steps:
			var t0 := float(k) / steps
			var zz := bz - 0.0 - (k + 1) * 0.42
			var yy := Y + BALCONY_Y - (k + 1) * (BALCONY_Y - FLOOR) / steps
			m.solid(gx - 1.2, zz, gx + 1.2, zz + 0.42, yy - 0.12, yy + (BALCONY_Y - FLOOR) / steps, Color(0.82, 0.82, 0.8))
			if t0 < 0.0:
				pass
		m.beam(Vector3(gx - 1.25, Y + BALCONY_Y + 1.0, bz), Vector3(gx - 1.25, fy + 1.0, bz - steps * 0.42), 0.06, 0.08, Color(0.75, 0.76, 0.78))
		m.beam(Vector3(gx + 1.25, Y + BALCONY_Y + 1.0, bz), Vector3(gx + 1.25, fy + 1.0, bz - steps * 0.42), 0.06, 0.08, Color(0.75, 0.76, 0.78))
	# Ceiling luminaires (rows over each zone) – lit at night through the
	# glass.
	var lx := H.position.x + 10.0
	while lx < H.end.x - 6.0:
		for lz: float in [178.0, 196.0, 216.0]:
			put.call("ceiling_lamp", at(lx, lz, 0.0, Y + 10.5))
		lx += 16.0
	# The glazing of the security line and the balcony.
	gl.generate_normals()
	var gmi := MeshInstance3D.new()
	gmi.name = "TerminalInnerGlass"
	gmi.mesh = gl.commit()
	gmi.material_override = terminal_glass()
	gmi.visibility_range_end = 500.0
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(gmi)
	isl._mesh_into(m, "TerminalInterior", target, 0.0, 700.0)
	for name: String in K:
		var far := 900.0 if name == "entrance_pod" else 420.0
		SkyportKit.place(target, name, K[name], far, name in ["entrance_pod", "checkin_island"])


static func _glass_panel(st: SurfaceTool, a: Vector3, b: Vector3, h: float) -> void:
	var a1 := a + Vector3(0, h, 0)
	var b1 := b + Vector3(0, h, 0)
	for v: Vector3 in [a, a1, b1, a, b1, b, a, b1, a1, a, b, b1]:
		st.add_vertex(v)


# ================================================================= airside
static func build_airside(P: Dictionary, target: Node3D, body: StaticBody3D, isl: SkyportIsland) -> void:
	var K := {}
	var put := func(name: String, xf: Transform3D) -> void:
		if not K.has(name):
			K[name] = []
		(K[name] as Array).append(xf)
	var stands: Array = P["stands"]
	# Jet bridges (collision on the tunnel so the swing web catches them).
	for gi in SkyportAirport.STANDS_AT.size():
		var x := float(SkyportAirport.STANDS_AT[gi]) - 4.2
		put.call("jet_bridge", at(x, HALL.end.y, PI))
		SkyportAirport._col(body, Vector3(x, Y + 6.0, HALL.end.y), Vector3(x, Y + 6.0, HALL.end.y + 47.0), 3.6, 3.2)
	# A full turnaround round the two parked airliners.
	for k: int in [0, 2]:
		var p: Vector3 = (stands[k] as Array)[0]
		_turnaround(put, p.x, p.z)
	# The scripted stands (1, 3): equipment staged behind the restraint line.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	for gi in SkyportAirport.STANDS_AT.size() - 1:
		var cx: float = float(SkyportAirport.STANDS_AT[gi]) + 16.0
		var end_x: float = float(SkyportAirport.STANDS_AT[gi + 1]) - 16.0
		while cx < end_x - 4.0:
			var r := rng.randf()
			if r < 0.4:
				put.call("gse_tug", at(cx + 1.4, 257.0, -PI * 0.5))
				var n := rng.randi_range(2, 4)
				for j in n:
					put.call("gse_cart", at(cx - 2.2 - j * 3.1, 257.0, PI * 0.5))
				cx += 6.0 + n * 3.1
			elif r < 0.55:
				put.call("gse_gpu", at(cx + 1.2, 257.0, PI * 0.5))
				cx += 4.0
			elif r < 0.75:
				put.call("gse_belt", at(cx + 3.4, 257.0, -PI * 0.5))
				cx += 8.5
			elif r < 0.88:
				put.call("gse_stairs", at(cx + 3.2, 257.0, -PI * 0.5))
				cx += 8.0
			else:
				put.call("gse_pushback", at(cx + 3.2, 257.0, -PI * 0.5))
				cx += 8.5
			cx += 1.4
	# Stand boards on the restraint line.
	for gi in SkyportAirport.STANDS_AT.size():
		var sx: float = SkyportAirport.STANDS_AT[gi]
		put.call("stand_sign", at(sx + 7.0, 263.0, PI))
		_label(target, "%d" % (gi + 1), Vector3(sx + 7.0, Y + 3.9, 263.12), 0.0, 0.85, Color("111111"), 220.0)
	# Remote stand (the regional prop): stairs at the door, an apron bus.
	var rs: Vector3 = (stands[4] as Array)[0]
	put.call("gse_stairs", at(rs.x - 3.6, rs.z - 2.0, -PI * 0.5))
	put.call("gse_bus", at(rs.x - 18.0, rs.z - 12.0, PI * 0.5))
	put.call("gse_fuel", at(rs.x + 12.0, rs.z - 4.0, 0.0))
	var bj: Vector3 = (stands[5] as Array)[0]
	put.call("gse_follow", at(bj.x + 14.0, bj.z - 2.0, 0.3))
	put.call("gse_gpu", at(bj.x - 6.0, bj.z - 10.0, 0.0))
	# The freighter on the cargo apron and its loaders, ULD trains.
	var fx := 2398.0
	var fz := 330.0
	var node: Node3D = load("res://src/vehicle/craft_models.gd").build("plane", "liner",
		{"size": Vector3(36, 9, 40), "jet": true, "paint": Color(0.93, 0.93, 0.92), "trim": Color(0.48, 0.1, 0.14)})
	node.name = "Freighter"
	node.position = Vector3(fx, Y + 0.02, fz)
	target.add_child(node)
	put.call("gse_belt", at(fx + 5.8, fz - 9.0, PI * 0.5))
	put.call("gse_belt", at(fx + 5.8, fz + 9.0, PI * 0.5))
	put.call("gse_fuel", at(fx - 13.0, fz + 3.0, 0.0))
	for row in 3:
		put.call("gse_tug", at(2372.0, 302.0 + row * 4.0, -PI * 0.5))
		for j in 5:
			put.call("gse_cart", at(2367.8 - j * 3.1, 302.0 + row * 4.0, -PI * 0.5))
	# Hangar apron: a tug at each hangar, a stairs truck by the GA hangar.
	for hg: Array in SkyportIsland.HANGARS:
		var hx := (float(hg[0]) + float(hg[2])) * 0.5
		put.call("gse_pushback", at(hx + 8.0, float(hg[3]) + 14.0, PI * 0.5))
	# --- Airfield lighting.
	var rw: Dictionary = SkyportIsland.RUNWAY
	var a: Vector3 = rw["from"]
	var b: Vector3 = rw["to"]
	var hw := float(rw["w"]) * 0.5 + 1.5
	var x := a.x + 10.0
	while x <= b.x - 10.0:
		for sg: float in [-1.0, 1.0]:
			put.call("runway_light", at(x, a.z + sg * hw, 0.0))
		x += 60.0
	var tz := -hw
	while tz <= hw + 0.1:
		put.call("runway_light_g", at(a.x + 1.5, a.z + tz, 0.0))
		put.call("runway_light_r", at(a.x - 1.5, a.z + tz, 0.0))
		put.call("runway_light_g", at(b.x - 1.5, a.z + tz, 0.0))
		put.call("runway_light_r", at(b.x + 1.5, a.z + tz, 0.0))
		tz += 4.0
	# Taxiway edge lights (blue), clear of the connectors and rapid exits.
	var cons := [1480.0, 1700.0, 1940.0, 2160.0, 2400.0, 2660.0, 2930.0, 3200.0, 2660.0, 2170.0, 1740.0]
	x = 1480.0
	while x <= 3210.0:
		for sg: float in [-1.0, 1.0]:
			var clear := true
			for cxx: float in cons:
				if absf(x - cxx) < 16.0:
					clear = false
			if sg < 0.0 and x > 1890.0 and x < 2335.0:
				clear = false   # (the apron edge: no lights across the stands' lead-ins)
			if clear:
				put.call("taxi_light", at(x, 395.0 + sg * 13.0, 0.0))
		x += 30.0
	# Approach bars over the water / grass at both ends (a gantry on piles).
	for e: Array in [[a.x, -1.0], [b.x, 1.0]]:
		for k in 6:
			var ax: float = float(e[0]) + float(e[1]) * (30.0 + k * 30.0)
			var q := Vector2(ax, a.z)
			var on_land := Geometry2D.is_point_in_polygon(q, SkyportIsland.outline())
			put.call("approach_bar", at(ax, a.z, PI * 0.5, (Y - 4.6 + 0.3) if not on_land else (Y - 4.3)))
	# Windsocks at both ends, the radar by the fire station.
	put.call("windsock", at(1500.0, 430.0, 0.4))
	put.call("windsock", at(3150.0, 430.0, -0.6))
	put.call("radar_mast", at(1466.0, 360.0, 0.0))
	SkyportAirport._col(body, Vector3(1466, Y, 360), Vector3(1466, Y + 17.0, 360), 3.0, 3.0)
	# Floodlight heads on the apron masts.
	for mp: Vector2 in SkyportAirport.mast_points():
		put.call("flood_head", Transform3D(Basis(Vector3.UP, PI), Vector3(mp.x, Y + 32.0, mp.y)))
	# --- Security fence: the airside line along the landside edge of the
	# aprons (buildings close the gaps), with the gatehouse on the airside
	# service road; then round the airfield along its coast.
	_fence_line(put, P, Vector2(1440.0, 178.0), Vector2(2560.0, 178.0), [1558.0])
	put.call("fence_gate", at(1558.0, 178.0, 0.0))
	SkyportAirport._col(body, Vector3(1564.4, Y, 178.0), Vector3(1564.4, Y + 3.0, 178.0), 3.4, 2.8)
	_coast_fence(put)
	for name: String in K:
		var far: float = {"runway_light": 2600.0, "runway_light_g": 2600.0, "runway_light_r": 2600.0, "taxi_light": 1800.0,
			"approach_bar": 2600.0, "jet_bridge": 1800.0, "fence": 650.0, "flood_head": 2600.0, "radar_mast": 2600.0}.get(name, 900.0)
		var shadows: bool = name not in ["runway_light", "runway_light_g", "runway_light_r", "taxi_light", "fence", "seat_row"]
		SkyportKit.place(target, name, K[name], far, shadows)


static func _turnaround(put: Callable, px: float, pz: float) -> void:
	# (Parked liner: nose ≈ pz − 8, centre pz + 10, heading −z.)
	put.call("gse_belt", at(px + 5.6, pz + 2.0, PI * 0.5))
	put.call("gse_belt", at(px + 5.6, pz + 22.0, PI * 0.5))
	put.call("gse_catering", at(px - 5.6, pz + 21.0, -PI * 0.5))
	put.call("gse_fuel", at(px - 13.0, pz + 12.0, 0.0))
	put.call("gse_gpu", at(px - 3.2, pz - 4.0, 0.0))
	put.call("gse_pushback", at(px + 0.4, pz - 12.5, PI))
	put.call("gse_tug", at(px + 11.0, pz + 4.0, PI))
	for j in 3:
		put.call("gse_cart", at(px + 11.0, pz - 0.2 - j * 3.1, PI))


static func _fence_line(put: Callable, P: Dictionary, a: Vector2, b: Vector2, gates: Array) -> void:
	var o := SkyportIsland.outline()
	var L := a.distance_to(b)
	var d := (b - a) / L
	var yaw := atan2(-d.y, d.x)
	var s := 2.0
	while s < L:
		var q := a + d * s
		var skip := false
		for g: float in gates:
			if absf(q.x - g) < 9.0:
				skip = true
		if not skip and Geometry2D.is_point_in_polygon(q, o) and SkyportIsland._shore_dist(q) > 6.0:
			for bd: Dictionary in P["buildings"]:
				var t0: Array = bd["tiers"][0]
				if Rect2(t0[0], t0[1], float(t0[2]) - float(t0[0]), float(t0[3]) - float(t0[1])).grow(1.5).has_point(q):
					skip = true
					break
			if not skip and SkyportIsland.road_clearance(P, q) < 1.0:
				skip = true
			if not skip:
				put.call("fence", Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, Y, q.y)))
		s += 4.0


static func _coast_fence(put: Callable) -> void:
	var o := SkyportIsland.outline()
	var ins := Geometry2D.offset_polygon(o, -14.0)
	if ins.is_empty():
		return
	var ring: PackedVector2Array = ins[0]
	var rw: Dictionary = SkyportIsland.RUNWAY
	var rz: float = (rw["from"] as Vector3).z
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var d := (b - a) / L
		var yaw := atan2(-d.y, d.x)
		var s := 2.0
		while s < L:
			var q := a + d * s
			# The airfield: south of the aprons, or east of the cargo apron.
			var airfield := q.y > 392.0 or (q.x > 2462.0 and q.y > 150.0)
			# (Gaps for the approach lights at the runway ends.)
			if airfield and absf(q.y - rz) > 14.0:
				put.call("fence", Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, Y + SkyportIsland.knoll_h(q.x, q.y), q.y)))
			s += 4.0


# ================================================================ landside
static func build_landside(P: Dictionary, target: Node3D, body: StaticBody3D, isl: SkyportIsland) -> void:
	var K := {}
	var put := func(name: String, xf: Transform3D) -> void:
		if not K.has(name):
			K[name] = []
		(K[name] as Array).append(xf)
	var z0 := SkyportIsland.PIVOT.y
	# Overhead direction gantries: [x, z, yaw (sign faces), left text, right text].
	var gantries := [
		[1872.0, z0, -PI * 0.5, "AIRPORT TERMINAL\nPARKING  ·  HOTELS", "CARGO  ·  FUEL\nRENTAL CARS"],
		[2300.0, z0, PI * 0.5, "CITY CENTRE\nHARBOUR BRIDGE", "WESTBANK\nMARINA  ·  TOWN"],
		[1954.0, 18.0, PI, "DEPARTURES\nDROP-OFF  ·  STATION", "SHORT STAY\nPARKING"],
		[2270.0, 104.0, 0.0, "EXIT  ·  CITY\nALL ROUTES", "RENTAL CAR RETURN\nFUEL"],
	]
	for g: Array in gantries:
		var xf := at(float(g[0]), float(g[1]), float(g[2]))
		put.call("gantry_sign", xf)
		for side in 2:
			var off := Vector3(-5.5 if side == 0 else 5.5, 6.5, 0.16)
			_label(target, String(g[3 + side]), xf * off, float(g[2]), 0.72, Color("ffffff"), 340.0)
		for sx: float in [-13.0, 13.0]:
			var p := xf * Vector3(sx, 0, 0)
			_box(body, p.x - 0.3, p.z - 0.3, p.x + 0.3, p.z + 0.3, Y, Y + 7.6)
	# The forecourt: taxi rank (shelter, waiting taxis), bus stop, flags.
	put.call("taxi_shelter", at(2236.0, 138.5, 0.0))
	_box(body, 2230.0, 139.6, 2242.0, 140.2, Y, Y + 3.0)
	_label(target, "TAXIS", Vector3(2229.4, Y + 3.6, 137.24), 0.0, 0.6, Color("111111"), 160.0)
	put.call("bus_stop_airport", at(1990.0, 139.0, 0.0))
	_label(target, "AIRPORT BUS  ·  CITY", Vector3(1990.0, Y + 3.1, 137.8), 0.0, 0.42, Color("f3efe6"), 120.0)
	for k in 5:
		put.call("flag_pole", at(1940.0, 52.0 + k * 9.0, PI * 0.5))
	# Car park barrier on Parking Access.
	put.call("barrier", at(2091.5, 140.0, 0.0))
	# Fuel station on the avenue (canopy, shop, totem).
	put.call("fuel_canopy", at(FUEL.x, FUEL.y, 0.0))
	for cx: float in [-8.0, 8.0]:
		for cz: float in [-3.5, 3.5]:
			_box(body, FUEL.x + cx - 0.3, FUEL.y + cz - 0.3, FUEL.x + cx + 0.3, FUEL.y + cz + 0.3, Y, Y + 5.2)
	for cz: float in [-4.5, 0.0, 4.5]:
		for cx: float in [-4.5, 0.0, 4.5]:
			_box(body, FUEL.x + cx - 0.45, FUEL.y + cz - 0.3, FUEL.x + cx + 0.45, FUEL.y + cz + 0.3, Y, Y + 2.0)
	put.call("fuel_kiosk", at(FUEL.x, FUEL.y + 12.0, PI))
	_box(body, FUEL.x - 8.0, FUEL.y + 12.0, FUEL.x + 8.0, FUEL.y + 22.0, Y, Y + 4.6)
	_label(target, "SKYPORT FUEL", Vector3(FUEL.x, Y + 4.4, FUEL.y + 11.66), PI, 0.38, Color("ffffff"), 160.0)
	# Rental car centre: two canopies over the bays, the booth, the cars.
	var rc := RENTAL
	for k in 2:
		put.call("rental_canopy", at(rc.position.x + 36.0 + k * 52.0, rc.position.y + 30.0, 0.0))
		put.call("rental_canopy", at(rc.position.x + 36.0 + k * 52.0, rc.position.y + 64.0, 0.0))
	put.call("rental_booth", at(rc.position.x + 10.0, rc.position.y + 14.0, PI * 0.5))
	_box(body, rc.position.x + 7.5, rc.position.y + 10.0, rc.position.x + 12.5, rc.position.y + 18.0, Y, Y + 3.8)
	_label(target, "CAR RENTAL", Vector3(rc.position.x + 12.75, Y + 3.6, rc.position.y + 14.0), PI * 0.5, 0.36, Color("ffffff"), 160.0)
	# Trolley bays and edge posts on the forecourt pavement.
	for tx: float in [2033.0, 2165.0]:
		put.call("trolley_bay", at(tx, 165.6, PI * 0.5))
	var ex := 1970.0
	while ex < 2252.0:
		var clear := true
		for d: float in DOORS:
			if absf(ex - d) < 7.0:
				clear = false
		if clear:
			put.call("edge_post", at(ex, 160.9, 0.0))
		ex += 6.0
	for name: String in K:
		SkyportKit.place(target, name, K[name], 900.0, name not in ["edge_post", "trolley_bay"])
	_parked_extras(target, isl)
	_landscape(P, target)
	_billboards(target)


## Planting: clipped box balls between the entrances, shrub beds round the
## hotels, the fuel station and the rental centre, card hedges round
## Terminal Circus (its old box hedges are skipped when the kit is in).
static func _landscape(P: Dictionary, target: Node3D) -> void:
	var pl := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7712
	var add := func(nm: String, x: float, z: float, s := 1.0, yaw := -1.0) -> void:
		if not pl.has(nm):
			pl[nm] = []
		(pl[nm] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU if yaw < 0.0 else yaw).scaled(Vector3.ONE * s), Vector3(x, Y, z)))
	# Forecourt: a pair of box balls either side of every entrance pod.
	for x: float in DOORS:
		for dx: float in [-5.4, 5.4]:
			add.call("box_ball", x + dx, 164.0, 1.1)
	# Hotels (records in SkyportIsland._buildings): beds along their street
	# fronts.
	for r: Rect2 in [Rect2(2036, -17, 66, 44), Rect2(2148, -15, 58, 40), Rect2(1878, 170, 44, 52)]:
		var x := r.position.x + 2.0
		while x < r.end.x - 1.0:
			add.call(["bush_round", "box_ball", "flower_bed", "bush_low"][rng.randi() % 4], x, r.position.y - 2.2, rng.randf_range(0.8, 1.15))
			x += rng.randf_range(2.4, 3.6)
	# Fuel station and rental centre edges.
	for x in range(int(FUEL.x - 20.0), int(FUEL.x + 21.0), 3):
		if absf(x - FUEL.x) > 9.0:
			add.call("bush_low", x, -19.5, 0.9)
	var rc := RENTAL
	var z := rc.position.y + 2.0
	while z < rc.end.y - 2.0:
		add.call("bush_round", rc.end.x + 2.5, z, 0.95)
		z += 4.0
	# Terminal Circus: a clipped hedge ring (cards), gaps for the gardeners.
	var circ: Array = P.get("circus", [])
	if not circ.is_empty():
		var C: Vector2 = circ[0]
		var Ri: float = float(circ[1]) - 6.0 - 2.2
		var n := int(TAU * Ri / 2.0)
		for k in n:
			if k % 9 == 0:
				continue
			var a := TAU * (k + 0.5) / n
			var q := C + Vector2.from_angle(a) * Ri
			if not pl.has("hedge_block"):
				pl["hedge_block"] = []
			(pl["hedge_block"] as Array).append(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(q.x, Y + 0.24, q.y)))
	FoliageKit.place(target, pl, 260.0)


## Lit billboards from the city's advert atlas (assets/ads): a Skyport Air
## campaign across the multi-storey car park, roadside boards on the avenue.
static func _billboards(target: Node3D) -> void:
	var meta_path := "res://assets/ads/ads_meta.json"
	if not ResourceLoader.exists("res://assets/ads/ads_atlas.png") or not FileAccess.file_exists(meta_path):
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var size: Array = meta["size"]
	var rects := {}
	for ad: Dictionary in meta["ads"]:
		rects[String(ad["id"])] = ad["wide"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ads/ads_atlas.png")
	mat.emission_enabled = true
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = 0.55
	mat.roughness = 0.35
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var m := BuildingMesher.new()
	# [brand, centre, yaw (board faces), width, height, posts]
	var boards := [
		["skyportair", Vector3(SkyportAirport.CAR_PARK.get_center().x, Y + 9.0, SkyportAirport.CAR_PARK.end.y + 0.32), 0.0, 22.0, 11.0, false],
		["skyportair", Vector3(1840.0, Y + 7.5, -50.5), PI, 12.0, 6.0, true],
		["ledgerline", Vector3(2210.0, Y + 7.5, -21.5), PI, 12.0, 6.0, true],
		["brasa", Vector3(1700.0, Y + 7.5, -21.5), PI, 12.0, 6.0, true],
		["harbourhale", Vector3(2120.0, Y + 7.5, 31.5), 0.0, 12.0, 6.0, true],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Array in boards:
		if not rects.has(b[0]):
			continue
		var r: Array = rects[b[0]]
		var u0 := float(r[0]) / float(size[0])
		var v0 := float(r[1]) / float(size[1])
		var u1 := (float(r[0]) + float(r[2])) / float(size[0])
		var v1 := (float(r[1]) + float(r[3])) / float(size[1])
		var c: Vector3 = b[1]
		var yaw: float = b[2]
		var w: float = b[3]
		var h: float = b[4]
		var basis := Basis(Vector3.UP, yaw)
		var rt := basis * Vector3(w * 0.5, 0, 0)
		var up := Vector3(0, h * 0.5, 0)
		var nrm := basis * Vector3(0, 0, 1)
		var face := c + nrm * 0.12
		var corners := [face - rt - up, face + rt - up, face + rt + up, face - rt + up]
		var uvs := [Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
		# Frame (dark casing), and two posts with a catwalk for the roadside ones.
		m.beam(c - rt - up * 1.04, c + rt - up * 1.04, 0.35, 0.3, Color(0.16, 0.17, 0.19))
		m.beam(c - rt + up * 1.04, c + rt + up * 1.04, 0.35, 0.3, Color(0.16, 0.17, 0.19))
		m.beam(c - rt * 1.02 - up, c - rt * 1.02 + up, 0.3, 0.35, Color(0.16, 0.17, 0.19))
		m.beam(c + rt * 1.02 - up, c + rt * 1.02 + up, 0.3, 0.35, Color(0.16, 0.17, 0.19))
		if b[5]:
			for sx: float in [-0.3, 0.3]:
				var foot := c + rt * (sx * 2.0) - nrm * 0.4
				foot.y = Y
				m.beam(foot, foot + Vector3(0, c.y - Y - h * 0.5, 0), 0.5, 0.5, Color(0.45, 0.47, 0.5))
			m.beam(c - rt - up - nrm * 0.9, c + rt - up - nrm * 0.9, 1.0, 0.12, Color(0.4, 0.42, 0.44))
			m.beam(c - rt - nrm * 0.2, c + rt - nrm * 0.2, 0.3, h, Color(0.12, 0.13, 0.14))   # (the board's back)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "AirportBillboards"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.visibility_range_end = 1200.0
	target.add_child(mi)
	_mesher_into(m, target, "AirportBillboardFrames")


static func _mesher_into(m: BuildingMesher, target: Node3D, nm: String) -> void:
	var isl := target.get_parent() as SkyportIsland
	if isl:
		isl._mesh_into(m, nm, target, 0.0, 1200.0)


## Taxis on the rank and cars in the rental centre's bays (the city's
## traffic bodies, mid LOD).
static func _parked_extras(target: Node3D, isl: SkyportIsland) -> void:
	var wr = isl.world_ref
	var mids: Array = wr.get("car_mid_meshes") if wr else []
	if mids.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var groups := {}
	var add := func(k: int, xf: Transform3D, col: Color) -> void:
		if k >= mids.size() or mids[k] == null:
			k = 0
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append([xf, Color(0.0, 5.0, 10.0, 0.0), col])
	# Taxi rank: a line nose to tail along the kerb, heading west.
	for i in 5:
		var bs := Basis(Vector3.UP, -PI * 0.5)
		add.call(0, Transform3D(bs, Vector3(2222.0 - i * 6.0, Y - 0.03, 142.0) + bs.z * 5.0), Color(0.95, 0.78, 0.12))
	# Rental bays: rows under the canopies, a fleet in few colours.
	var fleet := [Color(0.92, 0.92, 0.93), Color(0.1, 0.11, 0.13), Color(0.62, 0.64, 0.66), Color(0.2, 0.32, 0.55)]
	for row: float in [RENTAL.position.y + 26.0, RENTAL.position.y + 34.0, RENTAL.position.y + 60.0, RENTAL.position.y + 68.0]:
		var bx := RENTAL.position.x + 24.0
		while bx < RENTAL.end.x - 6.0:
			if rng.randf() < 0.8:
				var yaw := PI if int(row) % 2 == 0 else 0.0
				var bs := Basis(Vector3.UP, yaw)
				add.call(rng.randi() % mini(3, mids.size()), Transform3D(bs, Vector3(bx, Y - 0.03, row) + bs.z * 5.0), fleet[rng.randi() % fleet.size()])
			bx += 2.7
	for k: int in groups:
		var list: Array = groups[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mids[k]
		mm.instance_count = list.size()
		mm.buffer = CityWorld._instance_buffer(list)
		var mi := MultiMeshInstance3D.new()
		mi.name = "DistrictCars_%d" % k
		mi.multimesh = mm
		mi.visibility_range_end = 320.0
		target.add_child(mi)


## Profiled-metal sheds (warehouses, hangars, the cargo terminal): the city
## mesher drew them with office windows. Records marked "clad" are drawn
## here – cladding bays round every tier, a roof cap with rooflights and a
## parapet, loading docks along a "docks" face; a hangar's front stays open
## for its doors (SkyportIsland._build_airport_dressing) with a header over.
## (Unless the kit is missing, in which case the city mesher draws them.)
static func build_clad(P: Dictionary, target: Node3D, isl: SkyportIsland) -> void:
	var K := {}
	var m := BuildingMesher.new()
	for b: Dictionary in P["buildings"]:
		if not b.has("clad"):
			continue
		var kind: String = b["clad"]
		var tiers: Array = b["tiers"]
		for ti in tiers.size():
			var t: Array = tiers[ti]
			var x0: float = t[0]
			var z0: float = t[1]
			var x1: float = t[2]
			var z1: float = t[3]
			var y0: float = t[4]
			var y1: float = t[5]
			var h := y1 - y0
			# [a, b, outward normal]
			for e: Array in [[Vector2(x0, z0), Vector2(x1, z0), Vector2(0, -1)], [Vector2(x1, z1), Vector2(x0, z1), Vector2(0, 1)],
					[Vector2(x0, z1), Vector2(x0, z0), Vector2(-1, 0)], [Vector2(x1, z0), Vector2(x1, z1), Vector2(1, 0)]]:
				var a: Vector2 = e[0]
				var c: Vector2 = e[1]
				var n: Vector2 = e[2]
				var L := a.distance_to(c)
				var bays := maxi(1, ceili(L / 6.0))
				var yaw := atan2(n.x, n.y)
				var front := b.has("hangar_front") and ti == 0 and n.y > 0.5 and absf(z1 - float(b["hangar_front"])) < 0.5
				var wall_y0 := y0
				if front:
					# (Doors below: the header band from the door head up.)
					wall_y0 = y1 - 3.6
				for k in bays:
					var q := a.lerp(c, (k + 0.5) / bays)
					var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(L / bays / 6.0, y1 - wall_y0, 1.0)),
						Vector3(q.x + n.x * 0.04, wall_y0, q.y + n.y * 0.04))
					if not K.has(kind):
						K[kind] = []
					(K[kind] as Array).append(xf)
				# Corner flashing and a concrete kick band.
				m.beam(Vector3(a.x, y0, a.y), Vector3(a.x, y1 + 0.3, a.y), 0.35, 0.35, Color(0.32, 0.34, 0.36))
				if not front:
					m.solid(minf(a.x, c.x) + minf(n.x, 0.0) * 0.18, minf(a.y, c.y) + minf(n.y, 0.0) * 0.18,
						maxf(a.x, c.x) + maxf(n.x, 0.0) * 0.18, maxf(a.y, c.y) + maxf(n.y, 0.0) * 0.18, y0, y0 + 0.9, Color(0.6, 0.59, 0.56))
			# Roof: cap, parapet line, rooflight strips (only the top tier
			# shows its roof).
			m.solid(x0 - 0.15, z0 - 0.15, x1 + 0.15, z1 + 0.15, y1, y1 + 0.3, Color(0.55, 0.57, 0.6))
			if ti == tiers.size() - 1 or (tiers.size() > 1 and ti == 0):
				var rx := x0 + 6.0
				while rx < x1 - 4.0:
					m.solid(rx - 0.7, z0 + 4.0, rx + 0.7, z1 - 4.0, y1 + 0.3, y1 + 0.42, Color(0.78, 0.85, 0.9))
					rx += 9.0
		if b.has("docks"):
			var t0: Array = tiers[0]
			var dz: float = b["docks"]
			var x: float = float(t0[0]) + 6.0
			while x < float(t0[2]) - 4.0:
				if not K.has("dock_door"):
					K["dock_door"] = []
				(K["dock_door"] as Array).append(Transform3D(Basis(Vector3.UP, PI), Vector3(x, Y, dz)))
				x += 7.5
	for nm: String in K:
		SkyportKit.place(target, nm, K[nm], 1400.0, true)
	isl._mesh_into(m, "CladTrim", target, 0.0, 1400.0)


## Walking loops for the crowd (local): the halls, the airside mall, the
## gate lounges and the forecourt pavement.
static func walk_loops() -> Array:
	var r := func(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	return [
		r.call(1972.0, 172.0, 2250.0, 186.5),
		r.call(1972.0, 206.0, 2250.0, 210.0),
		r.call(1972.0, 220.3, 2250.0, 221.0),
		r.call(2150.0, 187.0, 2254.0, 199.0),
	]


# =================================================================== life
class Movers extends Node3D:
	## Apron vehicles on loops, the radar turning, floodlights at night.
	var isl: SkyportIsland
	var _runs: Array = []    # [Node3D, PackedVector3Array, cum, speed, s]
	var _radar: Node3D
	var _lights: Array = []
	var _t := 0.0

	func setup(p_isl: SkyportIsland) -> void:
		isl = p_isl
		if not SkyportKit.ready():
			return
		var Yv := SkyportIsland.LAND_Y
		var v := func(x: float, z: float) -> Vector3: return Vector3(x, Yv, z)
		# Baggage trains on the airside service road (both directions).
		var svc := PackedVector3Array([v.call(1590, 251.5), v.call(2322, 251.5), v.call(2326, 248.5), v.call(2326, 247.0),
			v.call(1594, 247.0), v.call(1588, 249.0)])
		_run(["gse_tug", "gse_cart", "gse_cart", "gse_cart"], svc, 6.5, 0.0)
		_run(["gse_tug", "gse_cart", "gse_cart"], svc, 6.0, 0.5)
		_run(["gse_tug", "gse_cart"], svc, 5.0, 0.25)
		# Apron bus: remote stand ↔ the terminal's west end.
		var bus := PackedVector3Array([v.call(1690, 322), v.call(1690, 300), v.call(1720, 268), v.call(1960, 262), v.call(1972, 268),
			v.call(1972, 300), v.call(1880, 300), v.call(1760, 330)])
		_run(["gse_bus"], bus, 7.0, 0.0)
		# Follow-me car up and down the parallel taxiway.
		var tw := PackedVector3Array([v.call(1500, 392), v.call(3150, 392), v.call(3160, 398), v.call(1490, 398)])
		_run(["gse_follow"], tw, 14.0, 0.3)
		# Bowser between the fuel farm road and the cargo apron.
		var fuel := PackedVector3Array([v.call(2350, 350), v.call(2455, 350), v.call(2455, 372), v.call(2350, 372)])
		_run(["gse_fuel"], fuel, 5.0, 0.0)
		# The radar.
		var rm := SkyportKit.mesh("radar_head")
		if rm:
			_radar = MeshInstance3D.new()
			(_radar as MeshInstance3D).mesh = rm
			_radar.position = Vector3(1466.0, Yv + 16.5, 360.0)
			(_radar as MeshInstance3D).visibility_range_end = 2600.0
			add_child(_radar)
		# Apron floodlights (the terminal masts): real lights, night only.
		for mp: Vector2 in SkyportAirport.mast_points().slice(0, 5):
			var l := SpotLight3D.new()
			l.position = Vector3(mp.x, Yv + 32.0, mp.y - 1.0)
			l.rotation = Vector3(-PI * 0.36, 0.0, 0.0)
			l.spot_range = 80.0
			l.spot_angle = 58.0
			l.light_energy = 9.0
			l.light_color = Color(1.0, 0.95, 0.86)
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 700.0
			l.distance_fade_length = 100.0
			l.visible = false
			add_child(l)
			_lights.append(l)

	func _run(parts: Array, path: PackedVector3Array, speed: float, phase: float) -> void:
		var cum := PackedFloat32Array([0.0])
		for i in path.size():
			cum.append(cum[i] + path[i].distance_to(path[(i + 1) % path.size()]))
		var nodes: Array = []
		for nm: String in parts:
			var mesh := SkyportKit.mesh(nm)
			if mesh == null:
				return
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.visibility_range_end = 700.0
			add_child(mi)
			nodes.append(mi)
		_runs.append([nodes, path, cum, speed, phase * cum[path.size()]])

	func _pose(path: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Array:
		var L := cum[path.size()]
		s = fposmod(s, L)
		var i := cum.bsearch(s, true) - 1
		i = clampi(i, 0, path.size() - 1)
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var t := (s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.001)
		var d := (b - a).normalized()
		return [a.lerp(b, t), atan2(-d.x, -d.z)]

	func _process(dt: float) -> void:
		_t += dt
		var cam := get_viewport().get_camera_3d()
		var near := true
		if cam:
			near = SkyportIsland.distance_to(cam.global_position) < 900.0
		if _radar:
			_radar.rotation.y = _t * 1.3
		var nt := float(isl.world_ref.get("night_amount")) if isl and is_instance_valid(isl.world_ref) else 0.0
		for l: SpotLight3D in _lights:
			l.visible = nt > 0.35
		if not near:
			return
		for r: Array in _runs:
			r[4] = float(r[4]) + float(r[3]) * dt
			var nodes: Array = r[0]
			for k in nodes.size():
				# (The train: each trailer 3.3 m behind the one ahead; the
				# heading of its own spot so corners fold the train round.)
				var gap := 0.0 if k == 0 else (4.2 + (k - 1) * 3.2)
				var po: Array = _pose(r[1], r[2], float(r[4]) - gap)
				var nd: Node3D = nodes[k]
				nd.position = po[0]
				nd.rotation.y = lerp_angle(nd.rotation.y, float(po[1]), minf(1.0, dt * 6.0))
