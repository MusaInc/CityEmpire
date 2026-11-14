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
## A QuikSave store (CityLife rival record): drawn fully stocked in the
## chain's red, with no interaction spots (it isn't yours).
var rival := {}
## The shop's brand colour: fascia, shelf headers, counter front, wall band.
var brand := Color(0.15, 0.4, 0.3)
## The shop's identity (ShopStyle.brand) and its kind's interior (look).
var ident := {}
var look := {}
var type_id := "convenience"
## Window posters per kind of shop (PROMOS below for corner shops).
const PROMOS_BY := {
	"clothing": ["NEW\nSEASON", "UP TO\n50% OFF", "DENIM\nFROM £34", "SUMMER\nEDIT", "SALE"],
	"cafe": ["FLAT WHITE\n£2.90", "FRESH\nPASTRIES", "BREAKFAST\nTILL 11", "OAT MILK\nNO EXTRA", "CAKE OF\nTHE DAY"],
	"takeaway": ["2 PIECE\nMEAL £4.99", "OPEN\nTILL LATE", "FAMILY\nBUCKET", "HALAL", "FREE\nDRINK"],
	"bakery": ["BAKED\nTHIS\nMORNING", "SOURDOUGH\n£3.90", "CELEBRATION\nCAKES", "SAUSAGE\nROLLS"],
	"phones": ["NOVA 12\nOUT NOW", "REPAIRS\nWHILE\nYOU WAIT", "TRADE IN\nYOUR OLD\nPHONE", "SIM ONLY\n£10"],
}
const PROMOS := ["MEAL DEAL\n£3.50", "COLD DRINKS\n2 FOR £2", "FRESH\nBREAD\nDAILY", "OPEN\n7AM–10PM", "HOT\nCOFFEE\n£1.80",
	"CARD &\nCONTACTLESS", "SNACKS\n3 FOR £2", "LOCAL\n& FRESH"]
const BRANDS := [Color(0.13, 0.42, 0.36), Color(0.16, 0.27, 0.5), Color(0.42, 0.2, 0.42), Color(0.2, 0.42, 0.2),
	Color(0.55, 0.32, 0.12), Color(0.1, 0.38, 0.52)]
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
var pile_pos := Vector3.ZERO
var _mid_used := false            # did fixtures take the middle of the floor?
var street_drop := 0.0            # m the floor stands above the pavement outside      # where cases put down on the floor stack up
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
var _ground_fn := Callable()


func setup(p_unit: Dictionary, p_biz: Business, ground_fn := Callable(), p_rival := {}) -> void:
	_ground_fn = ground_fn
	unit = p_unit
	biz = p_biz
	kind = String(unit.get("kind", "shop"))
	rival = p_rival
	brand = BRANDS[absi(String(unit.get("id", "")).hash()) % BRANDS.size()]
	if not rival.is_empty() and biz == null:
		if rival.get("firm", false):
			biz = rival_display(unit, String(rival.get("name", "")), String(rival.get("type", "convenience")))
		else:
			biz = rival_display(unit)
	type_id = biz.type_id if biz else "convenience"
	look = ShopStyle.look(type_id)
	if biz:
		ident = ShopStyle.brand(biz.name, type_id, not rival.is_empty() and not rival.get("firm", false))
		brand = ident["primary"]
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
	# How far the shop floor stands above the pavement at the door (a step).
	if ground_fn.is_valid() and kind == "shop":
		var outside := transform * Vector3((ox.x + ox.y) * 0.5, 0.0, 1.4)
		street_drop = clampf(transform.origin.y - float(ground_fn.call(outside.x, outside.z)), 0.0, 1.2)
	name = "Interior_" + String(unit.get("id", "unit"))
	rebuild()


## A fully stocked, fitted-out stand-in Business for drawing a store run by
## someone else (QuikSave, or an independent called `title`).
static func rival_display(u: Dictionary, title := "", type := "convenience") -> Business:
	var b := Business.new("rival_" + String(u.get("id", "")), type)
	b.setup_new(Premises.record(u), 1)
	for up in b.type_def().get("upgrades", []):
		if up in ["shelf_2", "fridge_2", "rail_2", "table_2", "cake_2", "lighting", "signage", "floor"]:
			b.apply_upgrade(up)
	b.name = title if title != "" else String(CityLife.rival_cfg().get("name", "QuikSave"))
	# Every slot stocked with something its fixture holds, from the shop's
	# own categories (a bakery's shelf has loaves, a clothes shop's shoes).
	var cats: Array = b.type_def().get("categories", [])
	var used := {}
	for s: Dictionary in b.slots:
		var fx: String = s["fixture"]
		if String(s["product"]) != "":
			s["qty"] = int(s["cap"])
			continue
		var pool: Array = EmpireData.product_ids().filter(func(p): return EmpireData.product(p)["fixture"] == fx \
			and String(EmpireData.product(p)["cat"]) in cats)
		if pool.is_empty():
			pool = EmpireData.product_ids().filter(func(p): return EmpireData.product(p)["fixture"] == fx)
		if pool.is_empty():
			continue
		var k := int(used.get(fx, 0))
		used[fx] = k + 1
		s["product"] = pool[k % pool.size()]
		s["qty"] = int(s["cap"])
	return b


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
	if _glass != null:
		var gl := MeshInstance3D.new()
		gl.name = "Glass"
		gl.mesh = _glass.commit()
		gl.material_override = _mat("glass")
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_static.add_child(gl)
		_glass = null
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
	_cull_details()


## Small things (lettering, posters, goods, lamps) only drawn up close; the
## shell and fascia carry the look further out. Someone else's shop is
## culled sooner (dozens of them line the streets).
func _cull_details() -> void:
	var near := 70.0 if rival.is_empty() else 55.0
	for n in find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g == _sign or g.name == "Shell":
			continue
		if g is Label3D or g.get_parent() == _goods or g.name == "Glow":
			g.visibility_range_end = near if g.name != "Glow" else maxf(near, 90.0)


# ------------------------------------------------------------- shop
func _build_shop(st: _Batch) -> void:
	if look.is_empty():
		look = ShopStyle.look(type_id)
	var wall: Color = look["wall"]
	var trim := Color(0.18, 0.2, 0.22)
	var floor_style := int(look["floor_style"])
	var floor_col: Color = look["floor"]
	if biz and biz.has_upgrade("floor"):
		if type_id == "convenience":
			floor_style = 1
			floor_col = Color(0.86, 0.85, 0.82)
		else:
			floor_col = floor_col.lightened(0.08)
	_floor(floor_col, floor_style)
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
	st.box(R(cx0 - 0.02, cd0 + 0.08, 0.12), R(cx0, cd1 - 0.08, 0.86), brand)  # branded counter front
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
	_decor(st, part_d, cx0, cd0, cd1)
	# Back room: racking, office desk, mop.
	_backroom(st, part_d, dw0, dw1)
	door_in = R((door.x + door.y) * 0.5, 0.9, 0.0)
	door_out = R((door.x + door.y) * 0.5, -1.6, 0.0)
	spots.append({"kind": "door", "pos": R((door.x + door.y) * 0.5, 0.55, 0.0), "label": "OPEN / CLOSE"})
	# The floor pile: just inside, left of the door, in front of the window.
	pile_pos = R(clampf(door.x - 1.0, 0.7, W * 0.5), 1.05, 0.0)
	spots.append({"kind": "pile", "pos": pile_pos, "label": "FLOOR"})
	# A sign over the stockroom door.
	var srs := Label3D.new()
	srs.text = "STOCKROOM"
	srs.font_size = 64
	srs.pixel_size = 0.004
	srs.shaded = false
	srs.modulate = Color(1.0, 0.85, 0.3)
	srs.outline_size = 8
	srs.position = R((dw0 + dw1) * 0.5, part_d - 0.03, 2.55)
	_static.add_child(srs)
	# Ceiling lights (their kind follows the shop's).
	var bright := 1.25 if biz and biz.has_upgrade("lighting") else 0.85
	var tint: Color = look.get("tint", Color(1.0, 0.97, 0.92))
	if biz and biz.has_upgrade("lighting"):
		tint = tint.lerp(Color(1.0, 0.9, 0.78), 0.4)
	_ceiling_lights(st, part_d, tint)
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


## Dressing: a brand band round the walls, posters, an entrance mat, a
## basket stack and a newspaper stand by the door, a plant, PAY HERE sign.
func _decor(st: _Batch, part_d: float, cx0: float, cd0: float, cd1: float) -> void:
	if type_id == "convenience":
		_decor_corner(st, part_d, cx0, cd0, cd1)
	else:
		_decor_trade(st, part_d, cx0, cd0, cd1)


