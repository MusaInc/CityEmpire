class_name ShopInterior
extends Node3D
## The inside of a shop unit (or a wholesale warehouse) cut into a city
## building by Premises. Lives in the unit's room frame (Premises.room_xf):
## x along the shopfront (0..W), y up, z out of the facade (the room is
## z = -depth..0); authoring below uses depth d = -z.
##
##  * Shell: floor (shader planes), walls, ceiling with light panels, glass
##    shopfront with a door gap, fascia sign outside, back-room partition.
##  * Fixtures come from the Business: shelf bays, drinks fridges, coffee
##    machine, pick & mix wall, tills. Their slots show the goods actually on
##    them (one MultiMesh per pack shape for the whole shop) with a shelf-edge
##    price tag, so a gap on the shelf is a real stockout.
##  * Back room: racking that shows the cases in stock, an office desk.
##  * Gameplay data for the floor: interaction points (`spots`), a walk grid
##    (`walkable`), till/queue positions and each slot's pick point.
## Collision boxes go on the human layer only.

const BAY := 1.9          # shelf bay width (m)
const SHELF_D := 0.55
const FRIDGE_D := 0.72
const BACKROOM := 3.0
const CELL := 0.4         # walk grid
const LEVELS := [0.28, 0.82, 1.36]
const FRIDGE_LEVELS := [0.3, 0.72, 1.14, 1.56]

var unit: Dictionary
var biz: Business
var kind := "shop"        # "shop" | "wholesale"
var W := 10.0
var H := 4.2
var D := 10.0
var ox := Vector2(2.0, 8.0)  # shopfront opening (x)
var door := Vector2(4.1, 5.9)  # door gap (x)

## Placed fixtures: [{kind, unit, origin (room Vector3), facing (room Vector3, the side shoppers stand), slots: [slot idx]}]
var placed: Array = []
## Interaction points (room coords): [{kind, pos, slot?, label}]
var spots: Array = []
var slot_pick := {}       # slot index -> room position a shopper stands to take from it
var slot_box := {}        # slot index -> [origin, along, out, width, y] for drawing goods
var till_customer: Array = []  # room positions
var till_staff: Array = []
var queue: Array = []
var door_in := Vector3.ZERO
var door_out := Vector3.ZERO
var rack_pos := Vector3.ZERO
var office_pos := Vector3.ZERO
var walk := {}            # Vector2i cell -> true when free

var _static: Node3D
var _goods: Node3D
var _labels: Node3D
var _dirt: MeshInstance3D
var _sign: Label3D
var _sign_light: OmniLight3D
var _open_sign: Label3D
var _col: StaticBody3D
var _cases_mm: MultiMeshInstance3D
static var _mat_cache := {}
static var _shape_meshes := {}


## Metres the room sits above its unit's floor level (the terrain under some
## lots comes up to a kerb's height over it): set by the game from the ground.
var lift := 0.0


func setup(p_unit: Dictionary, p_biz: Business, ground_fn := Callable()) -> void:
	unit = p_unit
	biz = p_biz
	kind = String(unit.get("kind", "shop"))
	var sz := Premises.room_size(unit)
	W = sz.x
	H = sz.y
	D = sz.z
	ox = Premises.opening_x(unit)
	var mid := (ox.x + ox.y) * 0.5
	door = Vector2(mid - 0.95, mid + 0.95) if kind == "shop" else ox
	transform = Premises.room_xf(unit)
	if ground_fn.is_valid():
		var hi := -INF
		for fx in 5:
			for fz in 5:
				var p := transform * Vector3(W * (fx + 0.5) / 5.0, 0, -D * (fz + 0.5) / 5.0)
				hi = maxf(hi, float(ground_fn.call(p.x, p.z)) - p.y)
		lift = clampf(hi + 0.03, 0.0, 0.3)
	# A building on a slope stands on a stone base course whose top (drawn and
	# collided) is a kerb above the lot level: the shop floor sits on it.
	var bc := BuildingMesher.base_course(unit["b"])
	if bc.has_volume():
		lift = maxf(lift, bc.end.y - float(unit["y0"]) + 0.02)
	transform.origin.y += lift
	name = "Interior_" + String(unit.get("id", "unit"))
	rebuild()


## Room coords (x, depth, y) → local node coords.
static func R(x: float, d: float, y: float) -> Vector3:
	return Vector3(x, y, -d)


func to_world(p: Vector3) -> Vector3:
	return global_transform * p if is_inside_tree() else transform * p


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	placed.clear()
	spots.clear()
	slot_pick.clear()
	slot_box.clear()
	till_customer.clear()
	till_staff.clear()
	queue.clear()
	_static = Node3D.new()
	_static.name = "Static"
	add_child(_static)
	_goods = Node3D.new()
	_goods.name = "Goods"
	add_child(_goods)
	_labels = Node3D.new()
	_labels.name = "Labels"
	add_child(_labels)
	_col = StaticBody3D.new()
	_col.name = "Collision"
	_col.collision_layer = CityWorld.HUMAN_LAYER | 1
	_col.collision_mask = 0
	add_child(_col)
	var st := _Batch.new()
	if kind == "wholesale":
		_build_warehouse(st)
	else:
		_build_shop(st)
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	mi.mesh = st.commit()
	mi.material_override = _mat("vc")
	mi.visibility_range_end = 260.0
	_static.add_child(mi)
	if _glow != null:
		var gi := MeshInstance3D.new()
		gi.name = "Glow"
		gi.mesh = _glow.commit()
		gi.material_override = _mat("glow")
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_static.add_child(gi)
		_glow = null
	_build_walk_grid()
	refresh_goods()


