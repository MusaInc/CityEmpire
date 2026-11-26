class_name ShopfrontKit
extends RefCounted
## Real shopfronts on the decorative ground floors (2026-11-26 storefront
## overhaul). Where building.gdshader paints shops along a ground floor
## (BuildingMesher.ground_shops), every whole 6 m bay of the shader's
## perimeter grid gets a 3D module laid flush on the wall: projecting piers
## with corbels, a fascia board carrying a fictional business's sign
## (assets/world/shop_brands.png, config/world/shop_brands.json), cornice,
## stall riser and sill, framed display windows with mullions and transom
## lights, and a recessed entrance – glazed returns, tiled threshold, soffit
## and a glazed door with its push bar. The windows trace a shallow interior
## behind the glass (shopfront.gdshader: shelving, a display table, counter,
## ceiling lights; by trade), lit at night while the shop is open. Some bays
## add a projecting blade sign, an A-board or planters on the pavement.
##
## Performance: three bay layouts (door centre / left / right) + a blade sign
## + two pavement props, each ONE shared mesh drawn by a MultiMesh per streamed
## chunk (instance colour = paint, custom = brand, trade, seed, open), one
## shader, one 2048² atlas. Visible to RANGE m; past that the building
## shader's painted shopfronts carry on, on the same grid.

const BAY := 6.0
const RANGE := 135.0
const PROP_RANGE := 70.0
const CELL := 50.0
const GLASS_Z := 0.28        # the shop windows' line, out from the wall
const PIER := 0.22           # half a pier at each end of a bay
const DOOR_W := 1.15
const SHADER := preload("res://src/world/shaders/shopfront.gdshader")
const ATLAS := "res://assets/world/shop_brands.png"
const BRANDS := "res://config/world/shop_brands.json"
## Trades known to the shader's interior palettes (index = custom.y).
const TRADES := ["bakery", "cafe", "pharmacy", "electronics", "optician", "books", "florist", "hardware",
	"barber", "jeweller", "deli", "newsagent", "laundry", "estate", "bank", "homeware", "clothing",
	"restaurant", "grocer", "sport", "sweets", "travel", "gallery", "fish"]
## Shopfront paint (instance colour): heritage greens, blues, reds, black, cream…
const PAINTS := [Color(0.08, 0.2, 0.15), Color(0.1, 0.13, 0.22), Color(0.36, 0.08, 0.07), Color(0.06, 0.06, 0.07),
	Color(0.82, 0.79, 0.7), Color(0.18, 0.22, 0.25), Color(0.32, 0.24, 0.16), Color(0.5, 0.52, 0.5),
	Color(0.09, 0.25, 0.33), Color(0.55, 0.12, 0.2)]

static var _mesh := {}
static var _mat: ShaderMaterial
static var _brand_trades: PackedInt32Array


static func _material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		if ResourceLoader.exists(ATLAS):
			_mat.set_shader_parameter("atlas", load(ATLAS))
	return _mat


static func brand_trades() -> PackedInt32Array:
	if _brand_trades.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BRANDS))
		if parsed is Dictionary:
			for b in (parsed as Dictionary).get("brands", []):
				_brand_trades.append(maxi(0, TRADES.find(String(b.get("trade", "")))))
		if _brand_trades.is_empty():
			_brand_trades.append(0)
	return _brand_trades