func _decor_corner(st: _Batch, part_d: float, cx0: float, cd0: float, cd1: float) -> void:
	var band := brand.lightened(0.05)
	# Band at 2.4 m on both side walls and the partition.
	st.box(R(0.03, 0.3, 2.35), R(0.06, part_d, 2.6), band)
	st.box(R(W - 0.06, 0.3, 2.35), R(W - 0.03, part_d, 2.6), band)
	st.box(R(0.0, part_d - 0.03, 2.35), R(W, part_d, 2.6), band)
	# Dado: a darker lower wall that hides scuffs.
	st.box(R(0.03, 0.3, 0.12), R(0.05, part_d, 0.95), Color(0.62, 0.6, 0.56))
	st.box(R(W - 0.05, 0.3, 0.12), R(W - 0.03, part_d, 0.95), Color(0.62, 0.6, 0.56))
	# Posters high on the left wall (above the shelving).
	var pd := 1.6
	var pcols := [Color(0.95, 0.75, 0.2), Color(0.9, 0.35, 0.3), Color(0.35, 0.65, 0.95)]
	var i := 0
	while pd + 1.0 < part_d - 0.5 and i < 3:
		st.box(R(0.06, pd, 2.75), R(0.08, pd + 0.9, 3.55), Color(0.96, 0.95, 0.92))
		st.box(R(0.08, pd + 0.06, 2.95), R(0.09, pd + 0.84, 3.49), pcols[i % pcols.size()])
		st.box(R(0.08, pd + 0.1, 2.8), R(0.09, pd + 0.8, 2.88), brand)
		pd += 2.2
		i += 1
	# Entrance mat.
	var mid := (door.x + door.y) * 0.5
	st.box(R(mid - 0.9, 0.32, 0.0), R(mid + 0.9, 1.4, 0.018), Color(0.14, 0.14, 0.15))
	st.box(R(mid - 0.75, 0.42, 0.018), R(mid + 0.75, 1.3, 0.022), brand.darkened(0.35))
	# Basket stack (front-left corner).
	for k in 5:
		var y := 0.0 + k * 0.09
		st.box(R(0.25, 0.45, y), R(0.7, 0.85, y + 0.07), Color(0.85, 0.15, 0.15) if rival.is_empty() else Color(0.95, 0.95, 0.95))
	_solid(R(0.2, 0.4, 0.0), R(0.75, 0.9, 0.5))
	# Newspaper stand (left of the door).
	var nx := door.x - 1.1
	if nx > 1.0:
		st.box(R(nx, 0.45, 0.0), R(nx + 0.7, 0.85, 0.7), Color(0.25, 0.27, 0.3))
		for j in 3:
			st.box(R(nx + 0.05 + j * 0.22, 0.5, 0.7), R(nx + 0.24 + j * 0.22, 0.8, 0.74),
				[Color(0.92, 0.92, 0.9), Color(0.95, 0.85, 0.5), Color(0.85, 0.9, 0.95)][j])
		_solid(R(nx, 0.45, 0.0), R(nx + 0.7, 0.85, 0.75))
	# A plant in the front-right window corner.
	var px := W - 0.55
	st.box(R(px - 0.2, 0.4, 0.0), R(px + 0.2, 0.8, 0.42), Color(0.55, 0.32, 0.2))
	st.box(R(px - 0.32, 0.28, 0.42), R(px + 0.32, 0.92, 1.05), Color(0.2, 0.45, 0.22))
	st.box(R(px - 0.2, 0.4, 1.05), R(px + 0.2, 0.8, 1.35), Color(0.25, 0.52, 0.25))
	_solid(R(px - 0.32, 0.28, 0.0), R(px + 0.32, 0.92, 1.0))
	# PAY HERE board hanging over the counter.
	var hd := (cd0 + cd1) * 0.5
	st.box(R(cx0 - 0.1, hd - 0.7, 2.75), R(cx0 - 0.04, hd + 0.7, 3.15), brand)
	for e: float in [-0.5, 0.5]:
		st.box(R(cx0 - 0.08, hd + e - 0.01, 3.15), R(cx0 - 0.06, hd + e + 0.01, H), Color(0.3, 0.3, 0.32))
	var lab := Label3D.new()
	lab.text = "PAY HERE"
	lab.font_size = 56
	lab.pixel_size = 0.004
	lab.outline_size = 0
	lab.shaded = false
	lab.modulate = Color(1, 1, 1)
	lab.position = R(cx0 - 0.115, hd, 2.95)
	lab.rotation.y = -PI * 0.5
	_static.add_child(lab)


func _shell(st: _Batch, wall: Color, trim: Color) -> void:
	# Side and back walls (inner faces), ceiling.
	_wall_box(st, -0.05, 0.02, 0.0, D, 0.0, H, wall)
	_wall_box(st, W - 0.02, W + 0.05, 0.0, D, 0.0, H, wall)
	_wall_box(st, 0.0, W, D - 0.02, D + 0.05, 0.0, H, wall.darkened(0.06))
	var ceil_col: Color = look.get("ceiling", Color(0.78, 0.78, 0.76)) if not look.is_empty() else Color(0.78, 0.78, 0.76)
	st.box(R(0.0, 0.0, H - 0.01), R(W, D, H + 0.05), ceil_col)
	# Suspended-ceiling grid (corner shops and the warehouse).
	if look.is_empty() or String(look.get("lights", "grid")) == "grid":
		var gx := 1.2
		while gx < W:
			st.box(R(gx - 0.015, 0.3, H - 0.035), R(gx + 0.015, D, H - 0.01), Color(0.55, 0.56, 0.57))
			gx += 1.2
		var gz := 1.5
		while gz < D:
			st.box(R(0.0, gz - 0.015, H - 0.035), R(W, gz + 0.015, H - 0.01), Color(0.55, 0.56, 0.57))
			gz += 1.2
	# Skirting.
	st.box(R(0.02, 0.0, 0.0), R(0.05, D, 0.12), trim)
	st.box(R(W - 0.05, 0.0, 0.0), R(W - 0.02, D, 0.12), trim)
	# Inner face of the front wall round the opening (0.3 m thick wall).
	var oh: float = float(unit["oy1"]) - float(unit["oy0"])
	# (Its outer face stops 3 cm inside the facade, or the two z-fight.)
	_wall_box(st, 0.0, ox.x, 0.03, 0.3, 0.0, H, wall)
	_wall_box(st, ox.y, W, 0.03, 0.3, 0.0, H, wall)
	_wall_box(st, ox.x, ox.y, 0.03, 0.3, oh, H, wall)