# ------------------------------------------------------------- shop
func _build_shop(st: _Batch) -> void:
	var wall := Color(0.86, 0.85, 0.8)
	var trim := Color(0.18, 0.2, 0.22)
	var floor_style := 1 if biz and biz.has_upgrade("floor") else 0
	_floor(Color(0.86, 0.85, 0.82) if floor_style == 1 else Color(0.72, 0.7, 0.66), floor_style)
	_shell(st, wall, trim)
	var part_d := D - BACKROOM
	# Back-room partition with a doorway on the right.
	var dw0 := W - 2.1
	var dw1 := W - 0.95
	_wall_box(st, 0.0, dw0, part_d, part_d + 0.14, 0.0, H, wall.darkened(0.04))
	_wall_box(st, dw1, W, part_d, part_d + 0.14, 0.0, H, wall.darkened(0.04))
	_wall_box(st, dw0, dw1, part_d, part_d + 0.14, 2.3, H, wall.darkened(0.04))
	st.box(R(dw0 - 0.06, part_d - 0.02, 0.0), R(dw1 + 0.06, part_d + 0.16, 2.36), trim)  # door frame (drawn)
	# Shopfront: glass either side of the door, frame, fascia.
	_shopfront(st, trim)
	# Counter + tills on the right.
	var tills := biz.tills() if biz else 1
	var cx0 := W - 2.45
	var cx1 := W - 1.75
	var cd0 := 1.3
	var cd1 := 1.3 + 1.25 * tills + 0.4
	st.box(R(cx0, cd0, 0.0), R(cx1, cd1, 0.98), Color(0.32, 0.22, 0.15))
	st.box(R(cx0 - 0.05, cd0 - 0.05, 0.98), R(cx1 + 0.05, cd1 + 0.05, 1.04), Color(0.9, 0.89, 0.86))
	_solid(R(cx0, cd0, 0.0), R(cx1, cd1, 1.04))
	for i in tills:
		var td := cd0 + 0.6 + 1.25 * i
		st.box(R(cx0 + 0.15, td - 0.22, 1.04), R(cx0 + 0.55, td + 0.22, 1.12), Color(0.12, 0.12, 0.13))  # register base
		st.box(R(cx0 + 0.28, td - 0.18, 1.12), R(cx0 + 0.32, td + 0.18, 1.42), Color(0.08, 0.09, 0.1))   # screen
		_glow_quad(R(cx0 + 0.27, td - 0.15, 1.15), R(cx0 + 0.27, td + 0.15, 1.39), Color(0.35, 0.8, 0.9))
		till_customer.append(R(cx0 - 0.55, td, 0.0))
		till_staff.append(R(cx1 + 0.55, td, 0.0))
		spots.append({"kind": "till", "pos": R(cx1 + 0.55, td, 0.0), "till": i, "label": "SERVE"})
	# Queue: back from the first till along the counter.
	for k in 6:
		queue.append(R(cx0 - 0.55, cd1 + 0.5 + 0.8 * k, 0.0))
	# Cigarette-style back display behind the counter (decor) + till staff area.
	st.box(R(W - 0.4, cd0, 0.9), R(W - 0.05, cd1, 2.2), Color(0.25, 0.27, 0.3))
	# Fixtures.
	_place_fixtures(st, part_d)
	# Back room: racking, office desk, mop.
	_backroom(st, part_d, dw0, dw1)
	door_in = R((door.x + door.y) * 0.5, 0.9, 0.0)
	door_out = R((door.x + door.y) * 0.5, -1.6, 0.0)
	spots.append({"kind": "door", "pos": R((door.x + door.y) * 0.5, 0.55, 0.0), "label": "OPEN / CLOSE"})
	# Ceiling lights.
	var bright := 1.25 if biz and biz.has_upgrade("lighting") else 0.85
	var tint := Color(1.0, 0.95, 0.86) if biz and biz.has_upgrade("lighting") else Color(0.92, 0.95, 1.0)
	for ix in 2:
		for iz in 2:
			var px := W * (0.28 + 0.44 * ix)
			var pd := part_d * (0.28 + 0.44 * iz)
			_glow_quad(R(px - 0.6, pd - 0.25, H - 0.02), R(px + 0.6, pd + 0.25, H - 0.02), tint * 1.4, true)
	_light(R(W * 0.35, part_d * 0.4, H - 0.4), tint, bright, maxf(W, D) * 0.9)
	_light(R(W * 0.68, part_d * 0.7, H - 0.4), tint, bright, maxf(W, D) * 0.9)
	_light(R(W * 0.5, D - 1.5, H - 0.4), Color(1.0, 0.9, 0.75), 0.5, 5.0)
	# Dirt: a floor decal that shows as the shop gets messy.
	_dirt = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W - 1.0, part_d - 1.0)
	_dirt.mesh = pm
	_dirt.material_override = _dirt_mat()
	_dirt.position = R(W * 0.5, part_d * 0.5, 0.025)
	_dirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_static.add_child(_dirt)
	spots.append({"kind": "clean", "pos": R(W * 0.4, part_d * 0.55, 0.0), "label": "CLEAN"})


func _shell(st: _Batch, wall: Color, trim: Color) -> void:
	# Side and back walls (inner faces), ceiling.
	_wall_box(st, -0.05, 0.02, 0.0, D, 0.0, H, wall)
	_wall_box(st, W - 0.02, W + 0.05, 0.0, D, 0.0, H, wall)
	_wall_box(st, 0.0, W, D - 0.02, D + 0.05, 0.0, H, wall.darkened(0.06))
	st.box(R(0.0, 0.0, H - 0.01), R(W, D, H + 0.05), Color(0.93, 0.93, 0.92))
	# Skirting.
	st.box(R(0.02, 0.0, 0.0), R(0.05, D, 0.12), trim)
	st.box(R(W - 0.05, 0.0, 0.0), R(W - 0.02, D, 0.12), trim)
	# Inner face of the front wall round the opening (0.3 m thick wall).
	var oh: float = float(unit["oy1"]) - float(unit["oy0"])
	_wall_box(st, 0.0, ox.x, 0.0, 0.3, 0.0, H, wall)
	_wall_box(st, ox.y, W, 0.0, 0.3, 0.0, H, wall)
	_wall_box(st, ox.x, ox.y, 0.0, 0.3, oh, H, wall)