# ------------------------------------------------------------ placement (pure data, worker thread)
## Every bay of decorative shopfront on these buildings:
## [[variant, Transform3D, paint Color, custom Color], ...] where variant is
## "bay0".."bay2", "blade", "aboard" or "planter".
static func bays_for(buildings: Array, layout: CityLayout = null) -> Array:
	var out: Array = []
	var trades := brand_trades()
	for b: Dictionary in buildings:
		if String(b.get("kind", "")) != "normal" or not BuildingMesher.ground_shops(b) or BuildingMesher.shaped(b):
			continue
		if int(b["style"]) == CityLayout.Style.WAREHOUSE:
			continue
		# An enterable ground floor (Premises) keeps its own stretch of the
		# frontage; the rest of the ground floor is still decorative shops.
		var unit: Dictionary = b.get("apt", {}) if b.get("apt", {}).get("ground", false) else {}
		var t: Array = b["tiers"][0]
		if float(t[5]) - float(t[4]) < 5.2 or not BuildingMesher._on_ground(b, t):
			continue
		var base := float(t[4])
		var avoid: Array[AABB] = []
		for bx: AABB in BuildingMesher.features(b)["col"]:
			if bx.position.y < base + 4.8:
				avoid.append(bx.grow(0.3))
		var bx := CityLayout.bxf(b)
		var seed := float(b["seed"])
		var rng := RandomNumberGenerator.new()
		rng.seed = int(seed * 7919.0) ^ 0x5f0
		var paint: Color = PAINTS[rng.randi() % PAINTS.size()]
		for side in 4:
			var face := BuildingMesher._face(t, side)
			var length: float = face[3]
			var origin: float = face[4]
			var first := ceili((origin + 0.01) / BAY)
			var last := floori((origin + length - 0.01) / BAY)
			for bay in range(first, last):
				var a0 := bay * BAY - origin
				if a0 < 0.05 or a0 + BAY > length - 0.05:
					continue
				var span := BuildingMesher._fbox(face, a0, a0 + BAY, 0.0, 0.6, base, base + 4.7)
				if avoid.any(func(o: AABB) -> bool: return o.intersects(span)):
					continue
				if not unit.is_empty() and int(unit.get("face", -1)) == side \
						and a0 < float(unit["a1"]) + 0.4 and a0 + BAY > float(unit["a0"]) - 0.4:
					continue
				var along: Vector3 = face[1]
				var outw: Vector3 = face[2]
				var xf := bx * Transform3D(Basis(along, Vector3.UP, outw), BuildingMesher._fpt(face, a0, 0.0, base))
				# On a slope the pavement in front can sit below the lot: a
				# stone plinth fills the drop (no floating shopfront).
				var drop := 0.0
				if layout:
					for ax: float in [0.5, BAY * 0.5, BAY - 0.5]:
						var fp := xf * Vector3(ax, 0.0, 0.8)
						drop = maxf(drop, xf.origin.y - layout.ground_y(fp.x, fp.z))
				if drop > 1.6:
					continue
				var brand := rng.randi() % trades.size()
				var s := rng.randf()
				var open := 1.0 if rng.randf() < 0.82 else 0.0
				# a shop now and then repaints its own front
				var col: Color = paint if rng.randf() < 0.7 else PAINTS[rng.randi() % PAINTS.size()]
				var custom := Color(float(brand) / 255.0, float(trades[brand]) / 255.0, s, open)
				out.append(["bay%d" % (rng.randi() % 3), xf, col, custom])
				if drop > 0.08:
					out.append(["plinth", xf * Transform3D(Basis.from_scale(Vector3(1.0, drop + 0.3, 1.0)), Vector3.ZERO), col, custom])
				if rng.randf() < 0.22:
					out.append(["blade", xf, col, custom])
				var r := rng.randf()
				if r < 0.28:
					out.append(["aboard", xf * Transform3D(Basis(), Vector3(rng.randf_range(1.0, BAY - 1.0), 0.0, rng.randf_range(1.1, 1.6))), col, custom])
				elif r < 0.42:
					for px: float in [0.75, BAY - 0.75]:
						out.append(["planter", xf * Transform3D(Basis(), Vector3(px, 0.0, 0.62)), col, custom])
	return out


# ------------------------------------------------------------ instancing (main thread)
## The modules under `root`, one MultiMesh per kind.
static func place(root: Node3D, list: Array) -> void:
	if list.is_empty():
		return
	# Grouped per kind and per 50 m cell: a visibility range is measured to
	# the centre of the whole MultiMesh, and a chunk is 200 m across.
	var by := {}
	for it: Array in list:
		var o: Vector3 = (it[1] as Transform3D).origin
		var key := [it[0], floori(o.x / CELL), floori(o.z / CELL)]
		if not by.has(key):
			by[key] = []
		by[key].append(it)
	for key: Array in by:
		var kind: String = key[0]
		var items: Array = by[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh(kind)
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][1])
			mm.set_instance_color(i, items[i][2])
			mm.set_instance_custom_data(i, items[i][3])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Shopfronts_" + kind
		mi.multimesh = mm
		var prop := kind in ["aboard", "planter"]
		mi.visibility_range_end = PROP_RANGE if prop else RANGE
		mi.visibility_range_end_margin = 10.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if prop else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)