func _shopfront(st: _Batch, _trim: Color) -> void:
	var oh: float = float(unit["oy1"]) - float(unit["oy0"])
	var gd := 0.12  # glass line, just inside the facade
	var trading_here := biz != null
	var hsh := absi(String(unit.get("id", "")).hash())
	# The joinery: painted timber, anodised aluminium or slim black steel
	# (ShopStyle.front), its stall risers, mullions and a lobbied door.
	var sf := ShopStyle.front(type_id if trading_here else "", hsh, brand, not rival.is_empty() and not rival.get("firm", false))
	var fc: Color = sf["frame"]
	var rh: float = sf["riser"]
	var mw: float = sf["mullion"]
	var th := oh - 0.62   # transom bar (and the door head)
	var dr := 0.75        # the doors stand this far back, in a lobby
	var glass_c := Color(0.6, 0.75, 0.8, 0.2)
	if _glass == null:
		_glass = _Batch.new()
	# Reveals: the cut edges of the building's wall, cased in the frame colour.
	st.box(R(0.28, -0.02, 0.0), R(ox.x + 0.06, gd + 0.08, oh), fc)
	st.box(R(ox.y - 0.06, -0.02, 0.0), R(W - 0.28, gd + 0.08, oh), fc)
	st.box(R(ox.x, -0.02, oh - 0.12), R(ox.y, gd + 0.08, oh), fc)
	# Either side of the door: stall riser, sill, panes split by mullions.
	var spans: Array = []
	for side in [[ox.x + 0.06, door.x], [door.y, ox.y - 0.06]]:
		var x0: float = side[0]
		var x1: float = side[1]
		if x1 - x0 < 0.2:
			continue
		spans.append([x0, x1])
		_riser(st, x0, x1, gd, rh, fc, sf)
		st.box(R(x0, gd - 0.13, rh), R(x1, gd + 0.06, rh + 0.05), fc.lightened(0.15))  # sill
		var panes := maxi(1, ceili((x1 - x0) / 1.9))
		for i in panes + 1:
			var mx := lerpf(x0, x1, float(i) / panes)
			st.box(R(mx - mw, gd - 0.06, rh), R(mx + mw, gd + 0.05, oh - 0.12), fc)
		_glass.box(R(x0, gd - 0.01, rh + 0.05), R(x1, gd + 0.01, th), glass_c)
		_solid(R(x0, gd - 0.08, 0.0), R(x1, gd + 0.08, oh))
	# Transom bar across the whole front, glazed lights above it.
	st.box(R(ox.x, gd - 0.07, th), R(ox.y, gd + 0.06, th + 0.07), fc)
	_glass.box(R(ox.x + 0.06, gd - 0.01, th + 0.07), R(ox.y - 0.06, gd + 0.01, oh - 0.12), glass_c)
	# The lobby: glazed returns either side, a mosaic floor, a soffit, and
	# the pair of doors standing open against the returns.
	for rx: float in [door.x, door.y]:
		st.box(R(rx - 0.04, gd, 0.0), R(rx + 0.04, dr, rh), fc)                       # return riser
		st.box(R(rx - 0.05, dr - 0.05, 0.0), R(rx + 0.05, dr + 0.05, th), fc)        # back post
		st.box(R(rx - 0.04, gd, th - 0.06), R(rx + 0.04, dr, th), fc)                 # top rail
		_glass.box(R(rx - 0.01, gd, rh), R(rx + 0.01, dr, th - 0.06), glass_c)
		_solid(R(rx - 0.05, gd, 0.0), R(rx + 0.05, dr, th))
		var s := 1.0 if rx == door.x else -1.0   # into the doorway
		var lx := rx + s * 0.035
		var leaf_c := fc.darkened(0.08)
		var l0 := lx - 0.025
		var l1 := lx + 0.025
		st.box(R(l0, dr, 0.02), R(l1, dr + 0.9, 0.3), leaf_c)                         # kick rail
		st.box(R(l0, dr, th - 0.2), R(l1, dr + 0.9, th - 0.08), leaf_c)              # top rail
		for e: float in [dr, dr + 0.84]:
			st.box(R(l0, e, 0.02), R(l1, e + 0.06, th - 0.08), leaf_c)                 # stiles
		_glass.box(R(lx - 0.008, dr + 0.06, 0.3), R(lx + 0.008, dr + 0.84, th - 0.2), glass_c)
		# Push bar (chrome) on the doorway side.
		var bx := lx + s * 0.06
		st.box(R(bx - 0.012, dr + 0.2, 0.98), R(bx + 0.012, dr + 0.7, 1.02), Color(0.82, 0.83, 0.85))
	st.box(R(door.x, dr - 0.05, th - 0.1), R(door.y, dr + 0.05, th), fc)            # door head
	st.box(R(door.x, gd, th), R(door.y, dr, th + 0.05), Color(0.9, 0.89, 0.86))      # soffit
	var tile := Color(0.9, 0.88, 0.82)
	st.box(R(door.x + 0.04, -0.02, 0.0), R(door.y - 0.04, dr, 0.022), tile)
	st.box(R(door.x + 0.04, -0.02, 0.022), R(door.y - 0.04, 0.06, 0.026), brand.darkened(0.35))  # threshold border
	st.box(R(door.x + 0.2, 0.18, 0.022), R(door.y - 0.2, dr - 0.12, 0.024), brand.darkened(0.35))
	st.box(R(door.x + 0.26, 0.24, 0.024), R(door.y - 0.26, dr - 0.18, 0.026), tile.lerp(brand, 0.25))
	if trading_here:
		# A display light along the window head (lit from inside).
		for sp in spans:
			_glow_quad(R(float(sp[0]) + 0.1, gd + 0.12, th - 0.03), R(float(sp[1]) - 0.1, gd + 0.24, th - 0.03), Color(1.0, 0.95, 0.85) * 1.2, true)
	# The frontage across the whole unit, outside the facade: stone
	# pilasters, a full-width fascia under a cornice, and (when trading) a
	# canopy, lamps and a hanging blade sign. Offset off the wall so nothing
	# z-fights.
	var fy := oh + 0.15
	var stone := Color(0.84, 0.81, 0.75) if hsh % 3 != 0 else Color(0.24, 0.25, 0.27)
	var sign_style := String(ident.get("sign", "painted"))
	var accent_c: Color = ident.get("accent", Color(1.0, 0.92, 0.7))
	var fascia := brand if trading_here else Color(0.1, 0.12, 0.16)
	if trading_here:
		match sign_style:
			"lightbox":
				fascia = accent_c if accent_c.get_luminance() > 0.6 else Color(0.96, 0.96, 0.95)
			"neon":
				fascia = brand.darkened(0.7)
			"script":
				fascia = accent_c.lerp(Color(0.97, 0.95, 0.9), 0.3)
	# Window posters, stuck inside the glass at the outer end of each window.
	for sp in spans:
		var x0: float = sp[0]
		var x1: float = sp[1]
		var outer := x0 < door.x
		var pw := minf(0.85, (x1 - x0) - 0.6)
		if pw < 0.5:
			continue
		var px0 := x0 + 0.25 if outer else x1 - 0.25 - pw
		var py0 := rh + 0.45
		var py1 := minf(th - 0.25, py0 + pw * 1.3)
		if trading_here:
			_poster(R(px0, gd + 0.03, py0), R(px0 + pw, gd + 0.03, py1), brand.lightened(0.12), Color(0.98, 0.9, 0.55),
				_promo_text(x0))
		elif kind == "shop" and outer:
			_poster(R(px0, gd + 0.03, py0), R(px0 + pw, gd + 0.03, py1), Color(0.97, 0.96, 0.92), Color(0.75, 0.1, 0.12),
				"TO LET\nRETAIL UNIT\n%d m²\nCITY LETTINGS" % int(unit.get("size", 0)), Color(0.15, 0.15, 0.18))
	if trading_here:
		# Opening hours and payment stickers on the glass beside the door.
		var hrs := biz.hours()
		var stk := Label3D.new()
		stk.text = "OPEN 7 DAYS\n%s – %s\n\nCARD · CONTACTLESS" % [_clock(hrs.x), _clock(hrs.y)]
		stk.font_size = 32
		stk.pixel_size = 0.0028
		stk.shaded = false
		stk.double_sided = false
		stk.outline_size = 0
		stk.modulate = Color(1.0, 1.0, 1.0, 0.92)
		stk.position = R(door.y + 0.4, gd - 0.015, 1.55)
		_static.add_child(stk)
	# Street level: the plinth down to the pavement and a step up to the door.
	# (0.24 m proud: in front of the building's own base course, 0.2 m out,
	# and just behind the pilaster bases' faces. Deeper than the step: streets
	# slope along the shopfront.)
	st.box(R(-0.04, -0.24, -street_drop - 1.2), R(W + 0.04, -0.005, 0.02), stone.darkened(0.3))
	if street_drop > 0.02:
		var sx0 := door.x - 0.35
		var sx1 := door.y + 0.35
		if street_drop > 0.3:
			var mid := -street_drop * 0.5
			st.box(R(sx0 - 0.1, -1.05, -street_drop - 0.05), R(sx1 + 0.1, -0.5, mid), stone.lightened(0.04))
			_solid(R(sx0 - 0.1, -1.05, -street_drop - 0.05), R(sx1 + 0.1, -0.5, mid))
		st.box(R(sx0, -0.55, -street_drop - 0.05), R(sx1, 0.0, 0.0), stone.lightened(0.1))
		_solid(R(sx0, -0.55, -street_drop - 0.05), R(sx1, 0.0, 0.0))
	if trading_here:
		_window_display(st, spans, gd)
		_street_dressing(st, hsh, oh)
		if bool(sf["shutter"]) and not rival.is_empty():
			_shutters(st, oh, sf)  # (not on your own shops: you'd walk through it)
	elif kind == "shop":
		_vacant(st, fy)
	# Pilasters with capitals.
	for px: float in [-0.04, W - 0.3]:
		st.box(R(px, -0.22, 0.0), R(px + 0.34, -0.01, fy + 0.86), stone)
		st.box(R(px - 0.04, -0.27, fy + 0.72), R(px + 0.38, -0.01, fy + 0.92), stone.lightened(0.08))
		st.box(R(px - 0.03, -0.25, 0.0), R(px + 0.37, -0.01, 0.3), stone.darkened(0.2))  # plinth
		_solid(R(px, -0.22, 0.0), R(px + 0.34, 0.0, fy))
	# Fascia and cornice.
	st.box(R(0.3, -0.3, fy), R(W - 0.3, -0.01, fy + 0.78), fascia)
	if trading_here and sign_style == "lightbox":
		_glow_quad(R(0.35, -0.305, fy + 0.04), R(W - 0.35, -0.305, fy + 0.74), fascia * 0.9)
	if trading_here and String(ident.get("initial", "")) != "":
		# The logo: a roundel-ish badge with the initial at the fascia's left.
		var lx0 := 0.55
		st.box(R(lx0, -0.34, fy + 0.07), R(lx0 + 0.64, -0.29, fy + 0.71), accent_c if sign_style != "lightbox" else brand)
		st.box(R(lx0 + 0.05, -0.35, fy + 0.12), R(lx0 + 0.59, -0.335, fy + 0.66), brand if sign_style != "lightbox" else accent_c)
		var logo := Label3D.new()
		logo.text = String(ident["initial"])
		logo.font = ShopStyle.font(String(ident.get("face", "")))
		logo.font_size = 120
		logo.pixel_size = 0.0034
		logo.shaded = false
		logo.outline_size = 0
		logo.modulate = accent_c if sign_style != "lightbox" else brand
		logo.position = R(lx0 + 0.32, -0.36, fy + 0.39)
		_static.add_child(logo)
	st.box(R(0.3, -0.33, fy - 0.07), R(W - 0.3, -0.01, fy), fascia.lightened(0.3) if trading_here else Color(0.3, 0.32, 0.35))
	st.box(R(-0.12, -0.4, fy + 0.78), R(W + 0.12, -0.01, fy + 0.94), stone.lightened(0.05))
	if trading_here:
		# A striped awning over the door and windows, sloping out to a valance
		# (painted and script fronts; lightbox and neon ones go without).
		var c0 := ox.x - 0.45
		var awning := sign_style in ["painted", "script"]
		var c1 := ox.y + 0.45
		var cream := Color(0.95, 0.92, 0.84)
		var ay0 := fy - 0.08
		var ay1 := fy - 0.7
		var ad := -1.45
		var stripes := maxi(4, int((c1 - c0) / 0.42))
		for i in (stripes if awning else 0):
			var xa := lerpf(c0, c1, float(i) / stripes)
			var xb := lerpf(c0, c1, float(i + 1) / stripes)
			var sc := brand if i % 2 == 0 else cream
			st.sheet(R(xa, -0.28, ay0), R(xb, -0.28, ay0), R(xb, ad, ay1), R(xa, ad, ay1), sc)
			st.sheet(R(xa, ad, ay1), R(xb, ad, ay1), R(xb, ad, ay1 - 0.24), R(xa, ad, ay1 - 0.24), sc.darkened(0.08))
		if awning:
			for ex: float in [c0, c1]:
				st._tri(R(ex, -0.28, ay0), R(ex, ad, ay1), R(ex, -0.28, ay1), Vector3.RIGHT, fascia.darkened(0.2))
				st._tri(R(ex, -0.28, ay0), R(ex, -0.28, ay1), R(ex, ad, ay1), Vector3.LEFT, fascia.darkened(0.2))
			st.box(R(c0, -0.3, ay0 - 0.04), R(c1, -0.22, ay0 + 0.06), Color(0.12, 0.12, 0.13))  # roller box
		if rival.get("for_sale", false):
			# An estate agent's board on the wall over the fascia.
			var bx0 := W - 2.3
			st.box(R(bx0, -0.14, fy + 1.02), R(bx0 + 1.7, -0.05, fy + 1.86), Color(0.98, 0.8, 0.12))
			st.box(R(bx0, -0.15, fy + 1.02), R(bx0 + 1.7, -0.05, fy + 1.2), Color(0.75, 0.1, 0.1))
			var fsl := Label3D.new()
			fsl.text = "FOR SALE"
			fsl.font_size = 96
			fsl.pixel_size = 0.0034
			fsl.shaded = false
			fsl.modulate = Color(0.75, 0.08, 0.08)
			fsl.position = R(bx0 + 0.85, -0.15, fy + 1.55)
			_static.add_child(fsl)
			var agl := Label3D.new()
			agl.text = "BUSINESS TRANSFER AGENTS"
			agl.font_size = 40
			agl.pixel_size = 0.0034
			agl.shaded = false
			agl.modulate = Color(1, 1, 1)
			agl.position = R(bx0 + 0.85, -0.16, fy + 1.11)
			_static.add_child(agl)
		# Gooseneck lamps lighting the fascia.
		for gx: float in [W * 0.22, W * 0.78]:
			st.box(R(gx - 0.02, -0.75, fy + 0.95), R(gx + 0.02, -0.3, fy + 0.99), Color(0.1, 0.1, 0.11))
			st.box(R(gx - 0.1, -0.86, fy + 0.86), R(gx + 0.1, -0.68, fy + 1.0), Color(0.1, 0.1, 0.11))
			_glow_quad(R(gx - 0.08, -0.84, fy + 0.855), R(gx + 0.08, -0.7, fy + 0.855), Color(1.0, 0.92, 0.75) * 1.8, true)
		# Hanging blade sign at the left pilaster.
		st.box(R(0.1, -0.95, fy + 0.6), R(0.16, -0.25, fy + 0.66), Color(0.1, 0.1, 0.11))
		st.box(R(0.08, -0.9, fy - 0.15), R(0.18, -0.3, fy + 0.6), fascia)
		st.box(R(0.07, -0.92, fy - 0.17), R(0.19, -0.28, fy - 0.12), stone)
		var blade := Label3D.new()
		blade.text = biz.name.left(1).to_upper()
		blade.font_size = 120
		blade.pixel_size = 0.004
		blade.shaded = false
		blade.modulate = Color(1.0, 0.95, 0.85)
		blade.position = R(0.195, -0.6, fy + 0.22)
		blade.rotation.y = PI * 0.5
		_static.add_child(blade)
		var blade2 := blade.duplicate() as Label3D
		blade2.position = R(0.065, -0.6, fy + 0.22)
		blade2.rotation.y = -PI * 0.5
		_static.add_child(blade2)
	_sign = Label3D.new()
	_sign.text = _sign_text()
	_sign.font_size = 96
	_sign.pixel_size = 0.0045
	_sign.outline_size = 0
	_sign.modulate = Color(1.0, 0.92, 0.7)
	_sign.position = R(W * 0.5, -0.315, fy + 0.39)
	_sign.rotation.y = 0.0  # faces +z (out to the street)
	_sign.double_sided = false
	_sign.shaded = false
	_sign.width = (W - 1.0) / 0.0045
	_sign.autowrap_mode = TextServer.AUTOWRAP_OFF
	_static.add_child(_sign)
	if trading_here:
		# The brand's typeface and sign style.
		_sign.font = ShopStyle.font(String(ident.get("face", "")))
		_sign.position.x += 0.35  # (clear of the logo)
		_sign.width = (W - 1.9) / _sign.pixel_size
		match sign_style:
			"lightbox":
				_sign.modulate = brand
			"neon":
				_sign.modulate = (accent_c if accent_c.get_luminance() > 0.3 else brand.lightened(0.4)) * 2.2
				_sign.outline_size = 18
				_sign.outline_modulate = Color(brand.lightened(0.2), 0.55)
			"script":
				_sign.modulate = brand
			_:
				_sign.modulate = accent_c
	if not rival.is_empty() and not rival.get("firm", false):
		_sign.modulate = Color(1.0, 1.0, 1.0)
	var lit := biz != null and biz.has_upgrade("signage")
	if lit:
		_sign_light = OmniLight3D.new()
		_sign_light.position = R((ox.x + ox.y) * 0.5, -1.0, fy + 0.4)
		_sign_light.light_color = Color(1.0, 0.85, 0.6)
		_sign_light.light_energy = 1.2
		_sign_light.omni_range = 5.0
		_static.add_child(_sign_light)
		if sign_style != "neon":
			_sign.modulate = _sign.modulate * 1.35
	# OPEN / CLOSED / TO LET card in the door glass.
	_open_sign = Label3D.new()
	_open_sign.font_size = 64
	_open_sign.pixel_size = 0.004
	_open_sign.position = R(door.x - 0.5, gd - 0.03, 1.5)
	_open_sign.shaded = false
	_static.add_child(_open_sign)
	update_signs(false)