func _shopfront(st: _Batch, trim: Color) -> void:
	var oh: float = float(unit["oy1"]) - float(unit["oy0"])
	var gd := 0.12  # glass line, just inside the facade
	# Frame: posts at the opening edges and the door, transom bar.
	for x: float in [ox.x, door.x, door.y, ox.y]:
		st.box(R(x - 0.05, gd - 0.06, 0.0), R(x + 0.05, gd + 0.06, oh), trim)
	st.box(R(ox.x, gd - 0.06, oh - 0.12), R(ox.y, gd + 0.06, oh), trim)
	st.box(R(ox.x, gd - 0.06, 0.0), R(door.x, gd + 0.06, 0.35), trim)  # stall risers
	st.box(R(door.y, gd - 0.06, 0.0), R(ox.y, gd + 0.06, 0.35), trim)
	_solid(R(ox.x, gd - 0.08, 0.0), R(door.x, gd + 0.08, oh))
	_solid(R(door.y, gd - 0.08, 0.0), R(ox.y, gd + 0.08, oh))
	# Glass panes (one transparent mesh).
	var gm := _Batch.new()
	gm.box(R(ox.x + 0.05, gd - 0.01, 0.35), R(door.x - 0.05, gd + 0.01, oh - 0.12), Color(0.6, 0.75, 0.8, 0.22))
	gm.box(R(door.y + 0.05, gd - 0.01, 0.35), R(ox.y - 0.05, gd + 0.01, oh - 0.12), Color(0.6, 0.75, 0.8, 0.22))
	var gi := MeshInstance3D.new()
	gi.mesh = gm.commit()
	gi.material_override = _mat("glass")
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_static.add_child(gi)
	# Fascia outside above the opening, with the shop's name.
	var fy := oh + 0.15
	st.box(R(ox.x - 0.3, -0.32, fy), R(ox.y + 0.3, -0.02, fy + 0.75), Color(0.1, 0.12, 0.16))
	_sign = Label3D.new()
	_sign.text = _sign_text()
	_sign.font_size = 96
	_sign.pixel_size = 0.0045
	_sign.outline_size = 0
	_sign.modulate = Color(1.0, 0.92, 0.7)
	_sign.position = R((ox.x + ox.y) * 0.5, -0.335, fy + 0.38)
	_sign.rotation.y = 0.0  # faces +z (out to the street)
	_sign.double_sided = false
	_sign.shaded = false
	_sign.width = (ox.y - ox.x) / 0.0045
	_sign.autowrap_mode = TextServer.AUTOWRAP_OFF
	_static.add_child(_sign)
	var lit := biz != null and biz.has_upgrade("signage")
	if lit:
		_sign_light = OmniLight3D.new()
		_sign_light.position = R((ox.x + ox.y) * 0.5, -1.0, fy + 0.4)
		_sign_light.light_color = Color(1.0, 0.85, 0.6)
		_sign_light.light_energy = 1.2
		_sign_light.omni_range = 5.0
		_static.add_child(_sign_light)
		_sign.modulate = Color(1.4, 1.2, 0.8)
	# OPEN / CLOSED / TO LET card in the door glass.
	_open_sign = Label3D.new()
	_open_sign.font_size = 64
	_open_sign.pixel_size = 0.004
	_open_sign.position = R(door.x - 0.5, gd - 0.03, 1.5)
	_open_sign.shaded = false
	_static.add_child(_open_sign)
	update_signs(false)


func _sign_text() -> String:
	if biz:
		return biz.name.to_upper()
	return "TO LET" if kind == "shop" else String(unit.get("name", "")).to_upper()


func update_signs(trading: bool) -> void:
	if _sign:
		_sign.text = _sign_text()
	if _open_sign:
		if biz == null:
			_open_sign.text = "TO LET\n%s / day" % EmpireData.money(float(unit.get("rent", 0)))
			_open_sign.modulate = Color(1.0, 0.85, 0.3)
		else:
			_open_sign.text = "OPEN" if trading else "CLOSED"
			_open_sign.modulate = Color(0.4, 1.0, 0.55) if trading else Color(1.0, 0.4, 0.35)


## Fixture positions in fill order: the back wall (fridges first), then the
## middle gondola's two sides, then the left wall.
func _fixture_sites(part_d: float) -> Array:
	var sites: Array = []
	var x := 0.35
	while x + BAY <= W - 2.6:
		sites.append({"back": R(x, part_d - 0.02, 0.0), "along": Vector3.RIGHT, "out": Vector3(0, 0, 1), "wall": "back"})
		x += BAY + 0.05
	var gx0 := 1.95
	var gx1 := W - 3.7
	if gx1 - gx0 >= 1.15:
		var gc := (gx0 + gx1) * 0.5
		var d := 2.2
		while d + BAY <= part_d - 1.5:
			# (+x side faces right, −x side faces left; both run front→back)
			sites.append({"back": R(gc + 0.02, d + BAY, 0.0), "along": Vector3(0, 0, 1), "out": Vector3.RIGHT, "wall": "gondola"})
			sites.append({"back": R(gc - 0.02, d, 0.0), "along": Vector3(0, 0, -1), "out": Vector3.LEFT, "wall": "gondola"})
			d += BAY + 0.05
	var d2 := 1.3
	while d2 + BAY <= part_d - 0.9:
		sites.append({"back": R(0.05, d2 + BAY, 0.0), "along": Vector3(0, 0, 1), "out": Vector3.RIGHT, "wall": "left"})
		d2 += BAY + 0.05
	return sites


func _place_fixtures(st: _Batch, part_d: float) -> void:
	if biz == null:
		return
	var sites := _fixture_sites(part_d)
	var want: Array = []
	for k in ["fridge", "coffee", "pickmix", "shelf"]:
		for u in int(biz.fixtures.get(k, 0)):
			want.append([k, u])
	var back_sites := sites.filter(func(s): return s["wall"] == "back")
	var other_sites := sites.filter(func(s): return s["wall"] != "back")
	for w in want:
		var site: Dictionary
		if (w[0] == "fridge" or w[0] == "coffee") and not back_sites.is_empty():
			site = back_sites.pop_front()
		elif not other_sites.is_empty():
			site = other_sites.pop_front()
		elif not back_sites.is_empty():
			site = back_sites.pop_front()
		else:
			push_warning("ShopInterior: no room for a %s in %s" % [w[0], unit.get("id")])
			continue
		_fixture(st, String(w[0]), int(w[1]), site)