# ------------------------------------------------------------ meshes (built once)
## Vertex colour = the part: rgb its own colour (or white = take the paint),
## a = material (0 paint, 0.25 dark metal, 0.5 stone/tile, 0.75 timber/rubber).
## UV2.x = surface kind for the shader: 0 frame, 1 window glass, 2 sign board,
## 3 door glass, 4 threshold tiles.
static func mesh(kind: String) -> ArrayMesh:
	if _mesh.has(kind):
		return _mesh[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"bay0":
			_bay(st, BAY * 0.5)
		"bay1":
			_bay(st, 1.35)
		"bay2":
			_bay(st, BAY - 1.35)
		"blade":
			_blade(st)
		"aboard":
			_aboard(st)
		"planter":
			_planter(st)
		"plinth":
			_box(st, 0.0, BAY, -1.0, 0.0, 0.0, 0.4, STONE)
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, _material())
	_mesh[kind] = m
	return m


## Material classes (UV2.y; the shader picks the colour, the instance colour
## is the paint): 0 paint, 0.1 soffit, 0.25 dark metal, 0.3 brass,
## 0.5 stone/tile, 0.6 leaves, 0.75 timber.
const PAINT := 0.0
const SOFFIT := 0.1
const METAL := 0.25
const BRASS := 0.3
const STONE := 0.5
const LEAF := 0.6
const TIMBER := 0.75


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, mat: float, surf: float,
		uv0 := Vector2(0, 1), uv1 := Vector2(1, 1), uv2 := Vector2(1, 0), uv3 := Vector2(0, 0), normal := Vector3.ZERO) -> void:
	var n := normal if normal != Vector3.ZERO else (b - a).cross(c - a).normalized()
	for p in [[a, uv0], [b, uv1], [c, uv2], [a, uv0], [c, uv2], [d, uv3]]:
		st.set_normal(n)
		st.set_color(Color.WHITE)
		st.set_uv(p[1])
		st.set_uv2(Vector2(surf, mat))
		st.add_vertex(p[0])


## An axis box in module space (x along, y up, z out), outward normals
## (the material draws both sides: winding doesn't matter).
static func _box(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: float, back := false) -> void:
	var p := [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0),
		Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
	var ux := func(v: Vector3) -> Vector2: return Vector2(v.x, -v.y)
	var uz := func(v: Vector3) -> Vector2: return Vector2(v.z, -v.y)
	var uy := func(v: Vector3) -> Vector2: return Vector2(v.x, v.z)
	_quad(st, p[4], p[5], p[6], p[7], mat, 0.0, ux.call(p[4]), ux.call(p[5]), ux.call(p[6]), ux.call(p[7]), Vector3.BACK)
	_quad(st, p[1], p[5], p[6], p[2], mat, 0.0, uz.call(p[1]), uz.call(p[5]), uz.call(p[6]), uz.call(p[2]), Vector3.RIGHT)
	_quad(st, p[4], p[0], p[3], p[7], mat, 0.0, uz.call(p[4]), uz.call(p[0]), uz.call(p[3]), uz.call(p[7]), Vector3.LEFT)
	_quad(st, p[3], p[2], p[6], p[7], mat, 0.0, uy.call(p[3]), uy.call(p[2]), uy.call(p[6]), uy.call(p[7]), Vector3.UP)
	_quad(st, p[4], p[5], p[1], p[0], mat, 0.0, uy.call(p[4]), uy.call(p[5]), uy.call(p[1]), uy.call(p[0]), Vector3.DOWN)
	if back:
		_quad(st, p[1], p[0], p[3], p[2], mat, 0.0, ux.call(p[1]), ux.call(p[0]), ux.call(p[3]), ux.call(p[2]), Vector3.FORWARD)