## A stall riser under a window: painted timber with raised and fielded
## panels, or a plain polished plinth (aluminium and steel fronts).
func _riser(st: _Batch, x0: float, x1: float, gd: float, rh: float, fc: Color, sf: Dictionary) -> void:
	var rc: Color = sf["riser_col"]
	st.box(R(x0, gd - 0.08, 0.0), R(x1, gd + 0.06, rh), rc)
	st.box(R(x0, gd - 0.1, 0.0), R(x1, gd - 0.08, 0.08), rc.darkened(0.3))  # kick strip
	if bool(sf["panels"]) and rh > 0.3:
		var n := maxi(1, roundi((x1 - x0) / 0.95))
		var pw := (x1 - x0) / n
		for i in n:
			var a := x0 + pw * i + 0.08
			var b := x0 + pw * (i + 1) - 0.08
			st.box(R(a, gd - 0.105, 0.14), R(b, gd - 0.08, rh - 0.08), fc.lightened(0.07))
			st.box(R(a + 0.06, gd - 0.115, 0.2), R(b - 0.06, gd - 0.1, rh - 0.14), fc.lightened(0.03))
	elif rh > 0.2:
		st.box(R(x0, gd - 0.09, rh - 0.03), R(x1, gd - 0.08, rh), fc)  # a metal capping


## A lit poster stuck inside the glass (a, b: its corners, facing the street).
func _poster(a: Vector3, b: Vector3, col: Color, band: Color, text: String, ink := Color(1.0, 0.98, 0.94)) -> void:
	_glow_quad(a, b, col * 0.75)
	var lo := a.min(b)
	var hi := a.max(b)
	_glow_quad(Vector3(lo.x, hi.y - 0.26, lo.z + 0.002), Vector3(hi.x, hi.y - 0.06, hi.z + 0.002), band * 0.9)
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 72
	lab.font = ShopStyle.font(String(ident.get("face", ""))) if biz else EmpireStyle.font("black")
	lab.pixel_size = clampf((hi.x - lo.x) / 520.0, 0.0016, 0.0034)
	lab.shaded = false
	lab.double_sided = false
	lab.modulate = ink
	lab.outline_size = 0
	lab.position = Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y - 0.32) * 0.5, hi.z + 0.006)
	_static.add_child(lab)


func _promo_text(seed_x: float) -> String:
	var plist: Array = PROMOS_BY.get(type_id, PROMOS)
	return plist[absi(hash([unit.get("id", ""), seed_x])) % plist.size()]


static func _clock(h: float) -> String:
	var hr := int(h) % 24
	var mn := int(round((h - floorf(h)) * 60.0))
	var ap := "am" if hr < 12 else "pm"
	var h12 := hr % 12
	if h12 == 0:
		h12 = 12
	return ("%d%s" % [h12, ap]) if mn == 0 else ("%d:%02d%s" % [h12, mn, ap])


## Pavement height at room point (x, d), relative to the shop floor.
func _street_y(x: float, d: float) -> float:
	if not _ground_fn.is_valid():
		return -street_drop
	var w := transform * R(x, d, 0.0)
	return clampf(float(_ground_fn.call(w.x, w.z)) - transform.origin.y, -1.6, 0.0)


## What the shop puts in its window, behind the glass, by kind.
func _window_display(st: _Batch, spans: Array, gd: float) -> void:
	var xa := 0.0
	var xb := 0.0
	match type_id:
		"convenience":
			# Right window: a stepped stand of drinks, crisps and sweets.
			xa = door.y + 0.35
			xb = W - 1.0
		"bakery", "phones":
			xa = 1.0
			xb = door.x - 0.35
		_:
			return
	if xb - xa < 0.8:
		return
	var d0 := gd + 0.2
	var d1 := d0 + 0.5
	match type_id:
		"convenience":
			var stand := Color(0.95, 0.95, 0.94)
			st.box(R(xa, d0, 0.0), R(xb, d1, 0.4), stand)
			st.box(R(xa, d0 + 0.22, 0.4), R(xb, d1, 0.75), stand.darkened(0.04))
			st.box(R(xa, d0 - 0.005, 0.3), R(xb, d0, 0.38), brand)  # the brand's stripe
			var cols := [Color(0.8, 0.1, 0.12), Color(0.95, 0.78, 0.15), Color(0.42, 0.2, 0.55), Color(0.2, 0.5, 0.85),
				Color(0.2, 0.6, 0.3), Color(0.95, 0.5, 0.15)]
			var i := 0
			var x := xa + 0.06
			while x + 0.13 < xb:
				var c: Color = cols[(i + absi(String(unit.get("id", "")).hash())) % cols.size()]
				st.box(R(x, d0 + 0.04, 0.4), R(x + 0.12, d0 + 0.18, 0.4 + 0.16 + 0.04 * (i % 3)), c)
				st.cylinder(R(x + 0.06, d0 + 0.36, 0.75), 0.04, 0.24, cols[(i + 3) % cols.size()], 8)
				x += 0.16
				i += 1
		"bakery":
			var wood := Color(0.55, 0.38, 0.24)
			st.box(R(xa, d0, 0.0), R(xb, d1, 0.5), wood)
			st.box(R(xa + 0.1, d0 + 0.2, 0.5), R(xb - 0.1, d1, 0.85), wood.lightened(0.08))
			var x2 := xa + 0.12
			var k := 0
			while x2 + 0.26 < xb:
				var crust := Color(0.72, 0.45, 0.22).lerp(Color(0.85, 0.62, 0.35), float(k % 3) / 3.0)
				st.box(R(x2, d0 + 0.04, 0.5), R(x2 + 0.24, d0 + 0.18, 0.6), crust)
				st.box(R(x2 + 0.03, d0 + 0.06, 0.6), R(x2 + 0.21, d0 + 0.16, 0.64), crust.lightened(0.12))
				if x2 + 0.3 < xb - 0.1:
					st.box(R(x2 + 0.02, d0 + 0.26, 0.85), R(x2 + 0.26, d0 + 0.44, 0.93), Color(0.7, 0.55, 0.33))  # basket
					st.box(R(x2 + 0.05, d0 + 0.29, 0.93), R(x2 + 0.23, d0 + 0.41, 0.99), crust.darkened(0.1))
				x2 += 0.32
				k += 1
		"phones":
			st.box(R(xa, d0, 0.0), R(xb, d1, 0.75), Color(0.97, 0.97, 0.98))
			var x3 := xa + 0.15
			while x3 + 0.2 < xb:
				st.box(R(x3, d0 + 0.18, 0.75), R(x3 + 0.09, d0 + 0.24, 0.93), Color(0.08, 0.08, 0.1))
				_glow_quad(R(x3 + 0.008, d0 + 0.179, 0.765), R(x3 + 0.082, d0 + 0.179, 0.92), brand.lightened(0.35) * 0.9)
				x3 += 0.32
	_solid(R(xa, d0, 0.0), R(xb, d1, 0.8))