func _fixture(st: _Batch, k: String, u: int, site: Dictionary) -> void:
	var al: Vector3 = site["along"]
	var out: Vector3 = site["out"]
	var dep := FRIDGE_D if k == "fridge" else (0.75 if k == "pickmix" else SHELF_D)
	var o: Vector3 = (site["back"] as Vector3) + out * dep  # the front edge (shoppers' side)
	var tall := 2.05 if k == "fridge" else 1.85
	# Footprint: from o along BAY, from o back (−out) by dep.
	var a := o
	var b := o + al * BAY - out * dep
	var lo := a.min(b)
	var hi := a.max(b)
	var body_col := Color(0.2, 0.22, 0.25)
	match k:
		"fridge":
			st.box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, tall, hi.z), Color(0.82, 0.84, 0.86))
			# Dark lit interior on the open (front) side, top light strip.
			var f0 := o + out * 0.005
			var f1 := o + al * BAY + out * 0.005
			_glow_quad_v(f0 + Vector3.UP * 0.12, f1 + Vector3.UP * (tall - 0.18), out, Color(0.55, 0.62, 0.7) * 0.35)
			_glow_quad_v(f0 + Vector3.UP * (tall - 0.16), f1 + Vector3.UP * (tall - 0.06), out, Color(0.9, 0.95, 1.0) * 1.3)
		"coffee":
			st.box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, 0.95, hi.z), Color(0.28, 0.18, 0.12))
			var m0 := o + al * 0.5 - out * 0.45
			st.box(m0 + Vector3(-0.3, 0.95, -0.3).abs() * 0.0 + Vector3(0, 0.95, 0), m0 + al * 0.9 + out * 0.3 + Vector3(0, 1.65, 0), Color(0.1, 0.1, 0.11))
			_glow_quad_v(o + al * 0.6 + Vector3.UP * 1.35, o + al * 1.2 + Vector3.UP * 1.55, out, Color(1.0, 0.6, 0.25))
		"pickmix":
			st.box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, 0.9, hi.z), Color(0.95, 0.5, 0.7))
			for i in 6:
				var c := o + al * (0.18 + 0.3 * i) - out * 0.35 + Vector3.UP * 0.9
				st.box(c - Vector3(0.12, 0.0, 0.12), c + Vector3(0.12, 0.35, 0.12), Color(0.85, 0.92, 0.95))
		_:
			# Shelf bay: back panel, base, uprights and three shelf boards.
			var back0 := o - out * dep
			st.box((back0).min(back0 + al * BAY - out * 0.04) , (back0 + al * BAY - out * 0.04).max(back0) + Vector3.UP * tall, body_col)
			st.box(lo, Vector3(hi.x, 0.12, hi.z), body_col)
			for y: float in LEVELS:
				var s0 := o + Vector3.UP * (y - 0.03)
				var s1 := o + al * BAY - out * dep + Vector3.UP * y
				st.box(s0.min(s1), s0.max(s1), Color(0.78, 0.78, 0.76))
			for e: float in [0.0, BAY]:
				var p0 := o + al * e - out * dep
				var p1 := o + al * e + Vector3.UP * tall
				st.box(p0.min(p1) - Vector3(0.025, 0, 0.025) * al.abs(), p0.max(p1) + Vector3(0.025, 0, 0.025) * al.abs(), body_col)
			# Category header board.
			st.box(back0 + Vector3.UP * (tall - 0.02) + out * 0.02, back0 + al * BAY + out * 0.06 + Vector3.UP * (tall + 0.22), Color(0.15, 0.4, 0.3))
	_solid(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, tall, hi.z))
	placed.append({"kind": k, "unit": u, "origin": o, "along": al, "out": out})
	# Slots of this fixture.
	var idx: Array = []
	for i in biz.slots.size():
		var s: Dictionary = biz.slots[i]
		if s["fixture"] == k and int(s["unit"]) == u:
			idx.append(i)
	for j in idx.size():
		var si: int = idx[j]
		var a0 := 0.0
		var wdt := BAY
		var y := 0.95
		match k:
			"shelf":
				a0 = 0.05 + (j % 2) * (BAY * 0.5)
				wdt = BAY * 0.5 - 0.1
				y = LEVELS[j / 2] + 0.0
			"fridge":
				a0 = 0.08
				wdt = BAY - 0.16
				y = FRIDGE_LEVELS[j]
			"coffee":
				a0 = 0.05
				wdt = 0.5
				y = 0.95
			"pickmix":
				a0 = 0.1
				wdt = BAY - 0.2
				y = 0.9
		slot_box[si] = [o + al * a0 - out * 0.05, al, out, wdt, y, dep - 0.1]
		var pick := o + al * (a0 + wdt * 0.5) + out * 0.75
		pick.y = 0.0
		slot_pick[si] = pick
		spots.append({"kind": "slot", "slot": si, "pos": pick, "label": "SLOT"})
		var lab := Label3D.new()
		lab.font_size = 28
		lab.pixel_size = 0.0028
		lab.shaded = false
		lab.modulate = Color(0.1, 0.1, 0.1)
		lab.outline_size = 0
		# Tag on the shelf edge, facing the aisle.
		lab.position = o + al * (a0 + wdt * 0.5) + out * 0.02 + Vector3.UP * (y - 0.07)
		lab.basis = Basis.looking_at(-out, Vector3.UP)
		lab.set_meta("slot", si)
		_labels.add_child(lab)
		var tag := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(minf(wdt, 0.42), 0.075)
		tag.mesh = qm
		tag.material_override = _mat("tag")
		tag.position = lab.position - out * 0.004
		tag.basis = lab.basis
		_static.add_child(tag)


