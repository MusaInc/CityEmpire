class_name StreetClutter
extends RefCounted
## Small procedural street things for CityWorld's furniture (merged into each
## chunk's one furniture mesh: no extra draw calls, no textures):
##   utility_box     green steel street cabinet (telecoms/power) with vents
##   crates          stacked bread crates on a pallet by a shopfront
##   litter          a few flattened cups/papers and a can by a bin (no collision)
##   banner_<district> a lamp-post banner pair in the district's colours
##                   (wayfinding: each quarter has its own), no collision
## Arrays as CityWorld._flatten_colors: [verts, normals, colours, indices].
## Colours are sRGB (the furniture material converts).

const NO_COLLISION := ["litter", "tree_grate", "banner_cbd", "banner_midtown", "banner_waterfront", "banner_docks",
	"banner_georgian", "banner_shops"]
## Banner colours per district: [field, stripe].
const BANNERS := {
	"cbd": [Color(0.1, 0.18, 0.36), Color(0.85, 0.72, 0.38)],
	"midtown": [Color(0.55, 0.12, 0.2), Color(0.95, 0.92, 0.86)],
	"waterfront": [Color(0.1, 0.42, 0.55), Color(0.97, 0.97, 0.95)],
	"docks": [Color(0.86, 0.5, 0.12), Color(0.15, 0.15, 0.16)],
	"georgian": [Color(0.16, 0.34, 0.24), Color(0.88, 0.78, 0.5)],
	"shops": [Color(0.62, 0.22, 0.52), Color(0.98, 0.84, 0.3)],
}


static func kinds() -> Array:
	var out := ["utility_box", "crates", "litter", "tree_grate"]
	for d in BANNERS:
		out.append("banner_" + d)
	return out


## Flush cast-iron tree grate & dark soil surround (no sidewalk obstruction).
static func tree_grate_box(size := 1.5) -> Array:
	var b := _B.new()
	var h := size * 0.5
	var rim := 0.09
	var iron := Color(0.17, 0.18, 0.19)
	var kerb := Color(0.46, 0.45, 0.43)
	var soil := Color(0.19, 0.14, 0.10)
	# Recessed dark soil bed inside the tree pit.
	b.box(Vector3(-h + rim, 0.0, -h + rim), Vector3(h - rim, 0.010, h - rim), soil)
	# Low flush granite kerb surround (4 edge strips).
	b.box(Vector3(-h, 0.0, -h), Vector3(h, 0.028, -h + rim), kerb)
	b.box(Vector3(-h, 0.0, h - rim), Vector3(h, 0.028, h), kerb)
	b.box(Vector3(-h, 0.0, -h + rim), Vector3(-h + rim, 0.028, h - rim), kerb)
	b.box(Vector3(h - rim, 0.0, -h + rim), Vector3(h, 0.028, h - rim), kerb)
	# Cast-iron inner collar around the trunk opening.
	var c := minf(0.28, h * 0.42)
	var ct := 0.045
	b.box(Vector3(-c, 0.010, -c), Vector3(c, 0.026, -c + ct), iron)
	b.box(Vector3(-c, 0.010, c - ct), Vector3(c, 0.026, c), iron)
	b.box(Vector3(-c, 0.010, -c + ct), Vector3(-c + ct, 0.026, c - ct), iron)
	b.box(Vector3(c - ct, 0.010, -c + ct), Vector3(c, 0.026, c - ct), iron)
	# Slotted cast-iron grate bars spanning from trunk collar to kerb rim.
	var span := h - rim - c
	if span > 0.08:
		for sg: float in [-1.0, 1.0]:
			for t: float in [-0.55, -0.22, 0.22, 0.55]:
				var off := t * (h - rim - 0.04)
				b.box(Vector3(off - 0.018, 0.010, sg * c), Vector3(off + 0.018, 0.024, sg * (h - rim)), iron)
				b.box(Vector3(sg * c, 0.010, off - 0.018), Vector3(sg * (h - rim), 0.024, off + 0.018), iron)
	return b.arrays()