## On the pavement outside a trading shop: an A-board, planters by the door,
## a newspaper rack at a newsagent's, a café table, now and then a bike rack.
## All kept within ~1.3 m of the frontage and clear of the doorway.
func _street_dressing(st: _Batch, h: int, oh: float) -> void:
	var plants := type_id in ["cafe", "bakery", "clothing"] or h % 2 == 0
	var dark := brand.darkened(0.55)
	if plants:
		for side: float in [-1.0, 1.0]:
			var cx := (door.x - 0.85) if side < 0.0 else (door.y + 0.85)
			if cx - 0.3 < 0.4 or cx + 0.3 > W - 0.4:
				continue
			var y0 := _street_y(cx, -0.37)
			st.box(R(cx - 0.3, -0.62, y0 - 0.1), R(cx + 0.3, -0.12, y0 + 0.5), dark)
			st.box(R(cx - 0.32, -0.64, y0 + 0.46), R(cx + 0.32, -0.1, y0 + 0.52), dark.lightened(0.15))
			_batch_cone(st, R(cx, -0.37, y0 + 0.5), 0.3, 0.05, 0.95, Color(0.17, 0.36, 0.19))
			_solid(R(cx - 0.3, -0.62, y0), R(cx + 0.3, -0.12, y0 + 1.0))
	# The A-board, right of the door.
	var xa := door.y + (1.75 if plants else 1.15)
	if xa + 0.35 < W - 0.35:
		var y0 := _street_y(xa, -1.0)
		var frame := brand.darkened(0.25)
		var chalk := Color(0.1, 0.12, 0.11)
		for f: float in [-1.0, 1.0]:
			var df := -1.0 + 0.25 * f   # feet; the apex is at d −1.0
			st.sheet(R(xa - 0.3, df, y0), R(xa + 0.3, df, y0), R(xa + 0.3, -1.0, y0 + 0.95), R(xa - 0.3, -1.0, y0 + 0.95), frame)
			var k := 0.012 * f
			st.sheet(R(xa - 0.25, df * 0.97 + k - 0.03 * f, y0 + 0.08), R(xa + 0.25, df * 0.97 + k - 0.03 * f, y0 + 0.08),
				R(xa + 0.25, -1.0 + 0.04 * f + k, y0 + 0.86), R(xa - 0.25, -1.0 + 0.04 * f + k, y0 + 0.86), chalk)
		var lab := Label3D.new()
		lab.text = _aboard_text()
		lab.font = ShopStyle.font(String(ident.get("face", "")))
		lab.font_size = 64
		lab.pixel_size = 0.0021
		lab.line_spacing = -6.0
		lab.shaded = false
		lab.double_sided = false
		lab.outline_size = 0
		lab.modulate = Color(0.97, 0.96, 0.9)
		lab.position = R(xa, -1.13 - 0.02, y0 + 0.47)
		lab.rotation.x = -atan(0.25 / 0.95)
		_static.add_child(lab)
		_solid(R(xa - 0.32, -1.27, y0), R(xa + 0.32, -0.73, y0 + 0.95))
	# A newspaper rack outside a corner shop.
	if type_id == "convenience":
		var x1 := door.x - (1.3 if plants else 0.55)
		var x0 := x1 - 0.75
		if x0 > 0.45:
			var y0 := _street_y((x0 + x1) * 0.5, -0.3)
			var green := Color(0.12, 0.25, 0.18)
			st.box(R(x0, -0.5, y0), R(x1, -0.12, y0 + 0.62), green)
			for j in 3:
				var px := x0 + 0.04 + j * 0.24
				st.box(R(px, -0.46, y0 + 0.62), R(px + 0.2, -0.16, y0 + 0.68 + 0.02 * j),
					[Color(0.93, 0.93, 0.9), Color(0.96, 0.88, 0.55), Color(0.86, 0.9, 0.96)][j])
			st.box(R(x0, -0.16, y0 + 0.62), R(x1, -0.12, y0 + 1.05), green)
			var hl := Label3D.new()
			hl.text = "TODAY'S\nPAPERS"
			hl.font_size = 40
			hl.pixel_size = 0.0028
			hl.shaded = false
			hl.double_sided = false
			hl.outline_size = 0
			hl.modulate = Color(0.98, 0.94, 0.8)
			hl.position = R((x0 + x1) * 0.5, -0.165, y0 + 0.84)
			_static.add_child(hl)
			_solid(R(x0, -0.5, y0), R(x1, -0.12, y0 + 1.05))
	# A café table and two chairs in front of the left window.
	if type_id in ["cafe", "bakery"]:
		var tx := door.x - (2.15 if plants else 1.4)
		if tx - 0.75 > 0.4:
			var y0 := _street_y(tx, -0.85)
			var metal := Color(0.12, 0.12, 0.13)
			st.cylinder(R(tx, -0.85, y0), 0.22, 0.03, metal, 10)
			st.cylinder(R(tx, -0.85, y0), 0.03, 0.72, metal, 6)
			st.cylinder(R(tx, -0.85, y0 + 0.72), 0.32, 0.03, Color(0.9, 0.89, 0.86), 14)
			for cs: float in [-1.0, 1.0]:
				var cx := tx + cs * 0.55
				st.box(R(cx - 0.2, -1.05, y0 + 0.44), R(cx + 0.2, -0.65, y0 + 0.48), brand.darkened(0.1))
				for lx: float in [-0.17, 0.17]:
					for ld: float in [-1.02, -0.68]:
						st.box(R(cx + lx - 0.015, ld - 0.015, y0), R(cx + lx + 0.015, ld + 0.015, y0 + 0.44), metal)
				var bxx := cx + cs * 0.18
				st.box(R(bxx - 0.02, -1.05, y0 + 0.48), R(bxx + 0.02, -0.65, y0 + 0.85), brand.darkened(0.1))
			_solid(R(tx - 0.8, -1.1, y0), R(tx + 0.8, -0.6, y0 + 0.8))
	# Now and then a pair of Sheffield bike stands by the right pilaster.
	if h % 5 == 1:
		var steel := Color(0.25, 0.26, 0.28)
		for k in 2:
			var bx := W - 0.75 - k * 0.7
			if bx < xa + 0.6:
				break
			var y0 := _street_y(bx, -0.95)
			for e: float in [-1.3, -0.6]:
				st.box(R(bx - 0.025, e - 0.025, y0), R(bx + 0.025, e + 0.025, y0 + 0.8), steel)
			st.box(R(bx - 0.025, -1.3, y0 + 0.78), R(bx + 0.025, -0.6, y0 + 0.83), steel)
			_solid(R(bx - 0.05, -1.32, y0), R(bx + 0.05, -0.58, y0 + 0.83))


func _aboard_text() -> String:
	if not rival.is_empty() and not rival.get("firm", false):
		return "MEAL DEAL\n£3.50\nOPEN TILL 11"
	return {"convenience": "OPEN\nSNACKS\nDRINKS\nLOTTERY", "cafe": "COFFEE\n& CAKE\nCOME IN!", "bakery": "FRESH\nBREAD\nDAILY",
		"takeaway": "HOT FOOD\nOPEN\nLATE", "clothing": "NEW IN\nSALE\nINSIDE", "phones": "REPAIRS\nWHILE YOU\nWAIT"}.get(type_id, "OPEN")


var _shutter: MeshInstance3D


## A roller shutter: its box under the fascia and guide rails always, the
## slatted curtain (its own mesh) only while the shop is shut at night.
func _shutters(st: _Batch, oh: float, sf: Dictionary) -> void:
	var sc: Color = sf["shutter_col"]
	st.box(R(ox.x - 0.02, -0.28, oh - 0.04), R(ox.y + 0.02, -0.02, oh + 0.15), sc.darkened(0.1))
	for gx: float in [ox.x - 0.02, ox.y - 0.06]:
		st.box(R(gx, -0.12, 0.0), R(gx + 0.08, -0.02, oh - 0.04), sc.darkened(0.2))
	var cb := _Batch.new()
	var y := 0.0
	var i := 0
	while y < oh - 0.05:
		var c := sc if i % 2 == 0 else sc.darkened(0.14)
		cb.box(R(ox.x + 0.04, -0.1, y), R(ox.y - 0.04, -0.06, minf(y + 0.095, oh - 0.04)), c)
		y += 0.1
		i += 1
	cb.box(R(ox.x + 0.04, -0.12, 0.0), R(ox.y - 0.04, -0.05, 0.07), sc.darkened(0.35))  # bottom rail
	_shutter = MeshInstance3D.new()
	_shutter.name = "Shutter"
	_shutter.mesh = cb.commit()
	_shutter.material_override = _mat("vc")
	_shutter.visibility_range_end = 260.0
	_shutter.visible = false
	_static.add_child(_shutter)


## An empty unit: what the last tenant left (an old shelf, dust sheets, a
## ladder, paint tins), post on the mat, and a letting agent's board.
func _vacant(st: _Batch, fy: float) -> void:
	var part_d := D - BACKROOM
	var grey := Color(0.5, 0.52, 0.54)
	# An old shelf unit on the left wall.
	st.box(R(0.05, 1.8, 0.0), R(0.5, 3.6, 0.12), grey.darkened(0.3))
	st.box(R(0.05, 1.8, 0.0), R(0.1, 3.6, 1.5), grey)
	for y: float in [0.55, 1.0, 1.45]:
		st.box(R(0.1, 1.8, y - 0.03), R(0.5, 3.6, y), grey.lightened(0.15))
	_solid(R(0.05, 1.8, 0.0), R(0.5, 3.6, 1.5))
	# Dust sheets over whatever's stacked at the back.
	var sheet := Color(0.88, 0.87, 0.83)
	var bx := W * 0.42
	if part_d > 4.0:
		st.box(R(bx, part_d - 2.0, 0.0), R(bx + 1.3, part_d - 0.9, 0.7), sheet)
		st.box(R(bx + 0.15, part_d - 1.85, 0.7), R(bx + 0.9, part_d - 1.1, 1.05), sheet.darkened(0.04))
		st.box(R(bx - 0.08, part_d - 2.05, 0.0), R(bx + 1.38, part_d - 0.85, 0.08), sheet.darkened(0.08))
		_solid(R(bx, part_d - 2.0, 0.0), R(bx + 1.3, part_d - 0.9, 1.05))
	# A stepladder and paint tins mid-floor.
	var lx := W * 0.3
	var ld := part_d * 0.55
	var alu := Color(0.75, 0.76, 0.78)
	for f: float in [-1.0, 1.0]:
		for e: float in [-0.22, 0.22]:
			st.sheet(R(lx + e - 0.02, ld + 0.35 * f, 0.0), R(lx + e + 0.02, ld + 0.35 * f, 0.0),
				R(lx + e + 0.02, ld + 0.05 * f, 1.6), R(lx + e - 0.02, ld + 0.05 * f, 1.6), alu)
	for r in 4:
		var ry := 0.35 + r * 0.38
		var rd := ld - 0.35 + 0.3 * (ry / 1.6)
		st.box(R(lx - 0.22, rd - 0.03, ry), R(lx + 0.22, rd + 0.03, ry + 0.03), alu)
	st.box(R(lx - 0.24, ld - 0.08, 1.6), R(lx + 0.24, ld + 0.08, 1.65), Color(0.85, 0.2, 0.15))
	for t in 3:
		st.cylinder(R(lx + 0.6 + t * 0.26, ld + 0.1 * t, 0.0), 0.1, 0.22, [Color(0.85, 0.85, 0.82), Color(0.3, 0.45, 0.6), Color(0.9, 0.8, 0.5)][t], 10)
	_solid(R(lx - 0.3, ld - 0.4, 0.0), R(lx + 0.3, ld + 0.4, 1.65))
	# Post and flyers on the floor behind the door.
	var mid := (door.x + door.y) * 0.5
	for k in 7:
		var px := mid - 0.6 + fmod(k * 0.37, 1.2)
		var pdd := 0.9 + fmod(k * 0.23, 0.55)
		st.box(R(px, pdd, 0.03), R(px + 0.22, pdd + 0.16, 0.035), [Color(0.97, 0.97, 0.95), Color(0.95, 0.85, 0.5), Color(0.85, 0.9, 0.97)][k % 3])
	# The letting agent's board, projecting from the wall over the fascia.
	var vx := W - 0.9
	st.box(R(vx - 0.02, -1.05, fy + 1.62), R(vx + 0.02, -0.02, fy + 1.67), Color(0.15, 0.15, 0.16))  # bracket
	st.box(R(vx - 0.03, -1.0, fy + 0.95), R(vx + 0.03, -0.2, fy + 1.58), Color(0.98, 0.98, 0.96))
	st.box(R(vx - 0.035, -1.0, fy + 0.95), R(vx + 0.035, -0.2, fy + 1.1), Color(0.75, 0.1, 0.12))
	for side: float in [1.0, -1.0]:
		var t1 := Label3D.new()
		t1.text = "TO LET"
		t1.font = EmpireStyle.font("black")
		t1.font_size = 96
		t1.pixel_size = 0.0026
		t1.shaded = false
		t1.double_sided = false
		t1.outline_size = 0
		t1.modulate = Color(0.75, 0.08, 0.1)
		t1.position = R(vx + 0.036 * side, -0.6, fy + 1.37)
		t1.rotation.y = PI * 0.5 * side
		_static.add_child(t1)
		var t2 := t1.duplicate() as Label3D
		t2.text = "CITY LETTINGS"
		t2.font_size = 40
		t2.modulate = Color(1, 1, 1)
		t2.position = R(vx + 0.037 * side, -0.6, fy + 1.025)
		_static.add_child(t2)