func _backroom(st: _Batch, part_d: float, dw0: float, dw1: float) -> void:
	# Racking along the back wall (cases drawn by refresh_goods).
	var r0 := 0.3
	var r1 := maxf(dw0 - 0.6, 2.5)
	var rd0 := D - 0.75
	var rd1 := D - 0.08
	for y: float in [0.1, 0.85, 1.6]:
		st.box(R(r0, rd0, y), R(r1, rd1, y + 0.05), Color(0.85, 0.45, 0.12))
	for x: float in [r0, (r0 + r1) * 0.5, r1]:
		st.box(R(x - 0.04, rd0, 0.0), R(x + 0.04, rd0 + 0.08, 2.3), Color(0.15, 0.3, 0.6))
		st.box(R(x - 0.04, rd1 - 0.08, 0.0), R(x + 0.04, rd1, 2.3), Color(0.15, 0.3, 0.6))
	_solid(R(r0, rd0, 0.0), R(r1, rd1, 2.3))
	rack_pos = R((r0 + r1) * 0.5, rd0 - 0.7, 0.0)
	spots.append({"kind": "rack", "pos": rack_pos, "label": "STOCKROOM"})
	slot_box[-1] = [R(r0, rd0, 0.0), Vector3.RIGHT, Vector3(0, 0, 1), r1 - r0, 0.0, 0.6]
	# Office desk on the right with a monitor.
	var dx0 := W - 1.6
	st.box(R(dx0, D - 1.3, 0.0), R(W - 0.1, D - 0.1, 0.76), Color(0.42, 0.3, 0.2))
	st.box(R(dx0 + 0.5, D - 0.6, 0.76), R(dx0 + 1.1, D - 0.55, 1.18), Color(0.05, 0.05, 0.06))
	_glow_quad(R(dx0 + 0.53, D - 0.62, 0.8), R(dx0 + 1.07, D - 0.62, 1.15), Color(0.3, 0.55, 0.9))
	_solid(R(dx0, D - 1.3, 0.0), R(W - 0.1, D - 0.1, 0.76))
	office_pos = R(dx0 + 0.8, D - 1.85, 0.0)
	spots.append({"kind": "office", "pos": office_pos, "label": "MANAGE"})


