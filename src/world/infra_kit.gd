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


static func place(target: Node3D, list: Dictionary, range_end := 1600.0) -> void:
	if not SkyportKit.ready():
		return
	for name: String in list:
		SkyportKit.place(target, name, list[name], range_end if name != "underpass_lamp" else 400.0, name != "underpass_lamp")