func _sign_text() -> String:
	if biz:
		# (Script faces read best as written; the rest in capitals.)
		return biz.name if String(ident.get("face", "")) in ["script", "retro"] else biz.name.to_upper()
	return "TO LET" if kind == "shop" else String(unit.get("name", "")).to_upper()


## `night`: the street's shut for the night (other people's shops with a
## roller shutter pull it down then).
func update_signs(trading: bool, night := false) -> void:
	if _shutter:
		_shutter.visible = night and not trading
	if _sign:
		_sign.text = _sign_text()
	if _open_sign:
		if rival.get("for_sale", false):
			_open_sign.text = "FOR SALE\n%s" % EmpireData.money(CityLife.firm_price(rival))
			_open_sign.modulate = Color(1.0, 0.85, 0.3)
		elif not rival.is_empty():
			_open_sign.text = "OPEN" if trading else "CLOSED"
			_open_sign.modulate = Color(1.0, 0.95, 0.9)
		elif biz == null:
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
	for k in ["fridge", "coffee", "hotcab", "cake", "pickmix", "techtable", "table", "rail", "shelf"]:
		for u in int(biz.fixtures.get(k, 0)):
			want.append([k, u])
	var back_sites := sites.filter(func(s): return s["wall"] == "back")
	var mid_sites := sites.filter(func(s): return s["wall"] == "gondola")
	var left_sites := sites.filter(func(s): return s["wall"] == "left")
	_mid_used = false
	for w in want:
		var site: Dictionary
		var k: String = w[0]
		if k in ["fridge", "coffee", "hotcab", "cake"] and not back_sites.is_empty():
			site = back_sites.pop_front()
		elif k in ["table", "techtable"] and not mid_sites.is_empty():
			site = mid_sites.pop_front()
			_mid_used = true
		elif k in ["rail", "shelf"] and not left_sites.is_empty():
			site = left_sites.pop_front()
		elif type_id == "convenience" and not mid_sites.is_empty():
			site = mid_sites.pop_front()
			_mid_used = true
		elif not left_sites.is_empty():
			site = left_sites.pop_front()
		elif not back_sites.is_empty():
			site = back_sites.pop_front()
		elif not mid_sites.is_empty():
			site = mid_sites.pop_front()
			_mid_used = true
		else:
			push_warning("ShopInterior: no room for a %s in %s" % [w[0], unit.get("id")])
			continue
		_fixture(st, String(w[0]), int(w[1]), site)


func _fixture(st: _Batch, k: String, u: int, site: Dictionary) -> void:
	var al: Vector3 = site["along"]
	var out: Vector3 = site["out"]
	var dep := FRIDGE_D if k == "fridge" else (0.75 if k == "pickmix" else ({"rail": 0.6, "table": 0.9, "cake": 0.75,
		"hotcab": 0.75, "techtable": 0.95}.get(k, SHELF_D) as float))
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
		"rail":
			# A chrome clothes rail: two uprights, the bar, a base rail.
			var steel := Color(0.78, 0.79, 0.8)
			var r0 := o - out * dep * 0.5
			for e2: float in [0.03, BAY - 0.03]:
				var up := r0 + al * e2
				st.box(up - Vector3(0.02, 0, 0.02), up + Vector3(0.02, 1.62, 0.02), steel)
				st.box(up - Vector3(0.025, 0, 0.025) - out * 0.22, up + Vector3(0.025, 0.04, 0.025) + out * 0.22, steel.darkened(0.3))
			var b0 := r0 + Vector3.UP * 1.58
			var b1 := r0 + al * BAY + Vector3.UP * 1.62
			st.box(b0.min(b1) - Vector3(0.012, 0, 0.012), b0.max(b1) + Vector3(0.012, 0, 0.012), steel)
			tall = 1.65
		"table":
			# A low timber display table for folded stock.
			var wood := Color(0.62, 0.45, 0.3)
			st.box(Vector3(lo.x, 0.74, lo.z), Vector3(hi.x, 0.8, hi.z), wood)
			for cx in [0.08, BAY - 0.08]:
				for cz in [0.08, dep - 0.08]:
					var lp: Vector3 = o + al * float(cx) - out * float(cz)
					st.box(lp - Vector3(0.03, 0, 0.03), lp + Vector3(0.03, 0.74, 0.03), wood.darkened(0.35))
			tall = 0.8
		"cake":
			# A glass-fronted display counter, lit inside.
			st.box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, 0.86, hi.z), Color(0.92, 0.9, 0.86) if type_id != "cafe" else brand.darkened(0.25))
			st.box(Vector3(lo.x, 0.86, lo.z), Vector3(hi.x, 0.9, hi.z), Color(0.35, 0.3, 0.26))
			st.box(Vector3(lo.x, 1.42, lo.z), Vector3(hi.x, 1.46, hi.z), Color(0.35, 0.3, 0.26))
			var gm := o + Vector3.UP * 0.9
			_glass_box(gm.min(gm + al * BAY - out * dep), (gm + al * BAY).max(gm - out * dep) + Vector3.UP * 0.52)
			_glow_quad(Vector3(lo.x + 0.05, 1.415, lo.z + 0.05), Vector3(hi.x - 0.05, 1.415, hi.z - 0.05), Color(1.0, 0.93, 0.8) * 1.3, true)
			tall = 1.46
		"hotcab":
			# Stainless heated cabinet on a counter, glowing orange inside.
			var ss := Color(0.74, 0.75, 0.77)
			st.box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, 0.9, hi.z), ss.darkened(0.15))
			st.box(Vector3(lo.x, 0.9, lo.z), Vector3(hi.x, 0.95, hi.z), ss)
			st.box(Vector3(lo.x, 1.45, lo.z), Vector3(hi.x, 1.5, hi.z), ss)
			var hm := o + Vector3.UP * 0.95
			_glass_box(hm.min(hm + al * BAY - out * dep), (hm + al * BAY).max(hm - out * dep) + Vector3.UP * 0.5)
			_glow_quad(Vector3(lo.x + 0.05, 1.44, lo.z + 0.05), Vector3(hi.x - 0.05, 1.44, hi.z - 0.05), Color(1.0, 0.55, 0.2) * 1.6, true)
			# Extraction hood over it.
			var hd0 := o - out * dep + Vector3.UP * 2.35
			st.box(hd0.min(hd0 + al * BAY + out * 0.55), hd0.max(hd0 + al * BAY + out * 0.55) + Vector3.UP * 0.35, ss)
			tall = 1.5
		"techtable":
			# A white demo table with devices laid out.
			st.box(Vector3(lo.x, 0.82, lo.z), Vector3(hi.x, 0.9, hi.z), Color(0.97, 0.97, 0.98))
			st.box(Vector3(lo.x + 0.2, 0.0, lo.z + 0.2), Vector3(hi.x - 0.2, 0.82, hi.z - 0.2), Color(0.9, 0.9, 0.92))
			_glow_quad(Vector3(lo.x + 0.02, 0.81, lo.z + 0.02), Vector3(hi.x - 0.02, 0.81, hi.z - 0.02), brand.lightened(0.3) * 0.8, true)
			tall = 0.9
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
			st.box(back0 + Vector3.UP * (tall - 0.02) + out * 0.02, back0 + al * BAY + out * 0.06 + Vector3.UP * (tall + 0.22), brand)
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
			"rail":
				a0 = 0.08 + j * (BAY * 0.5)
				wdt = BAY * 0.5 - 0.12
				y = 1.58
			"table":
				a0 = 0.08 + j * (BAY * 0.5)
				wdt = BAY * 0.5 - 0.12
				y = 0.8
			"cake", "techtable":
				a0 = 0.06 + j * (BAY / 3.0)
				wdt = BAY / 3.0 - 0.1
				y = 0.9
			"hotcab":
				a0 = 0.06 + j * (BAY * 0.5)
				wdt = BAY * 0.5 - 0.1
				y = 0.95
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
	# Cases put down on the shop floor, stacked by the door.
	if biz and biz.floor_pile and not biz.floor_pile.is_empty():
		var pl: Array = []
		for pid in biz.floor_pile.units:
			for c in Stock.cases_for(pid, biz.floor_pile.qty(pid)):
				pl.append(pid)
		var mm3 := MultiMesh.new()
		mm3.transform_format = MultiMesh.TRANSFORM_3D
		mm3.use_colors = true
		mm3.mesh = shape_mesh("case")
		mm3.instance_count = mini(pl.size(), 24)
		for i in mm3.instance_count:
			var col := i % 2
			var row := (i / 2) % 2
			var lvl := i / 4
			var p3 := pile_pos + Vector3(-0.27 + col * 0.54, 0.2 + lvl * 0.4, -0.2 - row * 0.4)
			mm3.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.04 * float((i * 7) % 5 - 2)), p3))
			mm3.set_instance_color(i, EmpireData.colour(pl[i]).lerp(Color(0.72, 0.56, 0.36), 0.55))
		var mi3 := MultiMeshInstance3D.new()
		mi3.multimesh = mm3
		mi3.material_override = _mat("goods")
		_goods.add_child(mi3)
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
	if shape == "garment":
		_hanging_goods(si, s, by_shape, sb, sz)
		return
	var across := maxi(int(wdt / (sz.x + 0.015)), 1)
	var rows := maxi(int(minf(dep, 0.5) / (sz.z + 0.02)), 1)
	var stack := 2 if shape in ["can", "bar", "box"] and s["fixture"] != "coffee" else 1
	if shape == "folded":
		stack = 5
	elif shape == "shoebox":
		stack = 2
	elif s["fixture"] in ["cake", "hotcab", "techtable"]:
		stack = 1
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