# --------------------------------------------------------- warehouse
func _build_warehouse(st: _Batch) -> void:
	_floor(Color(0.55, 0.55, 0.53), 2)
	_shell(st, Color(0.7, 0.71, 0.7), Color(0.2, 0.2, 0.22))
	# Pallet racking round three walls, full of cases (decor).
	var rack_c := Color(0.12, 0.3, 0.62)
	var beam_c := Color(0.95, 0.5, 0.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(unit.get("id", "w"))
	var cases := _Batch.new()
	var runs := [[R(0.1, 1.5, 0.0), Vector3(0, 0, -1), D - 2.5, Vector3.RIGHT],
		[R(W - 1.2, D - 1.0, 0.0), Vector3(0, 0, 1), D - 2.5, Vector3.LEFT],
		[R(1.5, D - 0.1, 0.0), Vector3.RIGHT, W - 3.0, Vector3(0, 0, 1)]]
	for run in runs:
		var o: Vector3 = run[0]
		var al: Vector3 = run[1]
		var L: float = run[2]
		var out: Vector3 = run[3]
		var dep := 1.1
		var a := 0.0
		while a + 2.6 <= L:
			for y: float in [0.0, 1.6, 3.2]:
				var p0 := o + al * a + Vector3.UP * (y + 0.12)
				var p1 := o + al * (a + 2.6) - out * 0.0 + out * dep + Vector3.UP * (y + 0.2)
				st.box(p0.min(p1), p0.max(p1), beam_c)
				# Cases on the beam.
				var n := rng.randi_range(2, 5)
				for i in n:
					var cc := Color.from_hsv(rng.randf(), 0.35, rng.randf_range(0.45, 0.8))
					var c0 := o + al * (a + 0.15 + i * 0.48) + out * 0.1 + Vector3.UP * (y + 0.2)
					var c1 := c0 + al * 0.42 + out * 0.8 + Vector3.UP * rng.randf_range(0.35, 0.6)
					cases.box(c0.min(c1), c0.max(c1), cc)
			for e: float in [a, a + 2.6]:
				var u0 := o + al * e
				var u1 := u0 + out * dep + Vector3.UP * minf(H - 0.3, 4.6)
				st.box(u0.min(u1) - Vector3(0.04, 0, 0.04), u0.max(u1) + Vector3(0.04, 0, 0.04), rack_c)
			var s0 := o + al * a
			var s1 := o + al * (a + 2.6) + out * dep + Vector3.UP * minf(H - 0.3, 4.6)
			_solid(s0.min(s1), s0.max(s1))
			a += 2.75
	_static.add_child(_mesh_of(cases, "vc"))
	# Trade counter facing the entrance.
	var tx := (ox.x + ox.y) * 0.5
	st.box(R(tx - 1.8, 4.2, 0.0), R(tx + 1.8, 4.9, 1.05), Color(0.25, 0.27, 0.3))
	st.box(R(tx - 1.85, 4.15, 1.05), R(tx + 1.85, 4.95, 1.1), Color(0.88, 0.88, 0.85))
	_solid(R(tx - 1.8, 4.2, 0.0), R(tx + 1.8, 4.9, 1.1))
	st.box(R(tx - 0.2, 4.6, 1.1), R(tx + 0.2, 4.65, 1.45), Color(0.05, 0.05, 0.06))
	_glow_quad(R(tx - 0.18, 4.58, 1.14), R(tx + 0.18, 4.58, 1.42), Color(0.3, 0.8, 0.5))
	spots.append({"kind": "trade", "pos": R(tx, 3.4, 0.0), "label": "TRADE COUNTER"})
	# Hanging sign over the counter.
	var sign := Label3D.new()
	sign.text = "TRADE COUNTER\nCash & card · Trade prices"
	sign.font_size = 72
	sign.pixel_size = 0.005
	sign.shaded = false
	sign.modulate = Color(1.0, 0.85, 0.3)
	sign.position = R(tx, 5.0, minf(H - 1.0, 3.4))
	_static.add_child(sign)
	# Roller shutter head + fascia outside.
	var oh: float = float(unit["oy1"]) - float(unit["oy0"])
	st.box(R(ox.x - 0.4, -0.35, oh + 0.1), R(ox.y + 0.4, -0.02, oh + 1.0), Color(0.85, 0.42, 0.1))
	var fas := Label3D.new()
	fas.text = String(unit.get("name", "")).to_upper()
	fas.font_size = 110
	fas.pixel_size = 0.005
	fas.shaded = false
	fas.modulate = Color(0.08, 0.08, 0.1)
	fas.position = R((ox.x + ox.y) * 0.5, -0.36, oh + 0.55)
	_static.add_child(fas)
	_light(R(W * 0.3, D * 0.4, H - 0.5), Color(0.95, 0.97, 1.0), 1.0, maxf(W, D) * 0.8)
	_light(R(W * 0.7, D * 0.6, H - 0.5), Color(0.95, 0.97, 1.0), 1.0, maxf(W, D) * 0.8)
	for ix in 3:
		_glow_quad(R(W * (0.2 + 0.3 * ix) - 0.9, D * 0.5 - 0.15, H - 0.02), R(W * (0.2 + 0.3 * ix) + 0.9, D * 0.5 + 0.15, H - 0.02),
			Color(1.0, 1.0, 1.0) * 1.3, true)
	door_in = R((ox.x + ox.y) * 0.5, 1.2, 0.0)
	door_out = R((ox.x + ox.y) * 0.5, -2.0, 0.0)
	rack_pos = R((ox.x + ox.y) * 0.5 + 3.5, -3.2, 0.0)
	# Collection bay outside: a pallet where bought goods wait.
	var pb := rack_pos
	st.box(pb + Vector3(-0.6, 0.0, -0.5), pb + Vector3(0.6, 0.14, 0.5), Color(0.6, 0.45, 0.28))
	spots.append({"kind": "pallet", "pos": pb + Vector3(0.0, 0.0, -1.0), "label": "COLLECTION BAY"})
	slot_box[-1] = [pb + Vector3(-0.6, 0.14, 0.5), Vector3.RIGHT, Vector3(0, 0, -1), 1.2, 0.0, 1.0]
	var bay := Label3D.new()
	bay.text = "COLLECTION BAY"
	bay.font_size = 64
	bay.pixel_size = 0.005
	bay.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	bay.shaded = false
	bay.modulate = Color(1.0, 0.85, 0.3)
	bay.position = pb + Vector3(0, 2.2, 0)
	_static.add_child(bay)


# -------------------------------------------------------------- goods
## Redraws the goods on every slot (and the cases in the stock room / on the
## collection pallet). Call after anything changes the stock.
func refresh_goods(pallet: Stock = null) -> void:
	if _goods == null:
		return
	for c in _goods.get_children():
		c.queue_free()
	var by_shape := {}   # shape -> [[Transform3D, Color]]
	if biz:
		for si in slot_box:
			if si < 0 or si >= biz.slots.size():
				continue
			var s: Dictionary = biz.slots[si]
			_slot_goods(si, s, by_shape)
	for shape in by_shape:
		var items: Array = by_shape[shape]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = shape_mesh(shape)
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, items[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mat("goods")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 60.0
		_goods.add_child(mmi)
	# Cases: the stock room's (shop) or the collection pallet's (warehouse).
	var src: Stock = biz.backroom if biz else pallet
	if src and slot_box.has(-1):
		var sb: Array = slot_box[-1]
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.mesh = shape_mesh("case")
		var list: Array = []
		for pid in src.units:
			for c in Stock.cases_for(pid, src.qty(pid)):
				list.append(pid)
		var per_row := maxi(int(float(sb[3]) / 0.52), 1)
		var shelves := [0.15, 0.9, 1.65] if biz else [0.0, 0.45, 0.9, 1.35]
		var cap := per_row * (2 if biz else 2) * shelves.size()
		mm2.instance_count = mini(list.size(), cap)
		for i in mm2.instance_count:
			var row := i % per_row
			var lvl := (i / per_row) % shelves.size()
			var deep := i / (per_row * shelves.size())
			var p: Vector3 = (sb[0] as Vector3) + (sb[1] as Vector3) * (0.27 + row * 0.52) \
				+ (sb[2] as Vector3) * (0.18 + deep * 0.3) * (-1.0 if biz else 1.0) + Vector3.UP * (float(shelves[lvl]) + 0.2)
			mm2.set_instance_transform(i, Transform3D(Basis(), p))
			mm2.set_instance_color(i, EmpireData.colour(list[i]).lerp(Color(0.72, 0.56, 0.36), 0.55))
		var mi2 := MultiMeshInstance3D.new()
		mi2.multimesh = mm2
		mi2.material_override = _mat("goods")
		_goods.add_child(mi2)
	# Price tags.
	for lab in _labels.get_children():
		var si: int = lab.get_meta("slot")
		if biz == null or si >= biz.slots.size():
			lab.text = ""
			continue
		var s: Dictionary = biz.slots[si]
		if s["product"] == "":
			lab.text = "— empty —"
		else:
			var p := EmpireData.product(s["product"])
			lab.text = "%s  %s%s" % [String(p.get("name", "")), EmpireData.money(biz.price(s["product"]), true),
				"" if int(s["qty"]) > 0 else "  · OUT"]
	if _dirt and biz:
		(_dirt.material_override as ShaderMaterial).set_shader_parameter("dirt", 1.0 - biz.cleanliness)


func _slot_goods(si: int, s: Dictionary, by_shape: Dictionary) -> void:
	var pid: String = s["product"]
	if pid == "" or int(s["qty"]) <= 0:
		return
	var p := EmpireData.product(pid)
	var shape := String(p.get("shape", "box"))
	var sz := shape_size(shape)
	var sb: Array = slot_box[si]
	var o: Vector3 = sb[0]
	var al: Vector3 = sb[1]
	var out: Vector3 = sb[2]
	var wdt: float = sb[3]
	var y: float = sb[4]
	var dep: float = sb[5]
	var across := maxi(int(wdt / (sz.x + 0.015)), 1)
	var rows := maxi(int(minf(dep, 0.5) / (sz.z + 0.02)), 1)
	var stack := 2 if shape in ["can", "bar", "box"] and s["fixture"] != "coffee" else 1
	var max_vis := across * rows * stack
	var vis := clampi(int(ceil(float(s["qty"]) / float(s["cap"]) * max_vis)), 1, max_vis)
	var col := EmpireData.colour(pid)
	var yaw := Basis.looking_at(-out, Vector3.UP)
	var n := 0
	# Front row first, from the left, so a part-empty shelf reads right.
	for r in rows:
		for st in stack:
			for a in across:
				if n >= vis:
					return
				var p0 := o + al * ((a + 0.5) * wdt / across) - out * (0.03 + sz.z * 0.5 + r * (sz.z + 0.02)) \
					+ Vector3.UP * (y + sz.y * 0.5 + st * (sz.y + 0.005))
				if not by_shape.has(shape):
					by_shape[shape] = []
				var tint := col * (1.0 - 0.06 * float((a + r) % 2))
				by_shape[shape].append([Transform3D(yaw, p0), Color(tint.r, tint.g, tint.b, 1.0)])
				n += 1


static func shape_size(shape: String) -> Vector3:
	match shape:
		"can": return Vector3(0.068, 0.122, 0.068)
		"bottle": return Vector3(0.075, 0.26, 0.075)
		"bag": return Vector3(0.17, 0.24, 0.07)
		"carton": return Vector3(0.08, 0.21, 0.08)
		"loaf": return Vector3(0.12, 0.12, 0.26)
		"bar": return Vector3(0.16, 0.03, 0.07)
		"pack": return Vector3(0.22, 0.22, 0.11)
		"cup": return Vector3(0.09, 0.11, 0.09)
		"case": return Vector3(0.48, 0.32, 0.36)
	return Vector3(0.12, 0.17, 0.06)  # box


## Pack meshes: a body in the instance colour with a white label band and a
## dark top/cap, so a shelf of the same colour still reads as packs.
static func shape_mesh(shape: String) -> Mesh:
	if _shape_meshes.has(shape):
		return _shape_meshes[shape]
	var sz := shape_size(shape)
	var b := _Batch.new()
	var h := sz * 0.5
	match shape:
		"can", "bottle", "cup":
			var neck := 0.0 if shape != "bottle" else sz.y * 0.28
			b.cylinder(Vector3(0, -h.y, 0), h.x, sz.y - neck, Color.WHITE, 10)
			b.cylinder(Vector3(0, -h.y + sz.y * 0.35, 0), h.x * 1.01, sz.y * 0.25, Color(0.92, 0.92, 0.92), 10)
			if neck > 0.0:
				b.cylinder(Vector3(0, h.y - neck, 0), h.x * 0.4, neck, Color(0.85, 0.85, 0.85), 8)
			else:
				b.cylinder(Vector3(0, h.y - 0.008, 0), h.x * 0.96, 0.008, Color(0.7, 0.7, 0.72), 10)
		"case":
			b.box(-h, h, Color.WHITE)
			b.box(Vector3(-h.x - 0.002, h.y - 0.05, -0.04), Vector3(h.x + 0.002, h.y + 0.002, 0.04), Color(0.82, 0.78, 0.62))
		_:
			b.box(-h, h, Color.WHITE)
			b.box(Vector3(-h.x * 0.8, -h.y * 0.2, h.z - 0.004), Vector3(h.x * 0.8, h.y * 0.45, h.z + 0.002), Color(0.95, 0.95, 0.95))
	var m := b.commit()
	_shape_meshes[shape] = m
	return m


# ------------------------------------------------------------ helpers
func _wall_box(st: _Batch, x0: float, x1: float, d0: float, d1: float, y0: float, y1: float, c: Color) -> void:
	st.box(R(x0, d1, y0), R(x1, d0, y1), c)
	_solid(R(x0, d1, y0), R(x1, d0, y1))


func _solid(a: Vector3, b: Vector3) -> void:
	var lo := a.min(b)
	var hi := a.max(b)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (hi - lo).max(Vector3.ONE * 0.02)
	cs.shape = bs
	cs.position = (lo + hi) * 0.5
	_col.add_child(cs)


func _floor(c: Color, style: int) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, D)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://src/empire/world/shop_floor.gdshader")
	fm.set_shader_parameter("base_col", c)
	fm.set_shader_parameter("room_size", Vector2(W, D))
	fm.set_shader_parameter("style", style)
	var fi := MeshInstance3D.new()
	fi.mesh = pm
	fi.material_override = fm
	fi.position = R(W * 0.5, D * 0.5, 0.012)
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fi.visibility_range_end = 260.0
	_static.add_child(fi)
	# Walkable floor collision (the building's tier was cut away).
	_solid(R(0.0, 0.0, -0.3), R(W, D, 0.0))


func _light(p: Vector3, c: Color, e: float, r: float) -> void:
	var o := OmniLight3D.new()
	o.position = p
	o.light_color = c
	o.light_energy = e
	o.omni_range = r
	o.omni_attenuation = 1.1
	o.shadow_enabled = false
	o.distance_fade_enabled = true
	o.distance_fade_begin = 90.0
	o.distance_fade_length = 30.0
	_static.add_child(o)


var _glow: _Batch


func _glow_quad(a: Vector3, b: Vector3, c: Color, ceiling := false) -> void:
	if _glow == null:
		_glow = _Batch.new()
	var lo := a.min(b)
	var hi := a.max(b)
	if ceiling or absf(hi.y - lo.y) < 0.001:
		_glow.box(lo - Vector3(0, 0.005, 0), Vector3(hi.x, lo.y + 0.002, hi.z), c)
	else:
		_glow.box(lo, hi + Vector3(0.004, 0, 0.004) * Vector3(float(absf(hi.x - lo.x) < 0.001), 0, float(absf(hi.z - lo.z) < 0.001)), c)


func _glow_quad_v(a: Vector3, b: Vector3, out: Vector3, c: Color) -> void:
	_glow_quad(a + out * 0.002, b + out * 0.006, c)


func _mesh_of(b: _Batch, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = _mat(mat)
	mi.visibility_range_end = 200.0
	return mi


static func _mat(k: String) -> Material:
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match k:
		"vc":
			m.roughness = 0.7
		"goods":
			m.roughness = 0.45
			m.vertex_color_use_as_albedo = true
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic_specular = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"tag":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.97, 0.95, 0.6)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[k] = m
	return m


static func _dirt_mat() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float dirt = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 p = UV * 9.0;
	float s = n(p) * 0.6 + n(p * 3.1) * 0.4;
	float a = smoothstep(1.0 - dirt * 0.75, 1.0 - dirt * 0.75 + 0.12, s) * min(dirt * 1.4, 0.85);
	ALBEDO = vec3(0.16, 0.13, 0.1);
	ALPHA = a;
}
"""
	sm.shader = sh
	return sm


# ------------------------------------------------------------- walk grid
func _build_walk_grid() -> void:
	walk.clear()
	var boxes: Array = []
	for c in _col.get_children():
		var cs := c as CollisionShape3D
		var bs := cs.shape as BoxShape3D
		if bs.size.y < 0.4 and cs.position.y < 0.0:
			continue  # (the floor)
		boxes.append(AABB(cs.position - bs.size * 0.5, bs.size).grow(0.28))
	var nx := int(ceil(W / CELL))
	var nz := int(ceil((D + 4.0) / CELL))
	for ix in nx:
		for iz in nz:
			var p := cell_pos(Vector2i(ix, iz))
			if p.x < 0.3 or p.x > W - 0.3:
				continue
			var d := -p.z
			if d > D - 0.3:
				continue
			if d < 0.35 and (p.x < door.x + 0.2 or p.x > door.y - 0.2):
				continue  # the shopfront, except the door
			var free := true
			for b: AABB in boxes:
				if b.has_point(Vector3(p.x, 0.5, p.z)):
					free = false
					break
			if free:
				walk[Vector2i(ix, iz)] = true


## Grid cell → room position (row 0 is 4 m outside the door).
func cell_pos(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, 4.0 - (c.y + 0.5) * CELL)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor((4.0 - p.z) / CELL)))


## A* over the walk grid (room coords in and out). Empty = no path.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := _nearest_free(cell_of(from))
	var b := _nearest_free(cell_of(to))
	var out := PackedVector3Array()
	if a == Vector2i(-999, -999) or b == Vector2i(-999, -999):
		return out
	var open := {a: true}
	var came := {}
	var g := {a: 0.0}
	var f := {a: Vector2(a - b).length()}
	var guard := 0
	while not open.is_empty() and guard < 4000:
		guard += 1
		var cur: Vector2i = open.keys()[0]
		for k in open:
			if f[k] < f[cur]:
				cur = k
		if cur == b:
			var cells: Array = [cur]
			while came.has(cur):
				cur = came[cur]
				cells.push_front(cur)
			for c in cells:
				out.append(cell_pos(c))
			out[out.size() - 1] = Vector3(to.x, 0.0, to.z)
			return out
		open.erase(cur)
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nb := cur + Vector2i(dx, dz)
				if not walk.has(nb):
					continue
				if dx != 0 and dz != 0 and (not walk.has(cur + Vector2i(dx, 0)) or not walk.has(cur + Vector2i(0, dz))):
					continue  # (no corner cutting)
				var ng: float = g[cur] + (1.414 if dx != 0 and dz != 0 else 1.0)
				if ng < float(g.get(nb, INF)):
					g[nb] = ng
					f[nb] = ng + Vector2(nb - b).length()
					came[nb] = cur
					open[nb] = true
	return out


func _nearest_free(c: Vector2i) -> Vector2i:
	if walk.has(c):
		return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if walk.has(c + Vector2i(dx, dz)):
					return c + Vector2i(dx, dz)
	return Vector2i(-999, -999)


## World-space interaction spots.
func world_spots() -> Array:
	var out: Array = []
	for s in spots:
		var d: Dictionary = s.duplicate()
		d["world"] = to_world(s["pos"])
		d["interior"] = self
		out.append(d)
	return out


## Is a world point inside this room?
func contains(world_p: Vector3) -> bool:
	var q := global_transform.affine_inverse() * world_p
	return q.x > 0.0 and q.x < W and q.z < 0.0 and q.z > -D and q.y > -1.0 and q.y < H


# -------------------------------------------------------- mesh batcher
class _Batch:
	var st := SurfaceTool.new()
	var n := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func box(a: Vector3, b: Vector3, c: Color) -> void:
		var lo := a.min(b)
		var hi := a.max(b)
		var v := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
		# faces: -z, +z, -x, +x, -y, +y (counter-clockwise seen from outside)
		_quad(v[1], v[0], v[3], v[2], Vector3(0, 0, -1), c)
		_quad(v[4], v[5], v[6], v[7], Vector3(0, 0, 1), c)
		_quad(v[0], v[4], v[7], v[3], Vector3(-1, 0, 0), c)
		_quad(v[5], v[1], v[2], v[6], Vector3(1, 0, 0), c)
		_quad(v[0], v[1], v[5], v[4], Vector3(0, -1, 0), c)
		_quad(v[7], v[6], v[2], v[3], Vector3(0, 1, 0), c)

	func cylinder(base: Vector3, r: float, h: float, c: Color, seg := 10) -> void:
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
			var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
			var nrm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
			_quad(p1, p0, p0 + Vector3.UP * h, p1 + Vector3.UP * h, nrm, c)
			_tri(base + Vector3.UP * h, p1 + Vector3.UP * h, p0 + Vector3.UP * h, Vector3.UP, c)

	func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
		_tri(a, b, c, nrm, col)
		_tri(a, c, d, nrm, col)

	func _tri(a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
		# Godot's front faces are clockwise: emit a, c, b for CCW input.
		for p in [a, c, b]:
			st.set_color(col)
			st.set_normal(nrm)
			st.add_vertex(p)
		n += 3

	func commit() -> ArrayMesh:
		if n == 0:
			return ArrayMesh.new()
		return st.commit()