## One 6 m bay with its door centred at x = door.
static func _bay(st: SurfaceTool, door: float) -> void:
	var dl := door - DOOR_W * 0.5
	var dr := door + DOOR_W * 0.5
	var g := GLASS_Z
	# Piers (half each end; neighbours complete them), sunk 0.25 m into the pavement.
	for px: Array in [[0.0, PIER], [BAY - PIER, BAY]]:
		_box(st, px[0], px[1], -0.25, 4.62, 0.0, 0.34, PAINT)
		# pier base block and capital
		_box(st, px[0], px[1], -0.25, 0.42, 0.0, 0.38, STONE)
		_box(st, px[0] + (0.0 if px[0] > 1.0 else 0.0), px[1], 3.42, 3.56, 0.0, 0.4, PAINT)
		# corbel under the cornice ends
		_box(st, px[0] + 0.03, px[1] - 0.03, 3.62, 4.46, 0.32, 0.46, PAINT)
	# Fascia: backing, sign board face (surface 2), mouldings, cornice.
	_box(st, PIER, BAY - PIER, 3.56, 4.52, 0.0, 0.3, PAINT)
	_quad(st, Vector3(PIER + 0.08, 3.64, 0.302), Vector3(BAY - PIER - 0.08, 3.64, 0.302),
		Vector3(BAY - PIER - 0.08, 4.44, 0.302), Vector3(PIER + 0.08, 4.44, 0.302), PAINT, 2.0,
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	_box(st, 0.0, BAY, 4.52, 4.6, 0.0, 0.4, PAINT)          # cornice bed
	_box(st, 0.0, BAY, 4.6, 4.7, 0.0, 0.46, PAINT)          # cornice cap
	_box(st, PIER, BAY - PIER, 3.5, 3.58, 0.0, 0.33, PAINT)  # fascia bed moulding
	# Windows either side of the door (or one side if the door's at an end).
	for run in [[PIER, dl - 0.06], [dr + 0.06, BAY - PIER]]:
		var x0: float = run[0]
		var x1: float = run[1]
		if x1 - x0 < 0.3:
			continue
		_box(st, x0, x1, -0.25, 0.56, 0.0, g + 0.02, PAINT)          # stall riser (panelled)
		_box(st, x0 + 0.08, x1 - 0.08, 0.14, 0.46, g + 0.02, g + 0.04, PAINT)   # riser panel
		_box(st, x0, x1, 0.56, 0.64, 0.0, g + 0.08, STONE)           # sill
		_box(st, x0, x1, 2.88, 2.98, 0.0, g + 0.04, PAINT)           # transom rail
		_box(st, x0, x1, 3.4, 3.5, 0.0, g + 0.03, PAINT)             # head
		# window glass (surface 1) and the transom lights above
		_quad(st, Vector3(x0, 0.64, g), Vector3(x1, 0.64, g), Vector3(x1, 2.88, g), Vector3(x0, 2.88, g),
			PAINT, 1.0, Vector2(x0, 0.64), Vector2(x1, 0.64), Vector2(x1, 2.88), Vector2(x0, 2.88))
		_quad(st, Vector3(x0, 2.98, g), Vector3(x1, 2.98, g), Vector3(x1, 3.4, g), Vector3(x0, 3.4, g),
			PAINT, 1.0, Vector2(x0, 2.98), Vector2(x1, 2.98), Vector2(x1, 3.4), Vector2(x0, 3.4))
		# mullions: thirds of the run, transom bars over them
		var n := maxi(1, int(round((x1 - x0) / 1.25)))
		for k in range(1, n):
			var mx := x0 + (x1 - x0) * float(k) / float(n)
			_box(st, mx - 0.03, mx + 0.03, 0.64, 2.88, g - 0.01, g + 0.05, PAINT)
			_box(st, mx - 0.025, mx + 0.025, 2.98, 3.4, g - 0.01, g + 0.05, PAINT)
		# side posts of the window run
		_box(st, x0, x0 + 0.06, 0.56, 3.4, 0.0, g + 0.06, PAINT)
		_box(st, x1 - 0.06, x1, 0.56, 3.4, 0.0, g + 0.06, PAINT)
	# The recessed entrance: glazed returns from the window line back to the
	# door at the wall, soffit, tiled threshold, door and fanlight.
	for sx: float in [dl - 0.06, dr]:
		_box(st, sx, sx + 0.06, -0.02, 2.62, 0.0, g + 0.06, PAINT)   # door-side posts
	for edge: float in [dl - 0.06, dr + 0.06]:
		var e: float = edge
		_quad(st, Vector3(e, 0.64, g), Vector3(e, 0.64, 0.02), Vector3(e, 2.62, 0.02), Vector3(e, 2.62, g),
			PAINT, 1.0, Vector2(g, 0.64), Vector2(0.0, 0.64), Vector2(0.0, 2.62), Vector2(g, 2.62))
	_box(st, dl - 0.06, dr + 0.06, 2.62, 2.88, 0.0, g + 0.04, PAINT)   # door head / fanlight rail
	_quad(st, Vector3(dl, 2.66, 0.04), Vector3(dr, 2.66, 0.04), Vector3(dr, 2.86, 0.04), Vector3(dl, 2.86, 0.04),
		PAINT, 1.0, Vector2(dl, 2.66), Vector2(dr, 2.66), Vector2(dr, 2.86), Vector2(dl, 2.86))
	_quad(st, Vector3(dl - 0.06, 2.6, g), Vector3(dr + 0.06, 2.6, g), Vector3(dr + 0.06, 2.6, 0.0), Vector3(dl - 0.06, 2.6, 0.0),
		SOFFIT, 0.0)   # soffit (facing down)
	_quad(st, Vector3(dl - 0.06, 0.012, 0.0), Vector3(dr + 0.06, 0.012, 0.0), Vector3(dr + 0.06, 0.012, g + 0.06), Vector3(dl - 0.06, 0.012, g + 0.06),
		STONE, 4.0, Vector2(dl, 0.0), Vector2(dr, 0.0), Vector2(dr, g), Vector2(dl, g))   # threshold tiles
	_box(st, dl - 0.06, dr + 0.06, -0.25, 0.012, 0.0, g + 0.08, STONE)   # step under them
	# door: frame, kick plate, glazed panel, push bar
	_box(st, dl, dr, 0.012, 0.32, 0.02, 0.07, PAINT)
	_box(st, dl, dl + 0.09, 0.012, 2.6, 0.02, 0.07, PAINT)
	_box(st, dr - 0.09, dr, 0.012, 2.6, 0.02, 0.07, PAINT)
	_box(st, dl, dr, 2.5, 2.6, 0.02, 0.07, PAINT)
	_quad(st, Vector3(dl + 0.09, 0.32, 0.045), Vector3(dr - 0.09, 0.32, 0.045), Vector3(dr - 0.09, 2.5, 0.045), Vector3(dl + 0.09, 2.5, 0.045),
		PAINT, 3.0, Vector2(dl, 0.32), Vector2(dr, 0.32), Vector2(dr, 2.5), Vector2(dl, 2.5))
	_box(st, dl + 0.14, dr - 0.14, 1.0, 1.05, 0.07, 0.1, BRASS)
	_box(st, dl + 0.12, dr - 0.12, 0.012, 0.3, 0.07, 0.075, BRASS)    # kick plate


## A projecting hanging sign on the left pier: bracket + double-sided board.
static func _blade(st: SurfaceTool) -> void:
	var x := 0.11
	_box(st, x - 0.02, x + 0.02, 3.3, 3.34, 0.3, 1.05, METAL)       # bracket arm
	_box(st, x - 0.02, x + 0.02, 2.95, 3.34, 0.32, 0.36, METAL)     # wall plate
	_box(st, x - 0.04, x + 0.04, 2.6, 3.24, 0.42, 1.02, PAINT)      # board edge
	for sd: float in [-1.0, 1.0]:
		var xx := x + 0.041 * sd
		var a := Vector3(xx, 2.66, 0.46)
		var b := Vector3(xx, 2.66, 0.98)
		var c := Vector3(xx, 3.18, 0.98)
		var d := Vector3(xx, 3.18, 0.46)
		if sd < 0.0:
			_quad(st, b, a, d, c, PAINT, 2.0, Vector2(0.3, 1), Vector2(0.7, 1), Vector2(0.7, 0), Vector2(0.3, 0))
		else:
			_quad(st, a, b, c, d, PAINT, 2.0, Vector2(0.3, 1), Vector2(0.7, 1), Vector2(0.7, 0), Vector2(0.3, 0))


## A pavement sandwich board (its two faces carry the brand), facing the street.
static func _aboard(st: SurfaceTool) -> void:
	var h := 0.95
	for sd: float in [-1.0, 1.0]:
		var zb := 0.24 * sd
		var a := Vector3(-0.32, 0.0, zb)
		var b := Vector3(0.32, 0.0, zb)
		var c := Vector3(0.32, h, 0.02 * sd)
		var d := Vector3(-0.32, h, 0.02 * sd)
		if sd > 0.0:
			_quad(st, a, b, c, d, PAINT, 2.0, Vector2(0.38, 1), Vector2(0.62, 1), Vector2(0.62, 0), Vector2(0.38, 0))
		else:
			_quad(st, b, a, d, c, PAINT, 2.0, Vector2(0.38, 1), Vector2(0.62, 1), Vector2(0.62, 0), Vector2(0.38, 0))
	_box(st, -0.34, 0.34, h - 0.03, h + 0.02, -0.04, 0.04, PAINT)


## A timber planter with a clipped box shrub.
static func _planter(st: SurfaceTool) -> void:
	_box(st, -0.36, 0.36, 0.0, 0.5, -0.28, 0.28, TIMBER)
	_box(st, -0.39, 0.39, 0.5, 0.56, -0.31, 0.31, TIMBER)
	_box(st, -0.3, 0.3, 0.56, 0.98, -0.22, 0.22, LEAF)
	_box(st, -0.24, 0.24, 0.98, 1.12, -0.17, 0.17, LEAF)