## Clothes on a rail: side by side along it, hanging from the bar.
func _hanging_goods(si: int, s: Dictionary, by_shape: Dictionary, sb: Array, sz: Vector3) -> void:
	var o: Vector3 = sb[0]
	var al: Vector3 = sb[1]
	var out: Vector3 = sb[2]
	var wdt: float = sb[3]
	var y: float = sb[4]
	var dep: float = sb[5]
	var n := maxi(int(wdt / 0.075), 1)
	var vis := clampi(int(ceil(float(s["qty"]) / float(s["cap"]) * n)), 1, n)
	var col := EmpireData.colour(String(s["product"]))
	var b := Basis.looking_at(al, Vector3.UP)  # (the garment's flat side along the rail)
	var mid := o - out * (dep * 0.5 + 0.05)
	if not by_shape.has("garment"):
		by_shape["garment"] = []
	for i in vis:
		var p := mid + al * ((i + 0.5) * wdt / n) + Vector3.UP * (y + 0.02 - sz.y * 0.5)
		var tint := col * (1.0 - 0.07 * float(i % 3))
		by_shape["garment"].append([Transform3D(b, p), Color(tint.r, tint.g, tint.b, 1.0)])


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
		"garment": return Vector3(0.44, 0.66, 0.05)
		"folded": return Vector3(0.28, 0.06, 0.24)
		"shoebox": return Vector3(0.32, 0.12, 0.2)
		"pastry": return Vector3(0.13, 0.06, 0.09)
		"cake": return Vector3(0.11, 0.08, 0.11)
		"foodbox": return Vector3(0.16, 0.08, 0.12)
		"phone": return Vector3(0.075, 0.012, 0.15)
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
		"garment":
			# On a hanger: shoulders and body, sleeves, a hook.
			b.box(Vector3(-h.x * 0.62, -h.y, -h.z), Vector3(h.x * 0.62, h.y - 0.04, h.z), Color.WHITE)
			b.box(Vector3(-h.x, h.y - 0.3, -h.z * 0.8), Vector3(h.x, h.y - 0.04, h.z * 0.8), Color(0.94, 0.94, 0.94))
			b.box(Vector3(-0.1, h.y - 0.05, -0.005), Vector3(0.1, h.y - 0.03, 0.005), Color(0.3, 0.22, 0.15))
			b.box(Vector3(-0.005, h.y - 0.03, -0.005), Vector3(0.005, h.y + 0.04, 0.005), Color(0.7, 0.7, 0.72))
		"folded":
			b.box(-h, h, Color.WHITE)
			b.box(Vector3(-h.x, -h.y * 0.2, -h.z - 0.002), Vector3(h.x, h.y * 0.2, -h.z + 0.01), Color(0.88, 0.88, 0.88))
		"shoebox":
			b.box(-h, h, Color.WHITE)
			b.box(Vector3(-h.x - 0.003, h.y - 0.035, -h.z - 0.003), Vector3(h.x + 0.003, h.y + 0.003, h.z + 0.003), Color(0.25, 0.25, 0.27))
		"pastry", "cake":
			b.cylinder(Vector3(0, -h.y, 0), h.x, sz.y, Color.WHITE, 10)
			b.cylinder(Vector3(0, h.y - 0.012, 0), h.x * 0.92, 0.014, Color(0.96, 0.92, 0.85), 10)
		"foodbox":
			b.box(-h, h, Color(0.97, 0.96, 0.94))
			b.box(Vector3(-h.x - 0.002, -h.y * 0.4, -h.z - 0.002), Vector3(h.x + 0.002, h.y * 0.3, h.z + 0.002), Color.WHITE)
		"phone":
			b.box(-h, h, Color.WHITE)
			b.box(Vector3(-h.x * 0.88, h.y, -h.z * 0.9), Vector3(h.x * 0.88, h.y + 0.002, h.z * 0.9), Color(0.05, 0.06, 0.08))
		_:
			b.box(-h, h, Color.WHITE)
			b.box(Vector3(-h.x * 0.8, -h.y * 0.2, h.z - 0.004), Vector3(h.x * 0.8, h.y * 0.45, h.z + 0.002), Color(0.95, 0.95, 0.95))
	var m := b.commit()
	_shape_meshes[shape] = m
	return m


# ------------------------------------------------------------ dressing
var _glass: _Batch


## A transparent box (display counters, hot cabinets): one mesh per room.
func _glass_box(lo: Vector3, hi: Vector3) -> void:
	if _glass == null:
		_glass = _Batch.new()
	_glass.box(lo, hi, Color(0.75, 0.85, 0.9, 0.16))


func _ceiling_lights(st: _Batch, part_d: float, tint: Color) -> void:
	var kind_l := String(look.get("lights", "grid"))
	match kind_l:
		"pendant":
			# Rows of pendant shades on cords, warm pools of light.
			for ix in 3:
				for iz in 2:
					var px := W * (0.2 + 0.3 * ix)
					var pd := part_d * (0.3 + 0.4 * iz)
					var drop := 1.15
					st.box(R(px - 0.008, pd - 0.008, H - drop + 0.2), R(px + 0.008, pd + 0.008, H), Color(0.1, 0.1, 0.1))
					var shade := ident.get("accent", Color(0.15, 0.15, 0.16)) as Color if type_id == "bakery" else Color(0.12, 0.12, 0.13)
					_batch_cone(st, R(px, pd, H - drop), 0.24, 0.07, 0.22, shade)
					_glow_quad(R(px - 0.12, pd - 0.12, H - drop - 0.005), R(px + 0.12, pd + 0.12, H - drop - 0.005), tint * 1.6, true)
		"track":
			# Black track runs with spot heads aimed at the rails.
			for tx: float in [W * 0.3, W * 0.68]:
				st.box(R(tx - 0.02, 0.6, H - 0.06), R(tx + 0.02, part_d - 0.4, H - 0.01), Color(0.08, 0.08, 0.09))
				var dd := 0.9
				while dd < part_d - 0.5:
					st.box(R(tx - 0.05, dd - 0.05, H - 0.24), R(tx + 0.05, dd + 0.05, H - 0.06), Color(0.1, 0.1, 0.11))
					_glow_quad(R(tx - 0.04, dd - 0.04, H - 0.245), R(tx + 0.04, dd + 0.04, H - 0.245), tint * 2.0, true)
					dd += 1.1
		"linear":
			for lx: float in [W * 0.25, W * 0.5, W * 0.75]:
				_glow_quad(R(lx - 0.04, 0.5, H - 0.02), R(lx + 0.04, part_d - 0.4, H - 0.02), tint * 1.5, true)
		"panel":
			for ix in 3:
				for iz in 2:
					var px2 := W * (0.2 + 0.3 * ix)
					var pd2 := part_d * (0.28 + 0.44 * iz)
					_glow_quad(R(px2 - 0.45, pd2 - 0.45, H - 0.02), R(px2 + 0.45, pd2 + 0.45, H - 0.02), tint * 1.1, true)
		_:
			for ix in 2:
				for iz in 2:
					var px3 := W * (0.28 + 0.44 * ix)
					var pd3 := part_d * (0.28 + 0.44 * iz)
					_glow_quad(R(px3 - 0.6, pd3 - 0.25, H - 0.02), R(px3 + 0.6, pd3 + 0.25, H - 0.02), tint * 0.95, true)


## A cone (lamp shade) in room space: base radius r0 at the bottom, r1 at the top.
func _batch_cone(st: _Batch, base: Vector3, r0: float, r1: float, h: float, c: Color) -> void:
	var seg := 10
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var q0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var q1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		st.sheet(p0, p1, q1, q0, c)


