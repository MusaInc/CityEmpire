class_name InfraKit
extends RefCounted
## Engineered bridge / viaduct parts from the Blender kit (SkyportKit
## meshes pier_column, pier_head, pier_foot, deck_girders, underpass_lamp):
## the generators record transforms here (pure data, thread-safe) and the
## builders instance them as MultiMeshes. Replaced the square column + flat
## crosshead ("T") piers and the bare flat deck soffits everywhere.
##
## A list is a Dictionary: mesh name -> Array[Transform3D].


static func _add(list: Dictionary, name: String, xf: Transform3D) -> void:
	if not list.has(name):
		list[name] = []
	(list[name] as Array).append(xf)


## A pier: footing at `ground` (its top 0.22·foot_h above), a chamfered
## column up to the underside of a tapered hammerhead whose top is top_y.
## dir: the deck's direction (the head spans across it).
static func pier(list: Dictionary, ground: Vector3, top_y: float, dir: Vector3, col_w: float, span: float,
		head_depth: float, head_t: float, columns := [0.0]) -> void:
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	var basis_of := func(sx: float, sy: float, sz: float) -> Basis:
		return Basis(side * sx, Vector3.UP * sy, -dir * sz)
	var head_bot := top_y - head_depth
	for off: float in columns:
		var g := ground + side * off
		var h := head_bot - g.y + 0.1
		if h < 0.5:
			continue
		_add(list, "pier_foot", Transform3D(basis_of.call(col_w * 2.1, maxf(col_w * 0.6, 0.9), col_w * 2.1), g))
		_add(list, "pier_column", Transform3D(basis_of.call(col_w, h, col_w * 0.9), g))
	_add(list, "pier_head", Transform3D(basis_of.call(span, head_depth, head_t), Vector3(ground.x, top_y, ground.z)))


## A portal frame: a column on each footing (a, b: ground points either
## side of the road it straddles) under a cap beam whose top is top_y,
## carrying whatever deck rests on it. Wide-span replacement for a median
## pier that would stand in a carriageway. The cap is the pier head mesh
## run the full width (haunched ends) with steel girders hung beneath.
static func portal(list: Dictionary, a: Vector3, b: Vector3, top_y: float, col_w: float, beam_depth: float) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var span := d.length()
	if span < 0.5:
		return
	var across := d / span
	var along := Vector3(across.z, 0.0, -across.x)   # (the deck's direction, roughly)
	var basis_of := func(sx: float, sy: float, sz: float) -> Basis:
		return Basis(across * sx, Vector3.UP * sy, -along * sz)
	var head_bot := top_y - beam_depth
	for g: Vector3 in [a, b]:
		var h := head_bot - g.y + 0.1
		if h < 0.5:
			continue
		_add(list, "pier_foot", Transform3D(basis_of.call(col_w * 2.0, maxf(col_w * 0.6, 0.9), col_w * 2.0), g))
		_add(list, "pier_column", Transform3D(basis_of.call(col_w, h, col_w * 0.95), g))
	var mid := Vector3((a.x + b.x) * 0.5, top_y, (a.z + b.z) * 0.5)
	_add(list, "pier_head", Transform3D(basis_of.call(span + col_w * 1.4, beam_depth * 0.55, 2.1), mid))
	_add(list, "deck_girders", Transform3D(Basis(across * (span + col_w * 0.8), Vector3.UP * beam_depth * 0.45, -along * 1.9),
		mid + Vector3.DOWN * beam_depth * 0.55))


## The deck's underside from a to b (points on the soffit centre line):
## girders `width` across, `depth` deep, and a soffit lamp every other bay
## when `lamps` (over roads and paths).
static func girders(list: Dictionary, a: Vector3, b: Vector3, width: float, depth: float, lamps := false) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.5:
		return
	var side := Vector3(-d.z, 0.0, d.x).normalized()
	_add(list, "deck_girders", Transform3D(Basis(d, Vector3.UP * depth, -side * width), (a + b) * 0.5))
	if lamps:
		for sg: float in [-0.22, 0.22]:
			_add(list, "underpass_lamp", Transform3D(Basis(d.normalized(), Vector3.UP, -side), (a + b) * 0.5 + side * sg * width - Vector3.UP * depth * 0.02))


