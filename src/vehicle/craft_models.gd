class_name CraftModels
extends RefCounted
## Low-poly procedural models for Craft (helicopters, planes, boats): a few
## dozen boxes each in vertex colours, one material shared by all, front
## along -Z. Each model is its own silhouette (not a recolour): a bubble
## trainer, a sleek turbine, an executive twin; a high-wing prop, a twin, a
## T-tail jet; an open runabout, a deep-vee speedboat, a two-deck yacht.

static var _mat: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.45
		_mat.metallic_specular = 0.6
	return _mat


static func build(kind: String, model: String, spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var paint: Color = spec.get("paint", Color(0.9, 0.9, 0.9))
	var trim: Color = spec.get("trim", Color(0.15, 0.17, 0.2))
	var glass := Color(0.12, 0.16, 0.2)
	var b := _M.new()
	var rotor := _M.new()
	match kind:
		"heli":
			var L: float = spec.get("size", Vector3(2.4, 2.6, 9.0)).z
			var big := L > 11.0
			b.box(Vector3(-1.0, 0.6, -2.2), Vector3(1.0, 2.4, 1.0), paint)                 # cabin
			b.box(Vector3(-0.95, 1.3, -2.9), Vector3(0.95, 2.3, -2.2), glass)               # windscreen
			if big:
				b.box(Vector3(-1.1, 0.6, -3.4), Vector3(1.1, 2.5, 1.6), paint)              # long cabin
				b.box(Vector3(-1.12, 1.5, -2.6), Vector3(1.12, 2.1, 1.2), glass)            # side windows
				b.box(Vector3(-1.13, 0.9, -3.0), Vector3(1.13, 1.2, 1.4), trim)             # stripe
			b.box(Vector3(-0.3, 1.5, 1.0), Vector3(0.3, 2.1, L * 0.55), paint)              # tail boom
			b.box(Vector3(-0.08, 1.6, L * 0.5), Vector3(0.08, 3.2, L * 0.58), trim)         # fin
			b.box(Vector3(-0.9, 1.9, L * 0.5), Vector3(0.9, 2.0, L * 0.56), trim)           # stabiliser
			for s: float in [-1.0, 1.0]:
				b.box(Vector3(s * 1.2 - 0.06, 0.0, -2.4), Vector3(s * 1.2 + 0.06, 0.1, 1.2), trim)  # skids
				b.box(Vector3(s * 1.0 - 0.05, 0.1, -1.5), Vector3(s * 1.0 + 0.05, 0.7, -1.4), trim)
				b.box(Vector3(s * 1.0 - 0.05, 0.1, 0.4), Vector3(s * 1.0 + 0.05, 0.7, 0.5), trim)
			b.box(Vector3(-0.15, 2.4, -0.3), Vector3(0.15, 2.8, 0.1), trim)                 # mast
			var r: float = spec.get("rotor_r", 4.6)
			rotor.box(Vector3(-r, 0.0, -0.18), Vector3(r, 0.06, 0.18), trim)
			rotor.box(Vector3(-0.18, 0.0, -r), Vector3(0.18, 0.06, r), trim)
		"plane" when model == "liner":
			_liner(b, spec, paint, trim, glass)
			var lg := _M.new()
			var LL: float = (spec.get("size", Vector3(34, 9, 36)) as Vector3).z
			for g in [[0.0, -LL * 0.38], [-2.9, LL * 0.03], [2.9, LL * 0.03]]:
				lg.box(Vector3(g[0] - 0.15, 0.5, g[1] - 0.15), Vector3(g[0] + 0.15, 2.0, g[1] + 0.15), Color(0.7, 0.7, 0.72))
				lg.box(Vector3(g[0] - 0.55, 0.0, g[1] - 0.6), Vector3(g[0] + 0.55, 1.0, g[1] + 0.6), Color(0.08, 0.08, 0.08))
			var lgn := Node3D.new()
			lgn.name = "Gear"
			var lgm := MeshInstance3D.new()
			lgm.mesh = lg.commit()
			lgm.material_override = material()
			lgn.add_child(lgm)
			root.add_child(lgn)
		"plane":
			var sz: Vector3 = spec.get("size", Vector3(11, 3, 9))
			var span := sz.x
			var L := sz.z
			var jet: bool = spec.get("jet", false)
			var high: bool = spec.get("high_wing", false)
			b.box(Vector3(-0.8, 0.9, -L * 0.5), Vector3(0.8, 2.3, L * 0.38), paint)        # fuselage
			b.box(Vector3(-0.5, 1.2, L * 0.38), Vector3(0.5, 2.1, L * 0.5), paint)         # tail cone
			b.box(Vector3(-0.7, 1.7, -L * 0.5 + 0.6), Vector3(0.7, 2.25, -L * 0.5 + 1.8), glass)
			b.box(Vector3(-0.82, 1.6, -L * 0.3), Vector3(0.82, 1.95, L * 0.25), glass)     # cabin windows
			var wy := 2.35 if high else 1.0
			b.box(Vector3(-span * 0.5, wy, -L * 0.12), Vector3(span * 0.5, wy + 0.22, L * 0.08), paint)  # wing
			b.box(Vector3(-span * 0.5, wy - 0.01, -L * 0.12), Vector3(-span * 0.5 + 0.6, wy + 0.23, L * 0.08), trim)
			b.box(Vector3(span * 0.5 - 0.6, wy - 0.01, -L * 0.12), Vector3(span * 0.5, wy + 0.23, L * 0.08), trim)
			var tail_y := 3.6 if jet else 1.9
			b.box(Vector3(-0.1, 1.9, L * 0.36), Vector3(0.1, tail_y + 0.4, L * 0.5), trim)          # fin
			b.box(Vector3(-span * 0.18, tail_y, L * 0.4), Vector3(span * 0.18, tail_y + 0.18, L * 0.5), paint)  # tailplane
			if jet:
				for s: float in [-1.0, 1.0]:
					b.box(Vector3(s * 1.0 - 0.45, 1.8, L * 0.18), Vector3(s * 1.0 + 0.45, 2.5, L * 0.36), trim)  # engines
			else:
				var engines: Array = [0.0] if not bool(spec.get("twin", false)) else [-span * 0.22, span * 0.22]
				for ex: float in engines:
					var ez := -L * 0.5 - 0.2 if ex == 0.0 else -L * 0.18
					b.box(Vector3(ex - 0.4, wy - 0.5 if ex != 0.0 else 1.2, ez), Vector3(ex + 0.4, wy + 0.1 if ex != 0.0 else 2.0, ez + 1.6), paint)
					rotor.box(Vector3(ex - 1.1, (wy - 0.2 if ex != 0.0 else 1.6) - 0.08, ez - 0.15), Vector3(ex + 1.1, (wy - 0.2 if ex != 0.0 else 1.6) + 0.08, ez - 0.1), trim)
			# Undercarriage (its own mesh "Gear": Craft retracts it in the air).
			var gear := _M.new()
			for g in [[0.0, -L * 0.36], [-1.4, L * 0.05], [1.4, L * 0.05]]:
				gear.box(Vector3(g[0] - 0.08, 0.3, g[1] - 0.08), Vector3(g[0] + 0.08, 1.0, g[1] + 0.08), trim)
				gear.box(Vector3(g[0] - 0.12, 0.0, g[1] - 0.3), Vector3(g[0] + 0.12, 0.6, g[1] + 0.3), Color(0.08, 0.08, 0.08))
			var gn := Node3D.new()
			gn.name = "Gear"
			gn.position = Vector3(0, 1.0, 0)
			var gmi := MeshInstance3D.new()
			gmi.mesh = gear.commit()
			gmi.material_override = material()
			gmi.position = Vector3(0, -1.0, 0)
			gn.add_child(gmi)
			root.add_child(gn)
		_:
			var sz: Vector3 = spec.get("size", Vector3(2.2, 1.4, 6.0))
			var w := sz.x * 0.5
			var L := sz.z
			var hull := Color(0.95, 0.95, 0.93)
			b.box(Vector3(-w, -0.5, -L * 0.3), Vector3(w, 0.6, L * 0.5), hull)             # hull
			b.box(Vector3(-w * 0.6, -0.4, -L * 0.5), Vector3(w * 0.6, 0.6, -L * 0.3), hull)  # bow
			b.box(Vector3(-w - 0.02, 0.1, -L * 0.3), Vector3(w + 0.02, 0.3, L * 0.5), paint)  # boot stripe
			b.box(Vector3(-w * 0.9, 0.6, -L * 0.25), Vector3(w * 0.9, 0.7, L * 0.45), Color(0.72, 0.58, 0.42))  # deck
			if L > 20.0:
				# Yacht: a saloon deck and a flybridge above it.
				b.box(Vector3(-w * 0.8, 0.7, -L * 0.15), Vector3(w * 0.8, 2.9, L * 0.3), hull)
				b.box(Vector3(-w * 0.81, 1.7, -L * 0.15), Vector3(w * 0.81, 2.6, L * 0.28), glass)
				b.box(Vector3(-w * 0.6, 2.9, -L * 0.05), Vector3(w * 0.6, 4.6, L * 0.18), hull)
				b.box(Vector3(-w * 0.61, 3.6, -L * 0.05), Vector3(w * 0.61, 4.3, L * 0.16), glass)
				b.box(Vector3(-0.1, 4.6, 0.0), Vector3(0.1, 7.0, 0.2), trim)                # mast
			else:
				b.box(Vector3(-w * 0.7, 0.7, -L * 0.12), Vector3(w * 0.7, 1.5, L * 0.05), glass)  # screen
				b.box(Vector3(-w * 0.7, 0.7, L * 0.1), Vector3(w * 0.7, 1.05, L * 0.35), paint)   # seats
				b.box(Vector3(-0.3, -0.3, L * 0.5), Vector3(0.3, 0.8, L * 0.5 + 0.6), trim)        # outboard
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = material()
	root.add_child(mi)
	if not rotor.empty():
		var rn := Node3D.new()
		rn.name = "Rotor"
		if kind == "heli":
			rn.position = Vector3(0.0, 2.85, -0.1)
		root.add_child(rn)
		var rmi := MeshInstance3D.new()
		rmi.mesh = rotor.commit()
		rmi.material_override = material()
		rn.add_child(rmi)
		if kind == "plane":
			rn.name = "Props"  # (props are drawn as fixed blurred bars)
	return root


## A narrow-body airliner (Skyport's scheduled traffic and the planes at
## the gates): a 4 m fuselage with a tapered nose and tail cone, swept wings
## in three steps with winglets, two engines under them, a tall fin in the
## airline's colour, cockpit and cabin window lines, a cheatline. Nose at
## −z, wheels at y 0. spec: size (span, –, length), paint, trim.
static func _liner(b: _M, spec: Dictionary, paint: Color, trim: Color, glass: Color) -> void:
	var sz: Vector3 = spec.get("size", Vector3(34, 9, 36))
	var L := sz.z
	var hs := sz.x * 0.5
	var grey := Color(0.62, 0.64, 0.67)
	var dark := Color(0.1, 0.12, 0.15)
	var n0 := -L * 0.5
	# Fuselage: an octagon-ish section from two boxes.
	b.box(Vector3(-2.0, 2.3, n0 + 4.0), Vector3(2.0, 5.3, L * 0.3), paint)
	b.box(Vector3(-1.55, 1.8, n0 + 4.0), Vector3(1.55, 5.8, L * 0.3), paint)
	b.box(Vector3(-2.25, 1.5, -L * 0.1), Vector3(2.25, 2.4, L * 0.14), grey)          # wing-root fairing
	# Nose: tapering steps, the cockpit glazing on the last.
	b.box(Vector3(-1.75, 2.1, n0 + 2.0), Vector3(1.75, 5.4, n0 + 4.0), paint)
	b.box(Vector3(-1.35, 2.5, n0 + 0.8), Vector3(1.35, 4.9, n0 + 2.0), paint)
	b.box(Vector3(-0.85, 2.9, n0), Vector3(0.85, 4.3, n0 + 0.8), paint)
	b.box(Vector3(-1.38, 4.1, n0 + 1.0), Vector3(1.38, 4.7, n0 + 2.3), dark)          # cockpit windows
	# Tail cone up to the fin.
	b.box(Vector3(-1.5, 2.9, L * 0.3), Vector3(1.5, 5.6, L * 0.4), paint)
	b.box(Vector3(-0.9, 3.8, L * 0.4), Vector3(0.9, 5.4, L * 0.5), paint)
	# Cabin windows and the cheatline, both sides.
	for s: float in [-1.0, 1.0]:
		var x0 := s * 2.0
		b.box(Vector3(x0 - 0.03 * s, 4.15, n0 + 4.5), Vector3(x0 + 0.03 * s, 4.45, L * 0.27), dark)
		b.box(Vector3(x0 - 0.03 * s, 3.3, n0 + 2.5), Vector3(x0 + 0.03 * s, 3.65, L * 0.3), trim)
		b.box(Vector3(x0 - 0.03 * s, 2.9, n0 + 5.0), Vector3(x0 + 0.03 * s, 4.6, n0 + 6.0), Color(0.82, 0.83, 0.85))  # door
	# Wings: three swept steps out to the winglets (low wing).
	var steps := [[1.8, hs * 0.38, 0.0], [hs * 0.38, hs * 0.72, 1.8], [hs * 0.72, hs, 3.6]]
	for s: float in [-1.0, 1.0]:
		for st: Array in steps:
			var xa := float(st[0])
			var xb := float(st[1])
			var dz := float(st[2])
			var chord := lerpf(L * 0.2, L * 0.07, xb / hs)
			b.box(Vector3(s * xa, 2.0 + xa * 0.04, -L * 0.1 + dz), Vector3(s * xb, 2.35 + xa * 0.04, -L * 0.1 + dz + chord), paint)
		b.box(Vector3(s * (hs - 0.15), 2.35 + hs * 0.04, -L * 0.1 + 4.6), Vector3(s * hs, 4.6, -L * 0.1 + 6.4), trim)  # winglet
		# Engine under the wing on a pylon.
		var ex := s * hs * 0.36
		b.box(Vector3(ex - 1.15, 0.85, -L * 0.2), Vector3(ex + 1.15, 2.9, -L * 0.06), trim)
		b.box(Vector3(ex - 1.0, 1.0, -L * 0.2 - 0.05), Vector3(ex + 1.0, 2.75, -L * 0.2), dark)   # intake
		b.box(Vector3(ex - 0.25, 2.8, -L * 0.14), Vector3(ex + 0.25, 2.1 + hs * 0.04 + 0.2, -L * 0.03), grey)
		# Tailplane.
		b.box(Vector3(s * 0.8, 4.6, L * 0.37), Vector3(s * hs * 0.36, 4.85, L * 0.46), paint)
	# Fin (the airline's colour), stepped back as it rises.
	b.box(Vector3(-0.22, 5.4, L * 0.33), Vector3(0.22, 8.6, L * 0.5), trim)
	b.box(Vector3(-0.2, 8.6, L * 0.38), Vector3(0.2, 11.4, L * 0.5), trim)
	b.box(Vector3(-0.18, 11.4, L * 0.43), Vector3(0.18, 12.6, L * 0.5), trim)


class _M:
	var st := SurfaceTool.new()
	var n := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func empty() -> bool:
		return n == 0

	func box(a: Vector3, b: Vector3, c: Color) -> void:
		var lo := a.min(b)
		var hi := a.max(b)
		var v := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
		_q(v[1], v[0], v[3], v[2], Vector3(0, 0, -1), c)
		_q(v[4], v[5], v[6], v[7], Vector3(0, 0, 1), c)
		_q(v[0], v[4], v[7], v[3], Vector3(-1, 0, 0), c)
		_q(v[5], v[1], v[2], v[6], Vector3(1, 0, 0), c)
		_q(v[0], v[1], v[5], v[4], Vector3(0, -1, 0), c)
		_q(v[7], v[6], v[2], v[3], Vector3(0, 1, 0), c)

	func _q(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
		for p in [a, cc, b, a, d, cc]:
			st.set_color(col)
			st.set_normal(nrm)
			st.add_vertex(p)
		n += 6

	func commit() -> ArrayMesh:
		return st.commit()