## Café, takeaway, bakery, clothes and phone shops: a feature wall, a menu
## board or a mirror, and the spare floor dressed for the trade.
func _decor_trade(st: _Batch, part_d: float, cx0: float, cd0: float, cd1: float) -> void:
	var accent: Color = ident.get("accent", Color(0.95, 0.92, 0.85))
	# Feature wall behind the counter in the brand colour, a band under the ceiling.
	st.box(R(W - 0.05, 0.4, 0.0), R(W - 0.03, part_d - 0.1, H - 0.4), brand.darkened(0.1))
	st.box(R(0.03, 0.3, H - 0.55), R(0.06, part_d, H - 0.42), brand)
	if look.get("tiles", false):
		# White metro tiles to 1.4 m on the left wall: a pale band with grout lines.
		st.box(R(0.03, 0.3, 0.1), R(0.055, part_d, 1.4), Color(0.97, 0.97, 0.96))
		var ty := 0.25
		while ty < 1.4:
			st.box(R(0.055, 0.3, ty), R(0.058, part_d, ty + 0.012), Color(0.82, 0.82, 0.8))
			ty += 0.15
	elif look.get("dado", false):
		st.box(R(0.03, 0.3, 0.1), R(0.05, part_d, 1.0), brand.lerp(Color(0.95, 0.93, 0.9), 0.55))
		st.box(R(0.05, 0.3, 1.0), R(0.06, part_d, 1.05), Color(0.9, 0.88, 0.84))
	# Entrance mat in the brand colour.
	var mid := (door.x + door.y) * 0.5
	st.box(R(mid - 0.9, 0.32, 0.0), R(mid + 0.9, 1.4, 0.018), Color(0.14, 0.14, 0.15))
	st.box(R(mid - 0.75, 0.42, 0.018), R(mid + 0.75, 1.3, 0.022), brand.darkened(0.2))
	var decor := String(look.get("decor", ""))
	if decor in ["seating", "stools"]:
		_menu_board(st, part_d)
	# The middle of the floor, if the fixtures left it free.
	var gx0 := 1.95
	var gx1 := W - 3.7
	var free_mid := not _mid_used and gx1 - gx0 >= 1.0
	match decor:
		"seating":
			if free_mid:
				var dd := 2.4
				while dd + 1.2 < part_d - 1.2:
					_cafe_table(st, R((gx0 + gx1) * 0.5, dd + 0.6, 0.0), accent)
					dd += 1.9
			_window_bar(st, accent)
		"stools":
			_window_bar(st, accent)
			if free_mid:
				var dd2 := 2.4
				while dd2 + 1.2 < part_d - 1.2:
					_cafe_table(st, R((gx0 + gx1) * 0.5, dd2 + 0.6, 0.0), Color(0.85, 0.85, 0.86))
					dd2 += 1.9
		"boutique":
			# Mannequins in the window, a mirror, a rug.
			_mannequin(st, R(door.y + 0.9, 0.75, 0.0))
			if door.x - 0.9 > 0.6:
				_mannequin(st, R(door.x - 0.9, 0.75, 0.0))
			st.box(R(0.06, part_d - 2.6, 0.2), R(0.08, part_d - 1.6, 2.3), Color(0.75, 0.82, 0.86))
			st.box(R(0.055, part_d - 2.65, 0.15), R(0.075, part_d - 1.55, 2.35), Color(0.75, 0.62, 0.35))
			st.box(R(gx0 - 0.3, 1.6, 0.0), R(gx1 + 0.3, part_d - 1.4, 0.015), brand.lerp(Color(0.9, 0.86, 0.8), 0.5))
		"plinths":
			# White plinths with a hero device on each, a big brand screen.
			var px := door.y + 0.9
			if px < W - 2.8:
				st.box(R(px - 0.3, 0.6, 0.0), R(px + 0.3, 1.2, 1.0), Color(0.97, 0.97, 0.98))
				st.box(R(px - 0.08, 0.84, 1.0), R(px + 0.08, 0.96, 1.25), Color(0.1, 0.1, 0.12))
				_solid(R(px - 0.3, 0.6, 0.0), R(px + 0.3, 1.2, 1.0))
			_glow_quad(R(0.07, part_d - 2.8, 1.2), R(0.07, part_d - 0.6, 2.5), brand.lightened(0.15) * 1.1)
	# A tall plant by the window.
	if decor != "stools":
		var pxp := 0.55
		st.box(R(pxp - 0.2, 0.4, 0.0), R(pxp + 0.2, 0.8, 0.42), accent.darkened(0.3))
		st.box(R(pxp - 0.32, 0.28, 0.42), R(pxp + 0.32, 0.92, 1.25), Color(0.2, 0.45, 0.22))
		st.box(R(pxp - 0.2, 0.4, 1.25), R(pxp + 0.2, 0.8, 1.6), Color(0.25, 0.52, 0.25))
		_solid(R(pxp - 0.32, 0.28, 0.0), R(pxp + 0.32, 0.92, 1.0))
	# Card machine sign over the counter.
	var hd := (cd0 + cd1) * 0.5
	st.box(R(cx0 - 0.1, hd - 0.6, 2.8), R(cx0 - 0.04, hd + 0.6, 3.15), brand)
	for e: float in [-0.45, 0.45]:
		st.box(R(cx0 - 0.08, hd + e - 0.01, 3.15), R(cx0 - 0.06, hd + e + 0.01, H), Color(0.3, 0.3, 0.32))
	var lab := Label3D.new()
	lab.text = {"cafe": "ORDER HERE", "takeaway": "ORDER & COLLECT", "bakery": "PAY HERE", "clothing": "TILLS", "phones": "PAY & COLLECT"}.get(type_id, "PAY HERE")
	lab.font = ShopStyle.font(String(ident.get("face", "")))
	lab.font_size = 52
	lab.pixel_size = 0.0036
	lab.outline_size = 0
	lab.shaded = false
	lab.modulate = accent
	lab.position = R(cx0 - 0.115, hd, 2.975)
	lab.rotation.y = -PI * 0.5
	_static.add_child(lab)


## A menu board over the back counter: the shop's products and prices.
func _menu_board(st: _Batch, part_d: float) -> void:
	var x0 := 0.5
	var x1 := minf(W - 2.8, x0 + 4.2)
	if x1 - x0 < 1.5:
		return
	var neon := type_id == "takeaway"
	st.box(R(x0, part_d - 0.06, 2.3), R(x1, part_d - 0.02, 3.35), Color(0.08, 0.08, 0.09) if not neon else brand.darkened(0.55))
	if neon:
		# Backlit picture panels of the food.
		var n := 3
		for i in n:
			var a := lerpf(x0 + 0.1, x1 - 0.1, float(i) / n)
			var b := lerpf(x0 + 0.1, x1 - 0.1, float(i + 1) / n) - 0.08
			_glow_quad(R(a, part_d - 0.065, 2.85), R(b, part_d - 0.065, 3.28), [Color(1.0, 0.75, 0.3), Color(0.95, 0.45, 0.25), Color(1.0, 0.9, 0.6)][i] * 1.2)
	var lines: Array = []
	var seen := {}
	if biz:
		for sl: Dictionary in biz.slots:
			var pid := String(sl["product"])
			if pid == "" or seen.has(pid):
				continue
			seen[pid] = true
			lines.append("%s  %s" % [String(EmpireData.product(pid)["name"]), EmpireData.money(biz.price(pid), true)])
	var menu := Label3D.new()
	menu.text = "\n".join(lines.slice(0, 6))
	menu.font = ShopStyle.font("condensed")
	menu.font_size = 64
	menu.pixel_size = 0.0042
	menu.shaded = false
	menu.modulate = Color(0.97, 0.95, 0.88)
	menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu.position = R((x0 + x1) * 0.5, part_d - 0.07, 2.62 if neon else 2.85)
	menu.rotation.y = 0.0  # (faces into the shop)
	_static.add_child(menu)


func _cafe_table(st: _Batch, c: Vector3, accent: Color) -> void:
	var top := Color(0.55, 0.38, 0.24) if type_id != "takeaway" else Color(0.92, 0.92, 0.93)
	st.cylinder(c, 0.38, 0.74, top.darkened(0.45), 12)
	st.cylinder(c + Vector3.UP * 0.72, 0.42, 0.04, top, 14)
	for sx: float in [-0.62, 0.62]:
		var cp := c + Vector3(sx, 0, 0)
		st.box(cp + Vector3(-0.2, 0.44, -0.2), cp + Vector3(0.2, 0.48, 0.2), accent.darkened(0.2))
		for lx: float in [-0.17, 0.17]:
			for lz: float in [-0.17, 0.17]:
				st.box(cp + Vector3(lx - 0.015, 0, lz - 0.015), cp + Vector3(lx + 0.015, 0.44, lz + 0.015), Color(0.15, 0.15, 0.16))
		var back := cp + Vector3(signf(sx) * 0.19, 0.48, 0)
		st.box(back + Vector3(-0.02, 0, -0.19), back + Vector3(0.02, 0.42, 0.19), accent.darkened(0.2))
	_solid(c + Vector3(-0.85, 0, -0.42), c + Vector3(0.85, 0.75, 0.42))


## A bar along the front window with stools.
func _window_bar(st: _Batch, accent: Color) -> void:
	var x0 := door.y + 0.3
	var x1 := W - 0.4
	if x1 - x0 < 1.2:
		return
	st.box(R(x0, 0.25, 1.02), R(x1, 0.7, 1.07), Color(0.55, 0.38, 0.24) if type_id != "takeaway" else Color(0.9, 0.9, 0.91))
	for bx: float in [x0 + 0.1, x1 - 0.1]:
		st.box(R(bx - 0.03, 0.4, 0.0), R(bx + 0.03, 0.55, 1.02), Color(0.15, 0.15, 0.16))
	var sx := x0 + 0.4
	while sx < x1 - 0.3:
		st.cylinder(R(sx, 1.0, 0.0), 0.025, 0.72, Color(0.15, 0.15, 0.16), 6)
		st.cylinder(R(sx, 1.0, 0.72), 0.18, 0.06, accent.darkened(0.15), 10)
		sx += 0.7
	_solid(R(x0, 0.25, 0.0), R(x1, 0.7, 1.07))


## A shop-window mannequin in an outfit of the brand's colours.
func _mannequin(st: _Batch, p: Vector3) -> void:
	var skin := Color(0.92, 0.92, 0.9)
	var outfit: Color = brand.lerp(Color(0.95, 0.93, 0.9), 0.15)
	st.cylinder(p, 0.18, 0.03, Color(0.2, 0.2, 0.22), 10)
	st.cylinder(p, 0.02, 0.8, Color(0.6, 0.6, 0.62), 6)
	st.box(p + Vector3(-0.17, 0.8, -0.1), p + Vector3(0.17, 1.05, 0.1), Color(0.18, 0.2, 0.28))
	st.box(p + Vector3(-0.19, 1.05, -0.11), p + Vector3(0.19, 1.5, 0.11), outfit)
	st.box(p + Vector3(-0.24, 1.15, -0.06), p + Vector3(-0.19, 1.48, 0.06), outfit)
	st.box(p + Vector3(0.19, 1.15, -0.06), p + Vector3(0.24, 1.48, 0.06), outfit)
	st.cylinder(p + Vector3(0, 1.5, 0), 0.045, 0.08, skin, 8)
	st.box(p + Vector3(-0.08, 1.58, -0.09), p + Vector3(0.08, 1.8, 0.09), skin)
	_solid(p + Vector3(-0.25, 0, -0.2), p + Vector3(0.25, 1.8, 0.2))


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
	# (Someone else's shop: only lit up close, there are dozens of them.)
	o.distance_fade_begin = 90.0 if rival.is_empty() else 35.0
	o.distance_fade_length = 30.0 if rival.is_empty() else 10.0
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
	if not rival.is_empty():
		return out
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

	## A thin two-sided quad (awning cloth): a→b→c→d round its edge.
	func sheet(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		var nrm := (b - a).cross(d - a).normalized()
		_quad(a, b, c, d, nrm, col)
		_quad(d, c, b, a, -nrm, col)

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