## Architectural glazed-and-clad transit access pavilion (stair/lift tower):
## grounded granite plinth with street-level entrance canopy, stacked glazed
## curtain-wall storeys with structural corner piers and concrete lift core,
## and a cantilevered roof crown with warm recessed soffit lighting.
## `base`: ground centre, `top_y`: platform/roof level, `front`: street-facing unit dir.
static func pavilion(list: Dictionary, base: Vector3, top_y: float, front: Vector3, width: float, depth: float,
		crown_h := 1.45, plinth_h := 2.8) -> void:
	var f := Vector3(front.x, 0.0, front.z)
	f = f.normalized() if f.length() > 0.001 else Vector3.FORWARD
	var side := Vector3(-f.z, 0.0, f.x)
	var b_of := func(sx: float, sy: float, sz: float) -> Basis:
		return Basis(side * sx, Vector3.UP * sy, -f * sz)
	var total_h := maxf(top_y - base.y, 4.0)
	var ph := minf(plinth_h, total_h * 0.35)
	_add(list, "transit_pavilion_base", Transform3D(b_of.call(width, ph, depth), base))
	var shaft_h := maxf(total_h - ph, 1.5)
	var storeys := maxi(1, roundi(shaft_h / 3.8))
	var sh := shaft_h / float(storeys)
	for i in storeys:
		_add(list, "transit_pavilion_bay", Transform3D(b_of.call(width, sh + 0.04, depth),
			Vector3(base.x, base.y + ph + float(i) * sh, base.z)))
	_add(list, "transit_pavilion_crown", Transform3D(b_of.call(width, crown_h, depth),
		Vector3(base.x, base.y + total_h - 0.12, base.z)))


## Enclosed glazed pedestrian skywalk bridge from `a` to `b` (floor centre line):
## structural underside box girder, full-height tinted glass walls with dark steel
## mullions and handrails, and an integrated cantilevered roof canopy with lighting.
static func skywalk(list: Dictionary, a: Vector3, b: Vector3, width := 3.2, height := 3.3, bay_len := 5.5) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.8:
		return
	var dir := d / L
	var side := Vector3(-dir.z, 0.0, dir.x).normalized()
	var n := maxi(1, ceili(L / bay_len))
	var step := L / float(n)
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		_add(list, "skywalk_bay", Transform3D(Basis(dir * (step + 0.04), Vector3.UP * height, -side * width),
			(p0 + p1) * 0.5))


## Sculpted cantilevered platform support brackets along a station platform edge,
## visually tying elevated station platforms into the central viaduct box girder.
static func platform_brackets(list: Dictionary, a: Vector3, b: Vector3, out_dir: Vector3,
		reach := 3.4, depth := 1.65, spacing := 7.5, thickness := 0.55) -> void:
	var d := b - a
	var L := d.length()
	if L < 2.0:
		return
	var along := d / L
	var out := Vector3(out_dir.x, 0.0, out_dir.z).normalized()
	var n := maxi(2, ceili(L / spacing))
	for i in n + 1:
		var u := lerpf(0.04, 0.96, float(i) / float(n))
		var p := a.lerp(b, u)
		_add(list, "platform_bracket", Transform3D(Basis(out * reach, Vector3.UP * depth, -along * thickness), p))


static func place(target: Node3D, list: Dictionary, range_end := 1600.0) -> void:
	if not SkyportKit.ready():
		return
	for name: String in list:
		SkyportKit.place(target, name, list[name], range_end if name != "underpass_lamp" else 400.0, name != "underpass_lamp")