static func build(kind: String) -> Array:
	var b := _B.new()
	match kind:
		"utility_box":
			var green := Color(0.2, 0.33, 0.24)
			b.box(Vector3(-0.45, 0.0, -0.2), Vector3(0.45, 1.25, 0.2), green)
			b.box(Vector3(-0.48, 1.25, -0.23), Vector3(0.48, 1.3, 0.23), green.darkened(0.2))   # lid
			b.box(Vector3(-0.47, 0.0, -0.22), Vector3(0.47, 0.1, 0.22), Color(0.5, 0.5, 0.48))  # plinth
			for i in 5:
				var y := 0.85 + i * 0.06
				b.box(Vector3(-0.3, y, 0.2), Vector3(0.3, y + 0.025, 0.215), green.darkened(0.45))  # vents
			b.box(Vector3(-0.02, 0.35, 0.2), Vector3(0.02, 0.75, 0.215), green.darkened(0.5))     # door split
			b.box(Vector3(0.1, 0.55, 0.2), Vector3(0.2, 0.6, 0.225), Color(0.75, 0.75, 0.72))       # lock
			b.box(Vector3(-0.38, 0.25, 0.2), Vector3(-0.08, 0.45, 0.212), Color(0.85, 0.83, 0.75))  # old sticker
		"crates":
			b.box(Vector3(-0.6, 0.0, -0.4), Vector3(0.6, 0.14, 0.4), Color(0.62, 0.48, 0.3))    # pallet
			var cols := [Color(0.14, 0.3, 0.55), Color(0.8, 0.2, 0.15), Color(0.14, 0.3, 0.55), Color(0.2, 0.45, 0.25)]
			var i := 0
			for x: float in [-0.3, 0.3]:
				for lvl in (3 if x < 0.0 else 2):
					var y := 0.14 + lvl * 0.3
					var c: Color = cols[i % cols.size()]
					b.box(Vector3(x - 0.28, y, -0.35), Vector3(x + 0.28, y + 0.28, 0.35), c)
					b.box(Vector3(x - 0.285, y + 0.08, -0.355), Vector3(x + 0.285, y + 0.16, 0.355), c.darkened(0.35))  # handle slots
					i += 1
		"litter":
			b.box(Vector3(-0.3, 0.0, 0.05), Vector3(-0.12, 0.006, 0.2), Color(0.92, 0.9, 0.84))    # paper
			b.box(Vector3(0.1, 0.0, -0.25), Vector3(0.26, 0.006, -0.12), Color(0.85, 0.82, 0.7))   # flattened cup
			b.box(Vector3(0.22, 0.0, 0.18), Vector3(0.34, 0.035, 0.24), Color(0.7, 0.15, 0.12))   # can on its side
			b.box(Vector3(-0.05, 0.0, -0.05), Vector3(0.05, 0.004, 0.06), Color(0.4, 0.55, 0.75))  # wrapper
		"tree_grate":
			return tree_grate_box(1.5)
		_:
			if kind.begins_with("banner_"):
				var pal: Array = BANNERS.get(kind.trim_prefix("banner_"), BANNERS["shops"])
				var field: Color = pal[0]
				var stripe: Color = pal[1]
				var steel := Color(0.22, 0.23, 0.25)
				# Two arms off the pole on the pavement side (+z) and the cloth
				# between them, hanging along the street (thin in x).
				for y: float in [3.5, 4.9]:
					b.box(Vector3(-0.02, y - 0.02, 0.08), Vector3(0.02, y + 0.02, 0.72), steel)
				b.box(Vector3(-0.012, 3.55, 0.12), Vector3(0.012, 4.88, 0.7), field)
				b.box(Vector3(-0.016, 4.45, 0.12), Vector3(0.016, 4.62, 0.7), stripe)
				b.box(Vector3(-0.016, 3.7, 0.12), Vector3(0.016, 3.78, 0.7), stripe)
	return b.arrays()


class _B:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func box(a: Vector3, b: Vector3, col: Color) -> void:
		var lo := a.min(b)
		var hi := a.max(b)
		var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
		_q(p[1], p[0], p[3], p[2], Vector3(0, 0, -1), col)
		_q(p[4], p[5], p[6], p[7], Vector3(0, 0, 1), col)
		_q(p[0], p[4], p[7], p[3], Vector3(-1, 0, 0), col)
		_q(p[5], p[1], p[2], p[6], Vector3(1, 0, 0), col)
		_q(p[7], p[6], p[2], p[3], Vector3(0, 1, 0), col)

	func _q(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
		var base := v.size()
		for p in [a, b, cc, d]:
			v.append(p)
			n.append(nrm)
			c.append(col)
		# (Godot's front faces are clockwise: a, c, b for CCW input.)
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))

	func arrays() -> Array:
		return [v, n, c, idx]
