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
var _room_probe: ReflectionProbe
var _goods: Node3D
var _labels: Node3D
var _headers: Array = []     # shelf header Label3Ds (meta "fixture" = [kind, unit])
var _dirt: MeshInstance3D
var _sign: Label3D
var _sign_light: OmniLight3D
var _sales_lights: Array[Light3D] = []
var _trade_glow: MeshInstance3D
var _trade_board: Label3D
var _front_seed := 0
var _lighting_open := true
var _lights_active := true
var _delivery_worker: ShopPerson
var _delivery_truck: Node3D
var _delivery_phase := 0
var _delivery_wait := 0.0
var _delivery_start := Vector3.ZERO
var _open_sign: Label3D
var _col: StaticBody3D
var _cases_mm: MultiMeshInstance3D
static var _mat_cache := {}
static var _shape_meshes := {}


## Metres the room sits above its unit's floor level (the terrain under some
## lots comes up to a kerb's height over it): set by the game from the ground.
var lift := 0.0
var public_display := false
var _public_visitor: ShopPerson
var _public_wait := 0.0
var _public_stop := 0
var _ground_fn := Callable()
## An office tower's lobby: your company there ({} = floors to let).
var office := {}


func setup(p_unit: Dictionary, p_biz: Business, ground_fn := Callable(), p_rival := {}) -> void:
	_ground_fn = ground_fn
	unit = p_unit
	_front_seed = absi(String(unit.get("id", "")).hash())
	biz = p_biz
	kind = String(unit.get("kind", "shop"))
	rival = p_rival
	brand = BRANDS[absi(String(unit.get("id", "")).hash()) % BRANDS.size()]
	if not rival.is_empty() and biz == null:
		if rival.get("firm", false):
			biz = rival_display(unit, String(rival.get("name", "")), String(rival.get("type", "convenience")))
		else:
			biz = rival_display(unit)
	public_display = biz == null and rival.is_empty() and Premises.STREET_TRADE.has(String(unit.get("street_use", "")))
	if public_display:
		biz = rival_display(unit, String(unit["name"]), Premises.STREET_TRADE[unit["street_use"]])
	type_id = biz.type_id if biz else "convenience"
	look = ShopStyle.look(type_id)
	look["wall"] = (look["wall"] as Color).lerp(
		[Color(0.75, 0.76, 0.77), Color(0.83, 0.78, 0.68), Color(0.69, 0.74, 0.70)][_front_seed % 3], 0.22)
	look["floor"] = (look["floor"] as Color).lerp(
		[Color(0.67, 0.64, 0.60), Color(0.53, 0.54, 0.55), Color(0.75, 0.73, 0.66)][(_front_seed / 7) % 3], 0.21)
	if biz:
		ident = ShopStyle.brand(biz.name, type_id, not rival.is_empty() and not rival.get("firm", false))
		if not public_display and rival.is_empty() and String(ShopStyle.house.get("name", "")) != "":
			ident = ShopStyle.house_ident(ShopStyle.house)   # one of yours: your brand
		brand = ident["primary"]
	var sz := Premises.room_size(unit)
	W = sz.x
	H = sz.y
	D = sz.z
	ox = Premises.opening_x(unit)
	var mid := (ox.x + ox.y) * 0.5
	var half_door := 1.32 if unit.get("flagship", false) else 0.95
	door = Vector2(mid - half_door, mid + half_door) if kind in ["shop", "street"] else ox
	transform = Premises.room_xf(unit)
	if ground_fn.is_valid():
		var hi := -INF
		for fx in 5:
			for fz in 5:
				var p := transform * Vector3(W * (fx + 0.5) / 5.0, 0, -D * (fz + 0.5) / 5.0)
				hi = maxf(hi, float(ground_fn.call(p.x, p.z)) - p.y)
		lift = clampf(hi + 0.03, 0.0, 0.3)
	# Keep the finish just above the solid foundation.
	var bc := BuildingMesher.base_course(unit["b"])
	if bc.has_volume():
		lift = maxf(lift, bc.end.y - float(unit["y0"]) + 0.02)
	transform.origin.y += lift
	# How far the shop floor stands above the pavement at the door (a step).
	if ground_fn.is_valid() and kind in ["shop", "street"]:
		var outside := transform * Vector3((ox.x + ox.y) * 0.5, 0.0, 1.4)
		street_drop = clampf(transform.origin.y - float(ground_fn.call(outside.x, outside.z)), 0.0, 1.2)
	name = "Interior_" + String(unit.get("id", "unit"))
	rebuild()


## A fully stocked, fitted-out stand-in Business for drawing a store run by
## someone else (QuikSave, or an independent called `title`).
static func rival_display(u: Dictionary, title := "", type := "convenience") -> Business:
	var b := Business.new("rival_" + String(u.get("id", "")), type)
	b.setup_new(Premises.record(u), 1)
	for up in ([] if u.get("flagship", false) else b.type_def().get("upgrades", [])):
		if up in ["shelf_2", "fridge_2", "rail_2", "table_2", "cake_2", "lighting", "signage", "floor"]:
			b.apply_upgrade(up)
	b.name = title if title != "" else String(CityLife.rival_cfg().get("name", "QuikSave"))
	# Every slot stocked with something its fixture holds, from the shop's
	# own categories (a bakery's shelf has loaves, a clothes shop's shoes).
	var used := {}
	for s: Dictionary in b.slots:
		var fx: String = s["fixture"]
		if String(s["product"]) != "":
			s["qty"] = int(s["cap"])
			continue
		var pool: Array = EmpireData.product_ids().filter(func(p): return EmpireData.product(p)["fixture"] == fx \
			and EmpireData.type_sells(type, p))
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
	_fitting_clear = Rect2()
	_headers.clear()
	spots.clear()
	slot_pick.clear()
	slot_box.clear()
	till_customer.clear()
	till_staff.clear()
	queue.clear()
	_sales_lights.clear()
	_trade_glow = null
	_trade_board = null
	_static = Node3D.new()
	_static.name = "Static"
	add_child(_static)
	var _zone := InteriorKit.add_lighting_zone(_static, AABB(Vector3(0, 0, -D), Vector3(W, H, D)))
	# The room's own light, seen from the street too (2026-11-26: with the
	# darker night ambient, shops were black behind their glass from outside –
	# homes, venues and lobbies already had this probe).
	InteriorKit.room_probe(_zone, Color(1.0, 0.95, 0.88), 0.66, 0.24)
	_room_probe = _zone.get_node_or_null("InteriorBounce") as ReflectionProbe
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
	elif kind == "hq" or kind == "office":
		_build_lobby(st)
	elif kind == "street" or (public_display and unit.get("street_use", "") == "furniture"):
		_build_street(st)
	else:
		_build_shop(st)
	_fit_wall_bays()
	_furniture_contact()
	_finish_spans()
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
		gl.visibility_range_end = 180.0
		gl.visibility_range_end_margin = 14.0
		_static.add_child(gl)
		_glass = null
	if _glow != null:
		var gi := MeshInstance3D.new()
		gi.name = "Glow"
		gi.mesh = _glow.commit()
		gi.material_override = _mat("glow")
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_static.add_child(gi)
		_trade_glow = gi
		_glow = null
	if kind != "street" or public_display:
		_build_walk_grid()
	if public_display or kind == "street":
		_populate_public_room()
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
	var dw0 := W - 2.3
	var dw1 := W - 0.95
	_wall_box(st, 0.0, dw0, part_d, part_d + 0.14, 0.0, H, wall.darkened(0.04))
	_wall_box(st, dw1, W, part_d, part_d + 0.14, 0.0, H, wall.darkened(0.04))
	_wall_box(st, dw0, dw1, part_d, part_d + 0.14, 2.3, H, wall.darkened(0.04))
	_stock_door(st, part_d, dw0, dw1, trim)
	var feature_wall := wall.lerp(brand, 0.42) if type_id == "clothing" else wall.darkened(0.08)
	_wall_finish(R(dw0 * 0.5, part_d - 0.007, H * 0.5), 0.0, Vector2(dw0 - 0.034, H - 0.015),
		feature_wall, 7 if type_id == "clothing" else 5)
	# A shallow perimeter trim closes the visual joint with the ceiling.
	var cornice := wall.lerp(Color(0.87, 0.83, 0.76), 0.25)
	st.box(R(0.03, 0.24, H - 0.13), R(0.095, part_d, H), cornice)
	st.box(R(W - 0.095, 0.24, H - 0.13), R(W - 0.03, part_d, H), cornice)
	st.box(R(0.095, part_d - 0.065, H - 0.13), R(W - 0.095, part_d, H), cornice)
	# Shopfront: glass either side of the door, frame, fascia.
	_shopfront(st, trim)
	# Counter + tills on the right.
	var tills := biz.tills() if biz else 1
	var cx0 := W - 2.45
	var cx1 := W - 1.75
	var cd0 := 1.55 if cx0 - 0.06 >= door.y + ENTRY_SIDE else ENTRY_CLEAR + 0.10
	var pitch := clampf((part_d - cd0 - 1.15) / float(tills), 0.62, 1.25)
	var cd1 := cd0 + pitch * tills + 0.24
	st.box(R(cx0, cd0, 0.0), R(cx1, cd1, 0.98), Color(0.32, 0.22, 0.15))
	st.box(R(cx0 - 0.02, cd0 + 0.08, 0.12), R(cx0, cd1 - 0.08, 0.86), brand)  # branded counter front
	st.box(R(cx0 - 0.05, cd0 - 0.05, 0.98), R(cx1 + 0.05, cd1 + 0.05, 1.04), Color(0.9, 0.89, 0.86))
	_solid(R(cx0, cd0, 0.0), R(cx1, cd1, 1.04))
	for i in tills:
		var td := cd0 + pitch * (float(i) + 0.5)
		st.box(R(cx0 + 0.15, td - 0.22, 1.04), R(cx0 + 0.55, td + 0.22, 1.12), Color(0.12, 0.12, 0.13))  # register base
		st.box(R(cx0 + 0.28, td - 0.18, 1.12), R(cx0 + 0.32, td + 0.18, 1.42), Color(0.08, 0.09, 0.1))   # screen
		_glow_quad(R(cx0 + 0.27, td - 0.15, 1.15), R(cx0 + 0.27, td + 0.15, 1.39), Color(0.35, 0.8, 0.9))
		till_customer.append(R(cx0 - 0.55, td, 0.0))
		till_staff.append(R(cx1 + 0.55, td, 0.0))
		if public_display and i == 0:
			spots.append({"kind": "retail_checkout", "pos": till_customer[-1]})
		elif not public_display:
			spots.append({"kind": "till", "pos": till_staff[-1], "till": i, "label": "SERVE"})
	# Fit the queue to the floor before the stockroom partition.
	var queue_last := part_d - 0.58
	var queue_first := minf(cd1 + 0.40, queue_last)
	for k in range(1 + mini(5, floori((queue_last - queue_first) / 0.8))):
		queue.append(R(cx0 - 0.58, queue_first + 0.8 * k, 0.0))
	# Queue markings on the floor: a spot per place in the line and a
	# "please queue here" strip at its head (floor paint only: the walk
	# grid is unchanged).
	for k2 in mini(queue.size(), 4):
		var qd := queue_first + 0.8 * k2
		st.box(R(cx0 - 0.72, qd - 0.12, 0.014), R(cx0 - 0.38, qd + 0.12, 0.019), brand.lightened(0.15) if k2 > 0 else accent_col())
	st.box(R(cx0 - 0.95, cd1 + 0.08, 0.014), R(cx0 - 0.15, cd1 + 0.16, 0.019), Color(0.95, 0.85, 0.2))
	var ql := Label3D.new()
	ql.text = "PLEASE QUEUE HERE"
	ql.font = EmpireStyle.font("black")
	ql.font_size = 40
	ql.pixel_size = 0.0019
	ql.shaded = false
	ql.double_sided = false
	ql.outline_size = 0
	ql.modulate = Color(0.12, 0.12, 0.14)
	ql.position = R(cx0 - 0.55, queue_first - 0.15, 0.022)
	# Flat on the floor, reading across the line for someone queueing
	# (facing the till).
	ql.rotation = Vector3(-PI * 0.5, PI, 0.0)
	_static.add_child(ql)
	# Cigarette-style back display behind the counter (decor) + till staff area.
	st.box(R(W - 0.4, cd0, 0.9), R(W - 0.05, cd1, 2.2), Color(0.25, 0.27, 0.3))
	# Fitting rooms reserve their footprint before products are allocated.
	var fit := _fitting_room(st, part_d) if type_id == "clothing" else Rect2()
	_place_fixtures(st, part_d)
	if _has_mezzanine():
		_build_mezzanine(st, part_d)
	_decor(st, part_d, cx0, cd0, cd1)
	if biz and biz.has_upgrade("security"):
		_build_cctv(st, part_d)
	if biz and (biz.reputation >= 65.0 or biz.has_upgrade("floor") or biz.has_upgrade("lighting") or biz.level >= 2):
		_build_shop_prestige(st, part_d, cx0, cx1, cd0, cd1)
	if biz and biz.level >= 2:
		_level_fitout(st, part_d)
	# Back room: racking, office desk, mop.
	_backroom(st, part_d, dw0, dw1)
	door_in = R((door.x + door.y) * 0.5, 0.9, 0.0)
	door_out = R((door.x + door.y) * 0.5, -1.6, 0.0)
	spots.append({"kind": "door", "pos": R((door.x + door.y) * 0.5, 0.55, 0.0), "label": "OPEN / CLOSE"})
	# Stage loose cases in the stockroom away from the customer entrance.
	pile_pos = R(1.45, part_d + 0.43, 0.0)
	spots.append({"kind": "pile", "pos": pile_pos, "label": "STAGING AREA"})
	# Ceiling lights (their kind follows the shop's).
	var bright := 1.25 if biz and biz.has_upgrade("lighting") else 0.85
	if biz and biz.reputation >= 65.0:
		bright += 0.12
	var tint: Color = look.get("tint", Color(1.0, 0.97, 0.92))
	tint = tint.lerp(Color(1.0, 0.93, 0.83), 0.18)
	if biz and biz.has_upgrade("lighting"):
		tint = tint.lerp(Color(1.0, 0.9, 0.78), 0.4)
	if unit.get("flagship", false) or (biz and biz.level >= 3):
		# (A major retailer and the chain's flagship get the track lighting.)
		_flagship_lights(st, part_d, tint)
		_flagship_feature(st, part_d, tint)
	else:
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
	if fit.has_area():
		st.box(R(fit.position.x - 0.025, -fit.end.y, 0.001),
			R(fit.end.x + 0.025, -fit.end.y + 0.84, 0.016), Color(0.19, 0.17, 0.15))


var _fitting_clear := Rect2()


func _fitting_room(st: _Batch, depth: float) -> Rect2:
	if W < 8.8 or depth < 5.8:
		return Rect2()
	var d0 := depth - 1.8
	var x0 := 0.14
	var width := 1.62
	var count := 2 if W > 17.0 else 1
	var end := x0 + width * count
	var panel := Color(0.46, 0.36, 0.27).lerp(brand, 0.24)
	var curtain := Color(0.27, 0.21, 0.20).lerp(brand, 0.30)
	_fitting_clear = Rect2(x0, -depth, end - x0, depth - d0 + 0.92)
	for divider in count + 1:
		var x := x0 + width * divider
		_wall_box(st, x - 0.031, x + 0.031, d0, depth, 0.0, 2.42, panel)
		if divider == count:
			_wall_finish(R(x + 0.036, (d0 + depth) * 0.5, 1.21), PI * 0.5, Vector2(depth - d0, 2.40), panel, 1)
	for i in count:
		var x := x0 + width * i
		st.box(R(x + 0.075, d0 - 0.08, 2.35), R(x + width - 0.075, d0, 2.60), panel.darkened(0.26))
		_glow_quad(R(x + width * 0.3, d0 + 0.23, 2.346), R(x + width * 0.7, d0 + 0.34, 2.346), Color(1.0, 0.94, 0.84), true)
		st.box(R(x + 0.02, d0 - 0.015, 2.30), R(x + width - 0.02, d0 + 0.052, 2.38), panel.lightened(0.18))
		for fold in 7:
			var px := x + 0.065 + fold * 0.071
			var front := d0 + cos(float(fold) * 2.0) * 0.026
			st.box(R(px, front, 0.075), R(px + 0.078, front + 0.022, 2.29), curtain.lightened(0.04 * float(fold % 3)))
		_solid(R(x + 0.065, d0 - 0.026, 0.075), R(x + 0.572, d0 + 0.048, 2.29))
		st.box(R(x + 0.33, depth - 0.083, 0.30), R(x + width - 0.26, depth - 0.019, 2.21), panel.darkened(0.32))
		var mirror := MeshInstance3D.new()
		var glass := QuadMesh.new()
		glass.size = Vector2(width - 0.66, 1.76)
		mirror.mesh = glass
		mirror.material_override = InteriorKit.fitting_glass()
		mirror.position = R(x + width * 0.5 + 0.03, depth - 0.086, 1.26)
		mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_static.add_child(mirror)
	_street_label("FITTING ROOMS", R(x0 + width * 0.5, d0 - 0.088, 2.475), width - 0.20, Color(0.93, 0.87, 0.74))
	_spot_light(R((x0 + end) * 0.5, d0 + 0.52, H - 0.15), Color(1.0, 0.9, 0.8), 1.45, H + 0.3, 33.0)
	return Rect2(x0, -depth, end - x0, depth - d0)


func _fit_wall_bays() -> void:
	if kind == "shop" and biz == null:
		return
	var blocked: Array[Rect2] = []
	for box: CollisionShape3D in _col.get_children():
		if box.shape is not BoxShape3D:
			continue  # the exterior grade does not occupy the sales floor
		var size := (box.shape as BoxShape3D).size
		var base := box.position - size * 0.5
		if base.y > 2.35 or base.y + size.y < 0.23:
			continue
		# Ignore the perimeter shell itself.
		var area := Rect2(Vector2(base.x, base.z), Vector2(size.x, size.z)).intersection(Rect2(0.042, -D + 0.043, W - 0.084, D - 0.08))
		if area.has_area():
			blocked.append(area.grow(0.06))
	for spot: Dictionary in spots:
		var p: Vector3 = spot["pos"]
		blocked.append(Rect2(Vector2(p.x - 0.46, p.z - 0.46), Vector2.ONE * 0.92))
	for p: Vector3 in till_customer + till_staff + queue:
		blocked.append(Rect2(p.x - 0.66, p.z - 0.66, 1.32, 1.32))
	if _fitting_clear.has_area():
		blocked.append(_fitting_clear)
	var depth := D - BACKROOM - 0.14 if kind == "shop" else D
	if kind == "shop":
		var stockroom_door := _door_at.x
		blocked.append(Rect2(stockroom_door - 1.53, -depth, 3.06, 1.15))
	var use := String(unit.get("street_use", kind))
	if kind == "shop" and not public_display:
		use = type_id
	elif kind == "wholesale":
		use = "warehouse"
	if kind in ["office", "hq"]:
		# Leave the main brand panel and wall-mounted reception displays visible.
		blocked.append(Rect2(W * 0.5 - 3.5, -D, 7.0, 0.75))
	if kind == "street" or (public_display and use == "furniture"):
		var mid := (door.x + door.y) * 0.5
		var title_span := minf(W - 1.5, 6.8)
		# Keep the wall lettering and service counter's back shelf visible.
		blocked.append(Rect2(mid - title_span * 0.43, -D, title_span * 0.86, 0.65))
	var bays := InteriorKit.plan(W, depth, H, blocked, ENTRY_CLEAR, 0.033)
	if _has_mezzanine():
		# Keep displays clear of the stair and overhanging gallery.
		bays = bays.filter(func(bay: Transform3D) -> bool: return not _under_mezzanine(bay.origin))
	for bay in bays:
		var box := InteriorKit.footprint(bay)
		_solid(box.position, box.end)
	InteriorKit.dress(_static, bays, InteriorKit.profile(use), _front_seed)


func _furniture_contact() -> void:
	var feet: Array[Rect2] = []
	for fixture: CollisionShape3D in _col.get_children():
		if fixture.shape is not BoxShape3D:
			continue
		var shape := (fixture.shape as BoxShape3D).size
		var at := fixture.position - shape * 0.5
		if absf(at.y) > 0.038 or shape.y < 0.26 or minf(shape.x, shape.z) < 0.22:
			continue
		if minf(shape.x, shape.z) > 2.5 or shape.x + shape.z > 6.5:
			continue
		if at.z < -D + 0.28 or at.z + shape.z > -0.5 or at.x < 0.17 or at.x + shape.x > W - 0.17:
			continue
		feet.append(Rect2(at.x, at.z, shape.x, shape.z))
		if feet.size() >= 38:
			break
	InteriorKit.add_contacts(_static, feet)


func _under_mezzanine(p: Vector3) -> bool:
	# The west stair and upper gallery are already furnished and have their own rails.
	return p.x < 6.8 and p.z < -3.25 and p.z > -16.35


## Growth levels (Growth, 2026-11-27): an established business hangs your
## company's lightbox over the shop floor; a major retailer adds a second and
## a SELF CHECKOUT sign over the extra till; the flagship's is gold-trimmed
## with FLAGSHIP under the name. All above head height – nothing to walk into.
func _level_fitout(st: _Batch, part_d: float) -> void:
	if H < 2.9 or W < 5.0:
		return
	var nm := String(ShopStyle.house.get("name", "")) if not ShopStyle.house.is_empty() else ""
	if nm == "":
		nm = biz.name
	var ident := ShopStyle.house_ident(ShopStyle.house) if not ShopStyle.house.is_empty() else {}
	var prim: Color = ident.get("primary", brand) if ident.get("primary") is Color else brand
	var acc: Color = ident.get("accent", Color(1, 1, 1)) if ident.get("accent") is Color else Color(1, 1, 1)
	var trim := Color(0.78, 0.64, 0.34) if biz.level >= 4 else Color(0.16, 0.17, 0.19)
	var at_d: Array = [part_d * 0.42]
	if biz.level >= 3 and part_d > 9.0:
		at_d.append(part_d * 0.78)
	for d: float in at_d:
		var y1 := H - 0.14
		var y0 := y1 - (0.5 if H >= 3.3 else 0.4)
		var hw := minf(W * 0.3, 2.4)
		# Hangers, frame and the lit face (both sides).
		for sx: float in [-hw * 0.8, hw * 0.8]:
			st.box(R(W * 0.5 + sx - 0.01, d - 0.01, y1), R(W * 0.5 + sx + 0.01, d + 0.01, H), trim)
		st.box(R(W * 0.5 - hw - 0.03, d - 0.07, y0 - 0.03), R(W * 0.5 + hw + 0.03, d + 0.07, y1 + 0.03), trim)
		st.box(R(W * 0.5 - hw, d - 0.075, y0), R(W * 0.5 + hw, d + 0.075, y1), prim)
		for side: float in [-1.0, 1.0]:
			var lb := Label3D.new()
			lb.text = nm.to_upper() + ("\nFLAGSHIP" if biz.level >= 4 else "")
			lb.font = ShopStyle.font(String(ShopStyle.house.get("face", ""))) if not ShopStyle.house.is_empty() else EmpireStyle.font("black")
			lb.font_size = 64 if biz.level < 4 else 56
			lb.pixel_size = minf(0.0042, hw * 2.0 * 0.86 / maxf(float(nm.length()) * 40.0, 1.0))
			lb.shaded = false
			lb.double_sided = false
			lb.outline_size = 0
			lb.modulate = acc * 1.25
			lb.position = R(W * 0.5, d + 0.08 * side, (y0 + y1) * 0.5)
			lb.rotation.y = 0.0 if side < 0.0 else PI
			_static.add_child(lb)
	if biz.level >= 3 and biz.tills() >= 2:
		var sc := Label3D.new()
		sc.text = "SELF CHECKOUT"
		sc.font = EmpireStyle.font("black")
		sc.font_size = 40
		sc.pixel_size = 0.003
		sc.shaded = false
		sc.modulate = Color(0.95, 0.97, 1.0)
		sc.outline_size = 0
		sc.position = R(W * 0.8, 1.2, H - 0.55)
		sc.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_static.add_child(sc)


func _flagship_lights(st: _Batch, sales_depth: float, tint: Color) -> void:
	var rails := maxi(4, floori(W / 5.0))
	for ix in rails:
		var x := W * (ix + 0.5) / rails
		st.box(R(x - 0.09, 1.5, H - 0.30), R(x + 0.09, sales_depth - 0.8, H - 0.12), Color(0.22, 0.23, 0.24))
		for bay in maxi(2, floori(sales_depth / 4.0)):
			var z := 2.1 + 4.0 * bay
			if z + 0.9 < sales_depth:
				_glow_quad(R(x - 0.07, z - 0.75, H - 0.308), R(x + 0.07, z + 0.75, H - 0.308), tint * 1.36, true)
	for x_factor: float in [0.30, 0.70]:
		for d_factor: float in [0.26, 0.70]:
			_spot_light(R(W * x_factor, sales_depth * d_factor, H - 0.32), tint, 1.55,
				clampf(maxf(W, sales_depth) * 0.39, 8.0, 17.0), 66.0)


func _flagship_feature(st: _Batch, depth: float, tint: Color) -> void:
	# The central walk remains open on both sides of the display island.
	if W < 16.0 or depth < 14.0:
		return
	var x := W * 0.5 + 0.83
	var d := depth * 0.56
	var edge := Vector3(0.67, 0.64, 0.75)
	var at := R(x, d, 0.0)
	var reserved := AABB(at + Vector3(-1.59, 0.25, -1.35), Vector3(3.18, 2.0, 2.7))
	for cs: CollisionShape3D in _col.get_children():
		if cs.shape is not BoxShape3D:
			continue
		var size := (cs.shape as BoxShape3D).size
		if reserved.intersects(AABB(cs.position - size * 0.5, size)):
			return
	match String(unit.get("street_use", "")):
		"clothing", "department":
			st.cylinder(at, 0.68, 0.13, Color(0.33, 0.23, 0.16), 22)
			_mannequin(at + Vector3(-0.16, 0.13, 0), PI * 0.08)
		"supermarket":
			var oak := Color(0.45, 0.32, 0.21)
			st.box(at - Vector3(edge.x, 0.0, edge.z), at + edge, oak)
			for i in 4:
				for j in 3:
					var p := at + Vector3(-0.48 + 0.30 * i, 0.64, -0.42 + 0.4 * j)
					st.cylinder(p, 0.09, 0.175, Color(0.44, 0.26, 0.14).lightened(0.07 * ((i + j) % 3)), 10)
		_:
			return
	_solid(at - Vector3(edge.x, 0.0, edge.z), at + edge)
	_spot_light(at + Vector3.UP * (H - 0.35), tint, 2.35, H + 1.0, 37.0)


func _has_mezzanine() -> bool:
	return H >= 5.1 and W >= 17.0 and D >= 17.0 and unit.get("street_use", "") in ["clothing", "department"]


func _build_mezzanine(st: _Batch, part_d: float) -> void:
	var h := 2.63
	var d0 := 8.0
	var d1 := minf(part_d - 0.9, 15.6)
	var ash := Color(0.59, 0.49, 0.36)
	var metal := Color(0.15, 0.17, 0.18)
	# The stair stays outside the main shopping aisle, and uses normal
	# walkable collisions so the character climbs it with touch movement.
	var steps := 16
	var going := 0.27
	var x0 := 0.65
	var x1 := 2.65
	for i in steps:
		var y := h * (i + 1) / steps
		var d := d0 - going * (steps - i)
		st.box(R(x0, d, y - 0.16), R(x1, d + going, y), ash)
		_solid(R(x0, d, 0.0), R(x1, d + going, y))
		if i % 3 == 0:
			st.box(R(x1 - 0.04, d + 0.09, y), R(x1 + 0.04, d + 0.16, y + 1.0), metal)
	st.box(R(0.16, d0, h - 0.19), R(6.5, d1, h), ash)
	_solid(R(0.16, d0, h - 0.19), R(6.5, d1, h))
	_wall_box(st, 6.42, 6.5, d0, d1, h, h + 1.0, metal)
	_wall_box(st, x1, 6.5, d0, d0 + 0.07, h, h + 1.0, metal)
	_wall_box(st, 0.16, 6.5, d1 - 0.08, d1, h, h + 1.0, metal)
	for d: float in [d0 + 2.2, minf(d1 - 0.85, d0 + 4.45)]:
		_street_furniture(st, 2.55, d, h)
	_glow_quad(R(0.75, d0 + 0.65, H - 0.03), R(5.9, d0 + 0.93, H - 0.03), Color(1.0, 0.93, 0.78) * 1.15, true)
	_light(R(3.15, d0 + 2.0, H - 0.36), Color(1.0, 0.93, 0.79), 0.7, 5.6)


## Dressing: a brand band round the walls, posters, an entrance mat, a
## basket stack and a newspaper stand by the door, a plant, PAY HERE sign.
func _decor(st: _Batch, part_d: float, cx0: float, cd0: float, cd1: float) -> void:
	if type_id == "convenience":
		_decor_corner(st, part_d, cx0, cd0, cd1)
	else:
		_decor_trade(st, part_d, cx0, cd0, cd1)


## Ceiling-mounted CCTV dome cameras in the sales floor corners when the
## "security" upgrade is installed.
func _build_cctv(st: _Batch, part_d: float) -> void:
	var mount_c := Color(0.14, 0.15, 0.17)
	var collar_c := Color(0.88, 0.89, 0.91)
	var dome_c := Color(0.06, 0.07, 0.09)
	var corners := [R(0.42, 0.62, H), R(W - 0.48, part_d - 0.48, H)]
	if W >= 14.0:
		corners.append(R(0.42, part_d - 0.48, H))
		corners.append(R(W - 0.48, 0.62, H))
	for pos: Vector3 in corners:
		st.box(pos + Vector3(-0.09, -0.05, -0.09), pos + Vector3(0.09, 0.0, 0.09), mount_c)
		st.cylinder(pos + Vector3(0.0, -0.10, 0.0), 0.11, 0.055, collar_c, 10)
		st.cylinder(pos + Vector3(0.0, -0.175, 0.0), 0.085, 0.078, dome_c, 10)
		_glow_quad(pos + Vector3(-0.015, -0.115, 0.085), pos + Vector3(0.015, -0.095, 0.095), Color(1.0, 0.18, 0.14) * 1.8)


## Subtle visual upgrades for high-reputation (>= 65) or upgraded shops:
## brass counter trim, a ceramic counter accent planter, and a top-rated plaque.
func _build_shop_prestige(st: _Batch, part_d: float, cx0: float, cx1: float, cd0: float, cd1: float) -> void:
	var brass := Color(0.76, 0.63, 0.34)
	# Sleek brass kick-rail and counter-front accent trim.
	st.box(R(cx0 - 0.032, cd0 + 0.05, 0.04), R(cx0 - 0.015, cd1 - 0.05, 0.095), brass)
	st.box(R(cx0 - 0.032, cd0 + 0.05, 0.88), R(cx0 - 0.015, cd1 - 0.05, 0.92), brass)
	# Compact ceramic accent planter resting on the front corner of the counter top.
	if cd1 - cd0 >= 0.85:
		var px := cx0 + 0.14
		var pd := cd0 + 0.12
		st.cylinder(R(px, pd, 1.04), 0.09, 0.15, Color(0.92, 0.9, 0.85), 10)
		st.cylinder(R(px, pd, 1.18), 0.115, 0.14, Color(0.18, 0.44, 0.22), 10)
		st.cylinder(R(px, pd, 1.30), 0.075, 0.10, Color(0.24, 0.54, 0.26), 8)
	# High-reputation shops earn a lit "TOP RATED" gold plaque behind the counter.
	if biz and biz.reputation >= 65.0:
		var md := (cd0 + cd1) * 0.5
		st.box(R(W - 0.08, md - 0.42, 2.32), R(W - 0.04, md + 0.42, 2.74), Color(0.11, 0.12, 0.14))
		st.box(R(W - 0.085, md - 0.44, 2.30), R(W - 0.04, md + 0.44, 2.33), brass)
		st.box(R(W - 0.085, md - 0.44, 2.73), R(W - 0.04, md + 0.44, 2.76), brass)
		var badge := Label3D.new()
		badge.text = "★★★★★\nTOP RATED" if biz.reputation >= 85.0 else "★★★★\nLOCAL FAVOURITE"
		badge.font = EmpireStyle.font("black")
		badge.font_size = 44
		badge.pixel_size = 0.0022
		badge.shaded = false
		badge.double_sided = false
		badge.outline_size = 0
		badge.modulate = Color(0.98, 0.84, 0.42)
		badge.position = R(W - 0.09, md, 2.53)
		badge.rotation.y = -PI * 0.5
		_static.add_child(badge)


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
		# Printed: an offer (the window promos), not a blank colour card.
		var pl := Label3D.new()
		pl.text = _promo_text(pd * 3.7 + 11.0)
		pl.font = ShopStyle.font(String(ident.get("face", ""))) if biz else EmpireStyle.font("black")
		pl.font_size = 64
		pl.pixel_size = 0.0019
		pl.line_spacing = -8.0
		pl.shaded = false
		pl.double_sided = false
		pl.outline_size = 0
		pl.modulate = Color(0.1, 0.1, 0.12) if i % pcols.size() == 0 else Color(1, 0.99, 0.96)
		pl.position = R(0.095, pd + 0.45, 3.22)
		pl.rotation.y = PI * 0.5
		_static.add_child(pl)
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
	# Newspaper stand on the outer display bay.
	var nx := door.x - ENTRY_SIDE - 0.85
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
	lab.double_sided = false
	lab.font_size = 56
	lab.pixel_size = 0.004
	lab.outline_size = 0
	lab.shaded = false
	lab.modulate = Color(1, 1, 1)
	lab.position = R(cx0 - 0.115, hd, 2.95)
	lab.rotation.y = -PI * 0.5
	_static.add_child(lab)
	# (Both faces: from behind the counter it used to be a blank green plank.)
	var lab2 := lab.duplicate() as Label3D
	lab2.text = "THANK YOU"
	lab2.position = R(cx0 - 0.025, hd, 2.95)
	lab2.rotation.y = PI * 0.5
	_static.add_child(lab2)


func _shell(st: _Batch, wall: Color, trim: Color) -> void:
	# Side and back walls (inner faces), ceiling.
	_wall_box(st, -0.05, 0.02, 0.0, D, 0.0, H, wall)
	_wall_box(st, W - 0.02, W + 0.05, 0.0, D, 0.0, H, wall)
	_wall_box(st, 0.0, W, D - 0.02, D + 0.05, 0.0, H, wall.darkened(0.06))
	var use := String(unit.get("street_use", type_id))
	var plaster_style := 3 if use in ["garage", "warehouse"] else 5
	var stone_style := 7 if use in ["hotel", "restaurant", "bank", "residential"] else plaster_style
	var side_span := Vector2(D - 0.35, H - 0.022)
	var side_center := -(D + 0.29) * 0.5
	_wall_finish(Vector3(0.024, H * 0.5, side_center), PI * 0.5, side_span, wall, stone_style)
	_wall_finish(Vector3(W - 0.024, H * 0.5, side_center), -PI * 0.5, side_span, wall, plaster_style)
	_wall_finish(Vector3(W * 0.5, H * 0.5, -D + 0.024), 0.0, Vector2(W - 0.05, H - 0.022), wall.darkened(0.06), stone_style)
	st.box(R(0.046, D - 0.065, 0.0), R(W - 0.046, D - 0.022, 0.12), trim)
	var ceil_col: Color = look.get("ceiling", Color(0.78, 0.78, 0.76)) if not look.is_empty() else Color(0.78, 0.78, 0.76)
	st.box(R(0.0, 0.0, H - 0.01), R(W, D, H + 0.05), ceil_col)
	# Suspended-ceiling grid (corner shops and the warehouse).
	if (look.is_empty() or String(look.get("lights", "grid")) == "grid") and not unit.get("flagship", false):
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
	var oh := _front_opening_height()
	# (Its outer face stops 3 cm inside the facade, or the two z-fight.)
	_wall_box(st, 0.0, ox.x, 0.03, 0.3, 0.0, H, wall)
	_wall_box(st, ox.y, W, 0.03, 0.3, 0.0, H, wall)
	_wall_box(st, ox.x, ox.y, 0.03, 0.3, oh, H, wall)


func _wall_finish(p: Vector3, yaw: float, span: Vector2, tint: Color, style: int) -> void:
	var surface := QuadMesh.new()
	surface.size = span
	var node := MeshInstance3D.new()
	node.mesh = surface
	node.position = p
	node.rotation.y = yaw
	node.material_override = InteriorKit.wall_finish(span, tint, style, _front_seed)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_static.add_child(node)


func _front_opening_height() -> float:
	return float(unit["oy1"]) - float(unit["oy0"]) - lift


## One face per pane, visible on both sides through the glass material.
## Joining two transparent faces at the same edge causes dark seams and
## makes double reflections through the shop.
func _pane(a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	if _cur_span >= 0:
		var sg: _Batch = (_spans[_cur_span] as Dictionary)["glass"]
		sg._quad(a, b, c, d, (b - a).cross(d - a).normalized(), tint)
		return
	if _glass == null:
		_glass = _Batch.new()
	_glass._quad(a, b, c, d, (b - a).cross(d - a).normalized(), tint)


# ------------------------------------------------- breakable shopfronts
## Each display window either side of the door is its own breakable span
## (destruction overhaul 2026-11-25): its stall riser, sill, mullions and
## glass are drawn as one node with its own collision body, so a car can
## smash through it into the shop while the pilasters, reveals, fascia and
## the walls of the building (the structure) stay put. StorefrontSmash
## finds the spans (group "shop_spans"), DamageDesk bills them, and
## `front_state` (set by the game before the room is built) keeps a broken
## window broken – then boarded up – until it's repaired.
var _spans: Array = []        # {shell: _Batch, glass: _Batch, lo, hi (room), node, body, broken}
var _cur_span := -1
## unit-level state from the game: span index -> "broken" | "boarded".
var front_state := {}


func span_count() -> int:
	return _spans.size()


## Span i's box in world space: [Transform3D (room), lo, hi] for hit tests.
func span_box(i: int) -> Array:
	var sp: Dictionary = _spans[i]
	return [global_transform, sp["lo"], sp["hi"]]


func span_broken(i: int) -> bool:
	return String((_spans[i] as Dictionary).get("state", "")) != ""


func _begin_span(lo: Vector3, hi: Vector3) -> _Batch:
	var sp := {"shell": _Batch.new(), "glass": _Batch.new(), "lo": lo.min(hi), "hi": lo.max(hi), "state": ""}
	_spans.append(sp)
	_cur_span = _spans.size() - 1
	return sp["shell"]


func _finish_spans() -> void:
	_cur_span = -1
	for i in _spans.size():
		var sp: Dictionary = _spans[i]
		var node := Node3D.new()
		node.name = "Span_%d" % i
		_static.add_child(node)
		var shell := MeshInstance3D.new()
		shell.name = "Frame"
		shell.mesh = (sp["shell"] as _Batch).commit()
		shell.material_override = _mat("vc")
		shell.visibility_range_end = 260.0
		node.add_child(shell)
		var gl := MeshInstance3D.new()
		gl.name = "Glass"
		gl.mesh = (sp["glass"] as _Batch).commit()
		gl.material_override = _mat("glass")
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gl.visibility_range_end = 180.0
		node.add_child(gl)
		var body := StaticBody3D.new()
		body.name = "SpanBody_%d" % i
		body.collision_layer = CityWorld.HUMAN_LAYER | 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = ((sp["hi"] as Vector3) - (sp["lo"] as Vector3)).max(Vector3.ONE * 0.02)
		cs.shape = bs
		cs.position = ((sp["lo"] as Vector3) + (sp["hi"] as Vector3)) * 0.5
		body.add_child(cs)
		body.set_meta("shop_span", i)
		add_child(body)
		sp["node"] = node
		sp["body"] = body
		sp["shell"] = null
		sp["glass"] = null
		var st0 := String(front_state.get(i, ""))
		if st0 != "":
			_set_span_state(i, st0)
	if not _spans.is_empty():
		add_to_group("shop_spans")


## "broken": window gone (jagged teeth of glass left in a bent frame, open
## to drive or walk through); "boarded": plywood over the opening (solid
## again); "": as built.
func _set_span_state(i: int, state: String) -> void:
	var sp: Dictionary = _spans[i]
	sp["state"] = state
	var node: Node3D = sp["node"]
	var body: StaticBody3D = sp["body"]
	var old := node.get_node_or_null("Damage")
	if old:
		old.queue_free()
	node.get_node("Frame").visible = state == ""
	node.get_node("Glass").visible = state == ""
	(body.get_child(0) as CollisionShape3D).set_deferred("disabled", state == "broken")
	if state == "":
		return
	var lo: Vector3 = sp["lo"]
	var hi: Vector3 = sp["hi"]
	var dmg := _Batch.new()
	var glass := _Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([unit.get("id", ""), i])
	var z := (lo.z + hi.z) * 0.5
	if state == "boarded":
		# Plywood sheets screwed over the hole, a batten across them.
		var n := maxi(1, ceili((hi.x - lo.x) / 1.22))
		for k in n:
			var x0 := lerpf(lo.x, hi.x, float(k) / n) + 0.01
			var x1 := lerpf(lo.x, hi.x, float(k + 1) / n) - 0.01
			var ply := Color(0.71, 0.58, 0.4).darkened(rng.randf_range(0.0, 0.12))
			dmg.box(Vector3(x0, lo.y + 0.02, z - 0.02), Vector3(x1, hi.y - 0.05, z + 0.03), ply)
		dmg.box(Vector3(lo.x, lo.y + (hi.y - lo.y) * 0.45, z + 0.03), Vector3(hi.x, lo.y + (hi.y - lo.y) * 0.45 + 0.09, z + 0.07), Color(0.48, 0.38, 0.27))
	else:
		# The frame left behind: a buckled bottom rail and the stubs of the
		# mullions, and teeth of glass hanging from the head and standing in
		# the sill.
		var frame := Color(0.17, 0.17, 0.16)
		dmg.box(Vector3(lo.x, lo.y, z - 0.05), Vector3(hi.x, lo.y + 0.12, z + 0.05), frame.darkened(0.2))
		dmg.box(Vector3(lo.x, hi.y - 0.14, z - 0.05), Vector3(hi.x, hi.y, z + 0.05), frame)
		var stubs := maxi(1, ceili((hi.x - lo.x) / 1.9))
		for k in stubs + 1:
			var x := lerpf(lo.x, hi.x, float(k) / stubs)
			var hgt := rng.randf_range(0.3, 1.2)
			dmg.box(Vector3(x - 0.03, lo.y, z - 0.04), Vector3(x + 0.03, lo.y + hgt, z + 0.04), frame)
		var tint := Color(0.65, 0.75, 0.81, 0.35)
		var x := lo.x
		while x < hi.x - 0.05:
			var w := rng.randf_range(0.12, 0.35)
			var x1 := minf(hi.x, x + w)
			var top_len := rng.randf_range(0.08, 0.6)
			var bot_len := rng.randf_range(0.05, 0.35)
			var tip := lerpf(x, x1, rng.randf())
			glass._tri(Vector3(x, hi.y - 0.14, z), Vector3(x1, hi.y - 0.14, z), Vector3(tip, hi.y - 0.14 - top_len, z), Vector3.BACK, tint)
			glass._tri(Vector3(x1, lo.y + 0.12, z), Vector3(x, lo.y + 0.12, z), Vector3(tip, lo.y + 0.12 + bot_len, z), Vector3.BACK, tint)
			x = x1
	var dn := Node3D.new()
	dn.name = "Damage"
	node.add_child(dn)
	var dm := MeshInstance3D.new()
	dm.mesh = dmg.commit()
	dm.material_override = _mat("vc")
	dn.add_child(dm)
	if state == "broken":
		var gm := MeshInstance3D.new()
		gm.mesh = glass.commit()
		gm.material_override = _mat("glass")
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dn.add_child(gm)


func break_span(i: int) -> void:
	if i >= 0 and i < _spans.size() and not span_broken(i):
		front_state[i] = "broken"
		_set_span_state(i, "broken")


func board_span(i: int) -> void:
	if i >= 0 and i < _spans.size():
		front_state[i] = "boarded"
		_set_span_state(i, "boarded")


func mend_span(i: int) -> void:
	if i >= 0 and i < _spans.size():
		front_state.erase(i)
		_set_span_state(i, "")


func _glazed_bays(st: _Batch, span: Vector2, y: Vector2, depth: float,
		stile: float, spacing: float, frame: Color, tint: Color, end_stiles := true) -> void:
	if span.y - span.x < 2.0 * stile + 0.02 or y.y - y.x < 0.02:
		return
	var count := maxi(1, ceili((span.y - span.x) / spacing))
	for i in count + 1:
		if not end_stiles and (i == 0 or i == count):
			continue
		var x := lerpf(span.x, span.y, float(i) / count)
		st.box(R(x - stile, depth - 0.049, y.x), R(x + stile, depth + 0.043, y.y), frame)
	for i in count:
		var left := lerpf(span.x, span.y, float(i) / count) + stile + 0.002
		var right := lerpf(span.x, span.y, float(i + 1) / count) - stile - 0.002
		_pane(R(left, depth, y.x + 0.003), R(right, depth, y.x + 0.003),
			R(right, depth, y.y - 0.003), R(left, depth, y.y - 0.003), tint)


func _shopfront(st: _Batch, _trim: Color) -> void:
	var oh := _front_opening_height()
	var gd := 0.12  # glass line, just inside the facade
	var trading_here := biz != null
	var flagship := bool(unit.get("flagship", false))
	var hsh := absi(String(unit.get("id", "")).hash())
	# The joinery: painted timber, anodised aluminium or slim black steel
	# (ShopStyle.front), its stall risers, mullions and a lobbied door.
	var sf := ShopStyle.front(type_id if trading_here else "", hsh, brand, not rival.is_empty() and not rival.get("firm", false))
	if flagship:
		var warm := String(unit.get("island", "")) == "west"
		sf["frame"] = Color(0.31, 0.29, 0.26) if warm else Color(0.34, 0.37, 0.39)
		sf["riser_col"] = (sf["frame"] as Color).darkened(0.24)
		sf["panels"] = false
	var fc: Color = (sf["frame"] as Color).lerp(Color(0.18, 0.18, 0.16), 0.21)
	var rh: float = sf["riser"]
	var mw: float = sf["mullion"]
	var th := oh - 0.62   # transom bar (and the door head)
	var dr := 0.75        # the doors stand this far back, in a lobby
	var glass_c := Color(0.65, 0.75, 0.81, 0.12 if unit.get("flagship", false) else 0.2)
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
		# (Its own breakable span: riser, sill, mullions, glass, collision.)
		var sb := _begin_span(R(x0, gd - 0.08, 0.0), R(x1, gd + 0.08, th))
		_riser(sb, x0, x1, gd, rh, fc, sf)
		sb.box(R(x0, gd - 0.13, rh), R(x1, gd + 0.06, rh + 0.05), fc.lightened(0.15))  # sill
		_glazed_bays(sb, Vector2(x0, x1), Vector2(rh + 0.05, th), gd, mw, 1.9, fc, glass_c)
		_cur_span = -1
		# The transom above the window stays (it's under the fascia beam).
		_solid(R(x0, gd - 0.08, th), R(x1, gd + 0.08, oh))
	# The transom has its own small lights, aligned with the display bays.
	st.box(R(ox.x, gd - 0.07, th), R(ox.y, gd + 0.06, th + 0.07), fc)
	for sp: Array in spans:
		_glazed_bays(st, Vector2(sp[0], sp[1]), Vector2(th + 0.07, oh - 0.12), gd, mw, 1.9, fc, glass_c)
	_glazed_bays(st, door, Vector2(th + 0.07, oh - 0.12), gd, mw, 2.9, fc, glass_c, false)
	# The lobby: glazed returns either side, a mosaic floor, a soffit, and
	# the pair of doors standing open against the returns.
	for rx: float in [door.x, door.y]:
		st.box(R(rx - 0.04, gd, 0.0), R(rx + 0.04, dr, rh), fc)                       # return riser
		st.box(R(rx - 0.05, dr - 0.05, 0.0), R(rx + 0.05, dr + 0.05, th), fc)        # back post
		st.box(R(rx - 0.04, gd, th - 0.06), R(rx + 0.04, dr, th), fc)                 # top rail
		_pane(R(rx, gd + 0.053, rh + 0.003), R(rx, dr - 0.052, rh + 0.003),
			R(rx, dr - 0.052, th - 0.063), R(rx, gd + 0.053, th - 0.063), glass_c)
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
		_pane(R(lx, dr + 0.063, 0.303), R(lx, dr + 0.837, 0.303),
			R(lx, dr + 0.837, th - 0.203), R(lx, dr + 0.063, th - 0.203), glass_c)
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
	if flagship:
		fascia = fascia.lerp(Color(0.24, 0.25, 0.25), 0.53)
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
				_promo_text(x0), Color(1.0, 0.98, 0.94), st)
		elif kind == "shop" and outer:
			_poster(R(px0, gd + 0.03, py0), R(px0 + pw, gd + 0.03, py1), Color(0.97, 0.96, 0.92), Color(0.75, 0.1, 0.12),
				"TO LET\nRETAIL UNIT\n%d m²\nCITY LETTINGS" % int(unit.get("size", 0)), Color(0.15, 0.15, 0.18), st)
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
	_entrance_approach(st, stone)
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
	var fascia_style := (_front_seed / 17) % 3
	if trading_here and not flagship:
		var trim_ink := accent_c.lerp(fascia, 0.27)
		match fascia_style:
			0:  # painted border with small mitred end plates
				for y: float in [fy + 0.11, fy + 0.66]:
					st.box(R(1.39, -0.326, y), R(W - 0.57, -0.304, y + 0.022), trim_ink)
			1:  # two aluminium cappings with a recessed name band
				for y: float in [fy + 0.015, fy + 0.71]:
					st.box(R(0.35, -0.336, y), R(W - 0.35, -0.304, y + 0.055), fc.lightened(0.19))
			_:  # inset tablet fitted to the centre of the frontage
				st.box(R(1.26, -0.329, fy + 0.10), R(W - 0.44, -0.304, fy + 0.70), fascia.darkened(0.23))
	if trading_here and sign_style == "lightbox":
		var bulb_d := -0.334 if fascia_style == 2 and not flagship else -0.305
		_glow_quad(R(1.27, bulb_d, fy + 0.13), R(W - 0.45, bulb_d, fy + 0.66), fascia * 0.9)
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
		var awning := not flagship and sign_style in ["painted", "script"]
		var c1 := ox.y + 0.45
		var cream := Color(0.95, 0.92, 0.84)
		var ay0 := oh + 0.30
		var ay1 := oh + 0.06
		var ad := -1.45
		var stripes := maxi(4, int((c1 - c0) / 0.42))
		for i in (stripes if awning else 0):
			var xa := lerpf(c0, c1, float(i) / stripes)
			var xb := lerpf(c0, c1, float(i + 1) / stripes)
			var sc := brand if i % 2 == 0 else cream
			st.sheet(R(xa, -0.28, ay0), R(xb, -0.28, ay0), R(xb, ad, ay1), R(xa, ad, ay1), sc)
			st.sheet(R(xa, ad, ay1), R(xb, ad, ay1), R(xb, ad, ay1 - 0.12), R(xa, ad, ay1 - 0.12), sc.darkened(0.08))
		if awning:
			for ex: float in [c0, c1]:
				st._tri(R(ex, -0.28, ay0), R(ex, ad, ay1), R(ex, -0.28, ay1), Vector3.RIGHT, fascia.darkened(0.2))
				st._tri(R(ex, -0.28, ay0), R(ex, -0.28, ay1), R(ex, ad, ay1), Vector3.LEFT, fascia.darkened(0.2))
			st.box(R(c0, -0.3, ay0 - 0.04), R(c1, -0.22, ay0 + 0.06), Color(0.12, 0.12, 0.13))  # roller box
		if flagship:
			# The front of the canopy carries the name where it stays
			# readable from below. The side display glazing stays clear.
			var canopy_half := minf(5.5, (door.y - door.x) * 0.5 + 2.5)
			var mid := (door.x + door.y) * 0.5
			var metal := fc.darkened(0.11)
			st.box(R(mid - canopy_half, -1.32, oh + 0.065), R(mid + canopy_half, -0.23, oh + 0.22), metal)
			st.box(R(mid - canopy_half, -1.36, oh + 0.07), R(mid + canopy_half, -1.32, oh + 0.45), fascia)
			_glow_quad(R(mid - canopy_half + 0.4, -1.17, oh + 0.055),
				R(mid + canopy_half - 0.4, -1.07, oh + 0.055), Color(0.95, 0.90, 0.79), true)
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
		blade.text = String(ident.get("initial", biz.name.left(1).to_upper()))
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
	if flagship and trading_here:
		_sign.position = R(W * 0.5, -1.368, oh + 0.262)
		_sign.pixel_size = 0.00355
		_sign.modulate = Color(0.98, 0.95, 0.89)
		_sign.width = 6.9 / _sign.pixel_size
	elif trading_here:
		var strip := minf(W - 1.8, 12.0)
		_sign.position.z = 0.354
		_sign.position.y = fy + (0.47 if fascia_style == 0 and W > 9.2 else 0.39)
		_fit_sign(_sign, strip - 0.32, 0.0046)
		if fascia_style == 0 and W > 9.2:
			var category := String(Premises.STREET_TITLES.get(unit.get("street_use", ""), {
				"convenience": "Groceries", "cafe": "Coffee & cakes", "bakery": "Bread & pastries",
				"takeaway": "Order & collect", "clothing": "Clothing", "phones": "Phones & repairs"
			}.get(type_id, "")))
			if category != "":
				_street_label(category.to_upper(), R(_sign.position.x, -0.354, fy + 0.24), strip * 0.65, _sign.modulate, "condensed", 0.0025)
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
## A low threshold is graded into the pavement. Larger level changes
## get an even flight of shallow steps ending at the surveyed street level.
const STEP_RISE := 0.145
const ENTRY_LANDING := 0.48
const ENTRY_TREAD := 0.33


func _entrance_approach(st: _Batch, stone: Color) -> void:
	var middle := (door.x + door.y) * 0.5
	var x0 := door.x - 0.19
	var x1 := door.y + 0.19
	var top_c := stone.lerp(Color(0.51, 0.49, 0.46), 0.58)
	if street_drop <= 0.19:
		# Meet the crossfall at both ends without extruding a full-width
		# step across the pavement. The threshold and ramp share collision.
		var run := clampf(street_drop * 11.0, 0.42, 2.15)
		var left := _street_y(x0, -run)
		var right := _street_y(x1, -run)
		if minf(left, right) >= -0.025:
			return
		if minf(left, right) >= -run * 0.15:
			_entrance_ramp(st, top_c, x0, x1, run, left, right)
			return
	var drop := maxf(street_drop, -_street_y(middle, -ENTRY_LANDING))
	var n := maxi(1, ceili(drop / STEP_RISE))
	# Recheck the bottom where the flight will actually meet the pavement.
	for i in 3:
		var depth := ENTRY_LANDING + ENTRY_TREAD * (n - 1)
		drop = maxf(drop, -_street_y(middle, -depth))
		n = maxi(1, ceili(drop / STEP_RISE))
	var base := -drop - 0.05
	# The landing (the top step), level with the shop floor.
	for i in n:
		var top := -drop * float(i) / float(n)
		var d0 := -ENTRY_LANDING - ENTRY_TREAD * i
		var d1 := 0.0 if i == 0 else d0 + ENTRY_TREAD
		var c := top_c.darkened(0.018 * i)
		st.box(R(x0, d0, base), R(x1, d1, top), c)
		st.box(R(x0, d0 - 0.012, top - 0.025), R(x1, d0 + 0.02, top), c.lightened(0.1))
		_solid(R(x0, d0, base), R(x1, d1, top))
	if n >= 3:
		var hx := x1 - 0.075
		var metal := Color(0.25, 0.25, 0.22)
		var far := -ENTRY_LANDING - ENTRY_TREAD * (n - 1) + 0.09
		var low := -drop * float(n - 1) / float(n)
		st.cylinder(R(hx, -0.13, 0.0), 0.018, 0.89, metal, 8)
		st.cylinder(R(hx, far, low), 0.018, 0.89, metal, 8)
		st.hull([R(hx - 0.022, -0.095, 0.87), R(hx + 0.022, -0.095, 0.87),
			R(hx + 0.022, -0.095, 0.912), R(hx - 0.022, -0.095, 0.912),
			R(hx - 0.022, far - 0.05, low + 0.87), R(hx + 0.022, far - 0.05, low + 0.87),
			R(hx + 0.022, far - 0.05, low + 0.912), R(hx - 0.022, far - 0.05, low + 0.912)], metal)


func _entrance_ramp(st: _Batch, col: Color, x0: float, x1: float, run: float, left: float, right: float) -> void:
	var base := minf(left, right) - 0.055
	var points := [R(x0, 0.025, base), R(x1, 0.025, base), R(x1, 0.025, 0.0), R(x0, 0.025, 0.0),
		R(x0, -run, base), R(x1, -run, base), R(x1, -run, right), R(x0, -run, left)]
	st.hull(points, col)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(points)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_col.add_child(collider)


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
func _poster(a: Vector3, b: Vector3, col: Color, band: Color, text: String, ink := Color(1.0, 0.98, 0.94), st: _Batch = null) -> void:
	_glow_quad(a, b, col * 0.75)
	var lo := a.min(b)
	var hi := a.max(b)
	if st:
		# The back of the lightbox, seen from inside the shop: a grey case
		# with a thin brand edge (it was a slab of glowing brand colour).
		st.box(Vector3(lo.x - 0.02, lo.y - 0.02, lo.z - 0.05), Vector3(hi.x + 0.02, hi.y + 0.02, lo.z - 0.004), Color(0.78, 0.78, 0.76))
		st.box(Vector3(lo.x - 0.02, hi.y - 0.04, lo.z - 0.054), Vector3(hi.x + 0.02, hi.y + 0.02, lo.z - 0.05), band.darkened(0.2))
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


func accent_col() -> Color:
	var a: Color = ident.get("accent", Color(0.95, 0.85, 0.2)) if ident is Dictionary else Color(0.95, 0.85, 0.2)
	return a


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
			xa = door.y + ENTRY_SIDE
			xb = W - 1.0
		"bakery", "phones":
			xa = 1.0
			xb = door.x - ENTRY_SIDE
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
			var offset := ENTRY_SIDE + 0.46
			var cx := (door.x - offset) if side < 0.0 else (door.y + offset)
			if cx - 0.3 < 0.4 or cx + 0.3 > W - 0.4:
				continue
			var y0 := _street_y(cx, -0.37)
			st.box(R(cx - 0.3, -0.62, y0 - 0.1), R(cx + 0.3, -0.12, y0 + 0.5), dark)
			st.box(R(cx - 0.32, -0.64, y0 + 0.46), R(cx + 0.32, -0.1, y0 + 0.52), dark.lightened(0.15))
			_batch_cone(st, R(cx, -0.37, y0 + 0.5), 0.3, 0.05, 0.95, Color(0.17, 0.36, 0.19))
			_solid(R(cx - 0.3, -0.62, y0), R(cx + 0.3, -0.12, y0 + 1.0))
	# The A-board, right of the door.
	var xa := maxf(W - 1.15, door.y + ENTRY_SIDE + (1.1 if plants else 0.55))
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
		_trade_board = lab
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
		var x1 := minf(1.35, door.x - ENTRY_SIDE - (1.0 if plants else 0.12))
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
		var tx := door.x - ENTRY_SIDE - (1.55 if plants else 0.98)
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
## Keeps the way in clear: a prop `w` wide starting at x0 (`d0` deep) that
## would stand in the corridor behind the door moves beside the door.
const ENTRY_CLEAR := 3.6
const ENTRY_SIDE := 0.9
const ENTRY_FORECOURT := 2.6


func _clear_of_entry(x0: float, x1: float, near_d: float, far_d: float) -> bool:
	return near_d >= ENTRY_CLEAR or far_d <= -ENTRY_FORECOURT \
		or x1 <= door.x - ENTRY_SIDE or x0 >= door.y + ENTRY_SIDE


func _beside_door(x0: float, w: float, d0: float) -> float:
	if _clear_of_entry(x0, x0 + w, d0, d0 + 1.1):
		return x0
	if door.y + ENTRY_SIDE + w < W - 0.6:
		return door.y + ENTRY_SIDE
	return maxf(0.6, door.x - ENTRY_SIDE - w)


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
	var bx := _beside_door(W * 0.42, 1.3, part_d - 2.0)
	if part_d > 4.0:
		st.box(R(bx, part_d - 2.0, 0.0), R(bx + 1.3, part_d - 0.9, 0.7), sheet)
		st.box(R(bx + 0.15, part_d - 1.85, 0.7), R(bx + 0.9, part_d - 1.1, 1.05), sheet.darkened(0.04))
		st.box(R(bx - 0.08, part_d - 2.05, 0.0), R(bx + 1.38, part_d - 0.85, 0.08), sheet.darkened(0.08))
		_solid(R(bx, part_d - 2.0, 0.0), R(bx + 1.3, part_d - 0.9, 1.05))
	# A stepladder and paint tins mid-floor.
	var ld := part_d * 0.55
	var lx := _beside_door(W * 0.3 - 0.3, 0.6, ld - 0.4) + 0.3
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
		var nm := String(ident.get("name", biz.name))
		return nm if String(ident.get("face", "")) in ["script", "retro"] else nm.to_upper()
	return "TO LET" if kind == "shop" else String(unit.get("name", "")).to_upper()


## `night`: the street's shut for the night (other people's shops with a
## roller shutter pull it down then).
func update_signs(trading: bool, night := false, occupied := false) -> void:
	if is_instance_valid(_trade_board):
		_trade_board.text = _aboard_text() if trading else "CLOSED"
	if kind == "shop" and (biz != null or not rival.is_empty()):
		_lighting_open = trading or occupied or is_instance_valid(_delivery_worker)
		for light in _sales_lights:
			light.light_energy = float(light.get_meta("open_energy")) * (1.0 if _lighting_open else 0.62)
		if is_instance_valid(_room_probe):
			_room_probe.ambient_color_energy = 0.66 if _lighting_open else 0.30
		if _trade_glow:
			_trade_glow.visible = _lighting_open
		if is_instance_valid(_sign_light):
			_sign_light.visible = trading and _lights_active
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
		elif public_display:
			_open_sign.text = "OPEN"
			_open_sign.modulate = Color(0.68, 0.95, 0.73)
		elif biz == null:
			_open_sign.text = "TO LET\n%s / day" % EmpireData.money(float(unit.get("rent", 0)))
			_open_sign.modulate = Color(1.0, 0.85, 0.3)
		else:
			_open_sign.text = "OPEN" if trading else "CLOSED"
			_open_sign.modulate = Color(0.4, 1.0, 0.55) if trading else Color(1.0, 0.4, 0.35)


## Lightweight mobile light toggle so distant/unoccupied shop interiors don't
## waste active light budget on exterior passes.
func set_exterior_lights_active(active: bool) -> void:
	_lights_active = active
	for light in _sales_lights:
		if is_instance_valid(light):
			light.visible = active
	if is_instance_valid(_sign_light):
		_sign_light.visible = active and _lighting_open


## Fixture positions in fill order: the back wall (fridges first), then the
## middle gondola's two sides, then the left wall.
func _fixture_sites(part_d: float) -> Array:
	var sites: Array = []
	var x := 0.35
	var bay_gap := 0.05
	# When fitting rooms occupy the back corner, start the wall run beside
	# them. Leaving an empty 1.9 m module here wastes the usable wall.
	if _fitting_clear.has_area() and _fitting_clear.position.y <= -part_d + 0.02:
		x = maxf(x, _fitting_clear.end.x + 0.025)
		bay_gap = 0.025
	while x + BAY <= W - 2.6:
		sites.append({"back": R(x, part_d - 0.02, 0.0), "along": Vector3.RIGHT, "out": Vector3(0, 0, 1), "wall": "back"})
		x += BAY + bay_gap
	if unit.get("flagship", false):
		var aisle_ends: Array = []
		var min_gx := 3.8
		var max_gx := W - 4.8
		var gx := min_gx
		while gx <= max_gx:
			if absf(gx - W * 0.5) > 1.9:
				aisle_ends.append(gx)
			gx += 3.35
		var d_min := maxf(5.0, ENTRY_CLEAR + 0.4)
		var d_max := part_d - 1.8
		var d := d_min
		while d + BAY <= d_max:
			for x_pos: float in aisle_ends:
				# Keep flagship gondolas cleanly clear of mezzanine stairs/gallery and counter zone.
				if _has_mezzanine() and x_pos < 7.6 and d < 16.5:
					continue
				if x_pos + 1.0 >= W - 3.6:
					continue
				_append_shop_bay(sites, x_pos, d)
			d += BAY + 0.06
			# Leave a transverse route between the front and back of long aisles.
			if absf(d - (d_min + part_d) * 0.5) < BAY:
				d += 1.65
	else:
		var gx0 := 1.95
		var gx1 := W - 3.7
		if gx1 - gx0 >= 1.15:
			var gc := lerpf(gx0, gx1, [0.42, 0.5, 0.58][_front_seed % 3])
			var d := ENTRY_CLEAR + 0.04 if not _clear_of_entry(gc - 1.0, gc + 1.0, 2.2, 2.2 + BAY) else 2.2
			while d + BAY <= part_d - 1.0:
				# (+x side faces right, −x side faces left; both run front→back)
				sites.append({"back": R(gc + 0.02, d + BAY, 0.0), "along": Vector3(0, 0, 1), "out": Vector3.RIGHT, "wall": "gondola"})
				sites.append({"back": R(gc - 0.02, d, 0.0), "along": Vector3(0, 0, -1), "out": Vector3.LEFT, "wall": "gondola"})
				d += BAY + 0.05
	var d2 := (16.4 if _has_mezzanine() else 1.3)
	while d2 + BAY <= part_d - 0.9:
		sites.append({"back": R(0.05, d2 + BAY, 0.0), "along": Vector3(0, 0, 1), "out": Vector3.RIGHT, "wall": "left"})
		d2 += BAY + 0.05
	if _fitting_clear.has_area():
		return sites.filter(func(site: Dictionary) -> bool:
			var back: Vector3 = site["back"]
			var edge := back + (site["along"] as Vector3) * BAY + (site["out"] as Vector3) * 0.96
			var lo := Vector2(minf(back.x, edge.x), minf(back.z, edge.z))
			var hi := Vector2(maxf(back.x, edge.x), maxf(back.z, edge.z))
			return not Rect2(lo, hi - lo).intersects(_fitting_clear))
	return sites


func _append_shop_bay(sites: Array, x: float, d: float) -> void:
	sites.append({"back": R(x + 0.025, d + BAY, 0.0), "along": Vector3.BACK, "out": Vector3.RIGHT, "wall": "gondola"})
	sites.append({"back": R(x - 0.025, d, 0.0), "along": Vector3.FORWARD, "out": Vector3.LEFT, "wall": "gondola"})


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
	# Shops with nothing made for the back wall (phones, clothes) put their
	# wall shelving there instead: it's the wall you see from the door.
	var back_free := not want.any(func(w): return w[0] in ["fridge", "coffee", "hotcab", "cake"])
	for w in want:
		var site: Dictionary
		var k: String = w[0]
		if k in ["fridge", "coffee", "hotcab", "cake"] and not back_sites.is_empty():
			site = back_sites.pop_front()
		elif back_free and k == "shelf" and not back_sites.is_empty() and not unit.get("flagship", false):
			site = back_sites.pop_front()
		elif k in ["table", "techtable"] and not mid_sites.is_empty():
			site = mid_sites.pop_front()
			_mid_used = true
		elif unit.get("flagship", false) and k in ["rail", "shelf"] and not mid_sites.is_empty():
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
			if not unit.get("flagship", false):
				push_warning("ShopInterior: no room for a %s in %s" % [w[0], unit.get("id")])
			continue
		_fixture(st, String(w[0]), int(w[1]), site)
	# A single feature panel avoids repeating the same ad across empty bays.
	if not back_sites.is_empty():
		var featured := _front_seed % back_sites.size()
		_wall_graphic(st, back_sites[featured], featured)
	if type_id == "convenience" and not unit.get("flagship", false) and _mid_used:
		var first: Dictionary = sites.filter(func(s): return s["wall"] == "gondola").front()
		var first_back: Vector3 = first["back"]
		_end_cap(st, first_back.x - 0.02, -first_back.z - BAY)


## A promotional end cap on the front of the central gondola: a low unit
## stacked with offer packs under a hanging OFFER card, facing the door –
## what you see first in a real corner shop. Kept out of the way in.
func _end_cap(st: _Batch, gc: float, aisle_start: float) -> void:
	var x0 := gc - 0.6
	var x1 := gc + 0.6
	var d0 := aisle_start - 0.60
	var d1 := aisle_start - 0.02
	if not _clear_of_entry(x0, x1, d0, d1):
		return
	var body := Color(0.2, 0.22, 0.25)
	st.box(R(x0, d0, 0.0), R(x1, d1, 0.12), body)                       # plinth
	for k in 3:
		var y := 0.12 + k * 0.36
		st.box(R(x0 + 0.03, d0 + 0.03, y), R(x1 - 0.03, d1, y + 0.03), Color(0.78, 0.78, 0.76))  # shelf
		# Offer packs stacked on each step, in the shop's colours and a
		# couple of bright promo ones.
		var cols := [brand.lightened(0.2), Color(0.95, 0.8, 0.2), Color(0.85, 0.2, 0.15), brand.darkened(0.1)]
		for j in 5:
			var px := x0 + 0.08 + j * 0.21
			st.box(R(px, d0 + 0.06, y + 0.03), R(px + 0.18, d0 + 0.4, y + 0.27), cols[(j + k) % cols.size()])
			st.box(R(px + 0.03, d0 + 0.055, y + 0.1), R(px + 0.15, d0 + 0.06, y + 0.2), Color(0.96, 0.95, 0.92))
	st.box(R(x0, d1 - 0.05, 0.0), R(x1, d1, 1.3), body)                  # back panel
	# Hanging card on two rods.
	st.box(R(x0 + 0.1, d0 + 0.2, 2.0), R(x1 - 0.1, d0 + 0.24, 2.45), Color(0.95, 0.8, 0.2))
	for e: float in [x0 + 0.2, x1 - 0.2]:
		st.box(R(e - 0.01, d0 + 0.21, 2.45), R(e + 0.01, d0 + 0.23, H), Color(0.3, 0.3, 0.32))
	var lab := Label3D.new()
	lab.text = "OFFERS"
	lab.font = EmpireStyle.font("black")
	lab.font_size = 64
	lab.pixel_size = 0.0028
	lab.shaded = false
	lab.double_sided = false
	lab.outline_size = 0
	lab.modulate = Color(0.75, 0.1, 0.1)
	lab.position = R(gc, d0 + 0.19, 2.22)
	_static.add_child(lab)
	_solid(R(x0, d0, 0.0), R(x1, d1, 1.3))


const WALL_LINES := {"convenience": ["OPEN LATE\nEVERY DAY", "LOCAL &\nFRIENDLY", "FRESH\nEVERY MORNING"],
	"clothing": ["NEW\nSEASON", "STYLE\nFOR LESS"], "cafe": ["GOOD\nCOFFEE", "BAKED\nIN-HOUSE"],
	"takeaway": ["HOT &\nFRESH", "OPEN\nTILL LATE"], "bakery": ["BAKED\nTHIS MORNING", "REAL\nBREAD"],
	"phones": ["REPAIRS\nWHILE U WAIT", "LATEST\nDEVICES"]}


func _wall_graphic(st: _Batch, site: Dictionary, i: int) -> void:
	var al: Vector3 = site["along"]
	var out: Vector3 = site["out"]
	var bk: Vector3 = site["back"]
	var a := bk + al * 0.2 + Vector3.UP * 0.95
	var b := bk + al * (BAY - 0.2) + out * 0.05 + Vector3.UP * 2.2
	st.box(a.min(b), a.max(b), brand.darkened(0.35))
	var ga := bk + al * 0.28 + out * 0.051 + Vector3.UP * 1.03
	var gb := bk + al * (BAY - 0.28) + out * 0.055 + Vector3.UP * 2.12
	_glow_quad(ga.min(gb), ga.max(gb), brand * 0.8)
	var lines: Array = WALL_LINES.get(type_id, WALL_LINES["convenience"])
	var lab := Label3D.new()
	lab.text = String(lines[(i + _front_seed) % lines.size()])
	lab.font = ShopStyle.font(String(ident.get("face", ""))) if biz else EmpireStyle.font("black")
	lab.font_size = 96
	# (Longest line ~13 characters across the ~1.3 m panel.)
	lab.pixel_size = 0.0015
	lab.line_spacing = -10.0
	lab.shaded = false
	lab.double_sided = false
	lab.outline_size = 0
	lab.modulate = Color(1, 0.99, 0.95)
	lab.position = bk + al * (BAY * 0.5) + out * 0.06 + Vector3.UP * 1.58
	lab.basis = Basis.looking_at(-out, Vector3.UP)
	_static.add_child(lab)


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
			# An upright drinks fridge you can see into: a pale cabinet, a dark
			# lit interior with wire shelves at the slot heights, and two glass
			# doors with chrome frames and handles.
			var shell := Color(0.86, 0.88, 0.9)
			var inner := Color(0.17, 0.2, 0.24)
			var bk := o - out * dep
			var bx := func(p0: Vector3, p1: Vector3, c: Color) -> void: st.box(p0.min(p1), p0.max(p1), c)
			var base_h := 0.24
			var top_h := tall - 0.2
			bx.call(bk, bk + al * BAY + out * 0.05 + Vector3.UP * tall, inner)                 # back
			for e3: float in [0.0, BAY - 0.04]:                                                 # sides
				bx.call(bk + al * e3, o + al * (e3 + 0.04) + Vector3.UP * tall, shell)
			bx.call(bk, o + al * BAY + Vector3.UP * base_h, shell.darkened(0.25))               # plinth
			bx.call(bk + Vector3.UP * top_h, o + al * BAY + Vector3.UP * tall, brand)           # canopy
			for ly: float in FRIDGE_LEVELS:                                                     # wire shelves
				bx.call(bk + al * 0.04 + out * 0.05 + Vector3.UP * (ly - 0.018), o + al * (BAY - 0.04) - out * 0.03 + Vector3.UP * ly, Color(0.55, 0.57, 0.6))
			# Light strip inside under the canopy, and the glow off the back.
			_glow_quad(bk + al * 0.06 + out * 0.1 + Vector3.UP * (top_h - 0.01), o + al * (BAY - 0.06) - out * 0.08 + Vector3.UP * (top_h - 0.01), Color(0.92, 0.97, 1.0) * 1.4, true)
			_glow_quad_v(bk + al * 0.06 + out * 0.051 + Vector3.UP * (base_h + 0.02), bk + al * (BAY - 0.06) + out * 0.051 + Vector3.UP * (top_h - 0.04), out, Color(0.35, 0.45, 0.55) * 0.45)
			# Glass doors, frames, handles.
			_glass_box((o - out * 0.025 + Vector3.UP * base_h).min(o + al * BAY + Vector3.UP * top_h), (o - out * 0.025 + Vector3.UP * base_h).max(o + al * BAY + Vector3.UP * top_h))
			var chrome := Color(0.72, 0.74, 0.77)
			for e4: float in [0.0, BAY * 0.5 - 0.015, BAY - 0.03]:
				bx.call(o + al * e4 + Vector3.UP * base_h, o + al * (e4 + 0.03) - out * 0.03 + Vector3.UP * top_h, chrome)
			for e5: float in [BAY * 0.5 - 0.07, BAY * 0.5 + 0.05]:
				bx.call(o + al * e5 + out * 0.01 + Vector3.UP * 0.8, o + al * (e5 + 0.02) + out * 0.04 + Vector3.UP * 1.45, Color(0.2, 0.2, 0.22))
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
			# Category header board, printed with what the bay holds
			# (_update_headers: it follows the stock).
			st.box(back0 + Vector3.UP * (tall - 0.02) + out * 0.02, back0 + al * BAY + out * 0.06 + Vector3.UP * (tall + 0.22), brand)
			var hl := Label3D.new()
			hl.font = ShopStyle.font(String(ident.get("face", ""))) if biz else EmpireStyle.font("black")
			hl.font_size = 64
			hl.pixel_size = 0.0022
			hl.shaded = false
			hl.double_sided = false
			hl.outline_size = 0
			hl.modulate = Color(1, 0.99, 0.95) if brand.get_luminance() < 0.55 else Color(0.08, 0.08, 0.1)
			hl.position = back0 + al * (BAY * 0.5) + out * 0.065 + Vector3.UP * (tall + 0.1)
			hl.basis = Basis.looking_at(-out, Vector3.UP)
			hl.set_meta("fixture", [k, u])
			_headers.append(hl)
			_static.add_child(hl)
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
		# A shelf-edge ticket: the price large, the name small under it
		# (sized to fit the ticket – long names used to spill off it).
		lab.font_size = 30
		lab.pixel_size = 0.0014
		lab.line_spacing = -6.0
		lab.font = EmpireStyle.font("black")
		lab.shaded = false
		lab.double_sided = false
		lab.modulate = Color(0.08, 0.08, 0.1)
		lab.outline_size = 0
		# Tag on the shelf edge, facing the aisle.
		lab.position = o + al * (a0 + wdt * 0.5) + out * 0.02 + Vector3.UP * (y - 0.07)
		lab.basis = Basis.looking_at(-out, Vector3.UP)
		lab.set_meta("slot", si)
		_labels.add_child(lab)
		var tag := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(minf(wdt, 0.42), 0.085)
		tag.mesh = qm
		tag.material_override = _mat("tag")
		tag.position = lab.position - out * 0.004
		tag.basis = lab.basis
		_static.add_child(tag)


## The stockroom door: a real frame (architrave both sides), a solid
## swing door with a porthole, kick plate and push plate that opens on its own
## for you and your staff (into the stockroom, away from the shop floor), and
## a lit STOCKROOM sign above it.
var _door_hinge: Node3D
var _door_handle: Marker3D
var _hero_reaching := false
var _door_open := 0.0
var _door_at := Vector3.ZERO
const DOOR_OPEN_ANGLE := 1.75  # rad (about 100°)


func _stock_door(st: _Batch, part_d: float, dw0: float, dw1: float, trim: Color) -> void:
	var frame := Color(0.93, 0.92, 0.89)
	for side: float in [-1.0, 1.0]:
		var dd := part_d - 0.03 if side < 0.0 else part_d + 0.17
		var d2 := part_d if side < 0.0 else part_d + 0.14
		st.box(R(dw0 - 0.09, dd, 0.0), R(dw0, d2, 2.39), frame)
		st.box(R(dw1, dd, 0.0), R(dw1 + 0.09, d2, 2.39), frame)
		st.box(R(dw0 - 0.09, dd, 2.3), R(dw1 + 0.09, d2, 2.39), frame)
	# Jamb linings (the reveal through the wall).
	st.box(R(dw0 - 0.01, part_d, 0.0), R(dw0, part_d + 0.14, 2.3), frame.darkened(0.06))
	st.box(R(dw1, part_d, 0.0), R(dw1 + 0.01, part_d + 0.14, 2.3), frame.darkened(0.06))
	# Threshold strip.
	st.box(R(dw0, part_d - 0.02, 0.0), R(dw1, part_d + 0.16, 0.012), Color(0.62, 0.6, 0.55))
	# The sign: a dark plate proud of the wall above the frame, lettered and
	# lit from a strip underneath.
	var cx := (dw0 + dw1) * 0.5
	_door_at = R(cx, part_d + 0.07, 0.0)
	var sw := maxf(dw1 - dw0 + 0.5, 1.7)
	var plate := Color(0.09, 0.1, 0.12)
	st.box(R(cx - sw * 0.5, part_d - 0.06, 2.44), R(cx + sw * 0.5, part_d - 0.005, 2.86), plate)
	st.box(R(cx - sw * 0.5, part_d - 0.065, 2.44), R(cx + sw * 0.5, part_d - 0.06, 2.47), brand.lightened(0.15))
	_glow_quad(R(cx - sw * 0.5 + 0.06, part_d - 0.066, 2.441), R(cx + sw * 0.5 - 0.06, part_d - 0.066, 2.462), Color(1.0, 0.86, 0.5))
	var sgn := Label3D.new()
	sgn.name = "StockroomSign"
	sgn.text = "STOCKROOM"
	sgn.font = EmpireStyle.font("black")
	sgn.font_size = 72
	sgn.pixel_size = 0.0036
	sgn.shaded = false
	sgn.double_sided = false
	sgn.outline_size = 0
	sgn.modulate = Color(1.0, 0.97, 0.9)
	sgn.position = R(cx, part_d - 0.07, 2.68)
	_static.add_child(sgn)
	var sub := Label3D.new()
	sub.text = "STAFF ONLY  ·  DELIVERIES"
	sub.font = EmpireStyle.font("bold")
	sub.font_size = 40
	sub.pixel_size = 0.0028
	sub.shaded = false
	sub.double_sided = false
	sub.outline_size = 0
	sub.modulate = brand.lightened(0.55)
	sub.position = R(cx, part_d - 0.07, 2.53)
	_static.add_child(sub)
	# The door leaf: hinged on the right jamb.
	var lw := dw1 - dw0 - 0.02
	var leaf_c := brand.darkened(0.35).lerp(Color(0.55, 0.57, 0.6), 0.45)
	var own := biz != null and rival.is_empty() and not public_display
	var lb := _Batch.new()
	lb.box(Vector3(-lw, 0.015, -0.022), Vector3(0.0, 2.28, 0.022), leaf_c)
	for f: float in [-1.0, 1.0]:
		var z0 := 0.022 * f
		var z1 := 0.027 * f
		lb.box(Vector3(-lw + 0.04, 0.02, minf(z0, z1)), Vector3(-0.04, 0.3, maxf(z0, z1)), Color(0.72, 0.73, 0.75))  # kick plate
		lb.box(Vector3(-lw + 0.08, 1.05, minf(z0, z1)), Vector3(-lw + 0.18, 1.35, maxf(z0, z1)), Color(0.78, 0.79, 0.8))  # push plate
		lb.box(Vector3(-lw * 0.5 - 0.17, 1.42, minf(z0, z1)), Vector3(-lw * 0.5 + 0.17, 1.76, maxf(z0, z1)), Color(0.86, 0.87, 0.88))  # window frame
		var z2 := 0.028 * f
		lb.box(Vector3(-lw * 0.5 - 0.13, 1.46, minf(z1, z2)), Vector3(-lw * 0.5 + 0.13, 1.72, maxf(z1, z2)), Color(0.16, 0.24, 0.3))  # vision panel
	if own:
		_door_hinge = Node3D.new()
		_door_hinge.name = "StockDoor"
		_door_hinge.position = R(dw1, part_d + 0.07, 0.0)
		_door_handle = Marker3D.new()
		_door_handle.position = Vector3(-lw + 0.13, 1.2, 0.044)
		_door_hinge.add_child(_door_handle)
		var lm := MeshInstance3D.new()
		lm.mesh = lb.commit()
		lm.material_override = _mat("vc")
		_door_hinge.add_child(lm)
		var tag := Label3D.new()
		tag.text = "STAFF ONLY"
		tag.font = EmpireStyle.font("black")
		tag.font_size = 40
		tag.pixel_size = 0.0026
		tag.shaded = false
		tag.outline_size = 0
		tag.modulate = Color(1.0, 0.95, 0.85)
		tag.position = Vector3(-lw * 0.5, 1.92, 0.03)
		_door_hinge.add_child(tag)
		_static.add_child(_door_hinge)
		_door_open = 0.0
		set_process(true)
	else:
		# Someone else's shop (or vacant/public): the door stays shut and physically solid.
		var o := R(dw1, part_d + 0.07, 0.0)
		st.box(o + Vector3(-lw, 0.015, -0.022), o + Vector3(0.0, 2.28, 0.022), leaf_c)
		st.box(o + Vector3(-lw * 0.5 - 0.13, 1.46, 0.0225), o + Vector3(-lw * 0.5 + 0.13, 1.72, 0.027), Color(0.16, 0.24, 0.3))
		st.box(o + Vector3(-lw + 0.04, 0.02, 0.0225), o + Vector3(-0.04, 0.3, 0.027), Color(0.72, 0.73, 0.75))
		_solid(o + Vector3(-lw, 0.0, -0.07), o + Vector3(0.0, 2.3, 0.07))


## Opens the stockroom door for anyone walking up to it (you, your staff),
## swinging it gently shut again behind them.
func _process(dt: float) -> void:
	_update_delivery(dt)
	if is_instance_valid(_public_visitor) and _public_visitor.arrived():
		_public_wait -= dt
		if _public_wait <= 0.0:
			_public_stop = (_public_stop + 1) % 3
			var stops := [door_in, R(W * 0.33, D * 0.48, 0.0), R(W * 0.65, D * 0.57, 0.0)]
			_public_visitor.set_path(path(_public_visitor.position, stops[_public_stop]))
			_public_wait = 2.2
	if _door_hinge == null or not is_instance_valid(_door_hinge):
		if not is_instance_valid(_public_visitor):
			set_process(false)
		return
	var at := to_world(_door_at)
	var want := 0.0
	var reaching := false
	for n in get_tree().get_nodes_in_group("door_openers"):
		var p: Vector3 = (n as Node3D).global_position
		if absf(p.y - at.y) < 2.2 and Vector2(p.x - at.x, p.z - at.z).length() < 1.7:
			want = 1.0
		if n is Player and is_instance_valid(_door_handle):
			var flat := Vector2(p.x - at.x, p.z - at.z)
			reaching = flat.length_squared() < 0.95 * 0.95 and absf(p.y - at.y) < 1.7
			if reaching and not _hero_reaching:
				var rig := n.get_node_or_null("Rig") as CharacterRig
				if rig:
					rig.reach_for_handle(_door_handle)
	_hero_reaching = reaching
	if is_equal_approx(want, _door_open):
		return
	_door_open = move_toward(_door_open, want, dt * (2.6 if want > _door_open else 1.1))
	var e := _door_open * _door_open * (3.0 - 2.0 * _door_open)
	_door_hinge.rotation.y = -DOOR_OPEN_ANGLE * e


## Present a settled stock order. The simulation has already received it.
func show_stock_delivery(truck_pose: Transform3D, truck_mesh: Mesh, approach: Vector3) -> void:
	if is_instance_valid(_delivery_worker) or walk.is_empty():
		return
	for spot: Dictionary in spots:
		if spot["kind"] != "rack":
			continue
		var route := path(door_in, spot["pos"])
		if route.is_empty():
			continue
		_delivery_start = door_out
		_delivery_worker = ShopPerson.new(hash(unit["id"]), true)
		_delivery_worker.name = "DeliveryWorker"
		_delivery_worker.position = _delivery_start
		_delivery_worker.floor_height = _delivery_floor_height
		add_child(_delivery_worker)
		_delivery_worker.position.y = _delivery_floor_height(_delivery_start)
		_delivery_worker.set_carry(true)
		route.insert(0, door_in)
		_delivery_phase = 0
		_delivery_wait = 0.0
		if truck_mesh:
			var truck := AnimatableBody3D.new()
			truck.name = "DeliveryVan"
			truck.sync_to_physics = false
			truck.collision_layer = Car.BODY_LAYER
			truck.collision_mask = 0
			var shell := MeshInstance3D.new()
			shell.mesh = truck_mesh
			truck.add_child(shell)
			var bounds := truck_mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = bounds.size
			var collision := CollisionShape3D.new()
			collision.shape = box
			collision.position = bounds.get_center()
			truck.add_child(collision)
			add_child(truck)
			truck.global_transform = truck_pose
			_delivery_truck = truck
		if truck_mesh and approach != Vector3.INF:
			_delivery_phase = -1
			_delivery_worker.hide()
			_delivery_truck.global_position = approach
			var arrival := create_tween()
			arrival.tween_property(_delivery_truck, "global_position", truck_pose.origin, 1.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			arrival.tween_callback(_begin_unload.bind(route))
		else:
			_begin_unload(route)
		refresh_goods()
		set_process(true)
		break


func _begin_unload(route: PackedVector3Array) -> void:
	if is_instance_valid(_delivery_worker):
		_delivery_worker.show()
		_delivery_worker.set_path(route)
		_delivery_phase = 0


func _delivery_floor_height(at: Vector3) -> float:
	if at.z < -1.0:
		return 0.0
	var p := to_world(Vector3(at.x, 0.0, at.z))
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p - Vector3.UP * 1.9,
		CityWorld.HUMAN_LAYER | 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return to_local(hit.position).y if not hit.is_empty() else at.y


func _update_delivery(dt: float) -> void:
	if _delivery_phase < 0 or not is_instance_valid(_delivery_worker) or not _delivery_worker.arrived():
		return
	if _delivery_phase == 0:
		_delivery_worker.set_carry(false)
		_delivery_wait = 0.85
		_delivery_phase = 1
	elif _delivery_phase == 1:
		_delivery_wait -= dt
		if _delivery_wait <= 0.0:
			_delivery_worker.set_path(path(_delivery_worker.position, _delivery_start))
			_delivery_phase = 2
	else:
		_delivery_worker.queue_free()
		_delivery_worker = null
		if is_instance_valid(_delivery_truck):
			_delivery_truck.queue_free()
		_delivery_truck = null


func _backroom(st: _Batch, part_d: float, dw0: float, dw1: float) -> void:
	# Racking along the back wall (cases drawn by refresh_goods).
	var r0 := 0.3
	var r1 := maxf(dw0 - 0.6, 2.5)
	var rd0 := D - 0.75
	var rd1 := D - 0.08
	for y: float in [0.1, 0.85, 1.6]:
		st.box(R(r0, rd0 + 0.04, y + 0.02), R(r1, rd1 - 0.04, y + 0.04), Color(0.62, 0.64, 0.66))  # steel decking
		st.box(R(r0, rd0, y - 0.04), R(r1, rd0 + 0.05, y + 0.05), Color(0.92, 0.45, 0.1))  # front beam
		st.box(R(r0, rd1 - 0.05, y - 0.04), R(r1, rd1, y + 0.05), Color(0.92, 0.45, 0.1))  # back beam
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
	_backroom_dressing(st, part_d, dw0, dw1, r0, r1, rd0, dx0)


## A working stockroom, not a bare box: sealed grey floor with a yellow
## walkway from the door to the racking, bay labels on the uprights, a strip
## light, a sack truck by the door, flattened boxes, a mop bucket, and a
## rota/notice board over the desk.
func _backroom_dressing(st: _Batch, part_d: float, dw0: float, dw1: float, r0: float, r1: float, rd0: float, dx0: float) -> void:
	var d0 := part_d + 0.14
	st.box(R(0.06, d0, 0.0), R(W - 0.06, D - 0.06, 0.017), Color(0.47, 0.5, 0.52))  # sealed concrete (over the shop tiles)
	var yel := Color(0.98, 0.78, 0.12)
	# Walkway: through the door, then along the racking.
	st.box(R(dw0 + 0.02, d0 + 0.05, 0.017), R(dw0 + 0.08, rd0 - 0.6, 0.021), yel)
	st.box(R(dw1 - 0.08, d0 + 0.05, 0.017), R(dw1 - 0.02, D - 1.4, 0.021), yel)
	st.box(R(r0, rd0 - 0.12, 0.017), R(dw0 + 0.08, rd0 - 0.06, 0.021), yel)
	# Keep-clear hatching in front of the door.
	for i in 4:
		var x := dw0 + 0.15 + i * (dw1 - dw0 - 0.3) / 3.0
		st.box(R(x - 0.03, d0 + 0.1, 0.017), R(x + 0.03, d0 + 0.75, 0.021), yel)
	# Bay labels on the racking uprights (A, B…), yellow plates at eye level.
	var bays := ["A", "B", "C", "D"]
	var xs := [r0, (r0 + r1) * 0.5, r1]
	for i in xs.size() - 1:
		var mx := (float(xs[i]) + float(xs[i + 1])) * 0.5
		st.box(R(mx - 0.24, rd0 - 0.035, 1.98), R(mx + 0.24, rd0 - 0.005, 2.26), yel)
		var bl := Label3D.new()
		bl.text = "BAY " + bays[i]
		bl.font = EmpireStyle.font("black")
		bl.font_size = 56
		bl.pixel_size = 0.0034
		bl.shaded = false
		bl.outline_size = 0
		bl.double_sided = false
		bl.modulate = Color(0.08, 0.08, 0.1)
		bl.position = R(mx, rd0 - 0.04, 2.12)
		_static.add_child(bl)
	# Strip light over the walkway.
	_glow_quad(R(W * 0.25, D - 1.6, H - 0.02), R(W * 0.75, D - 1.45, H - 0.02), Color(0.95, 0.97, 1.0), true)
	# Sack truck by the door (left of it, inside).
	var tx := dw0 - 0.45
	var td := d0 + 0.35
	if tx > r1 + 0.2 or td < rd0 - 1.0:
		var red := Color(0.75, 0.12, 0.1)
		st.box(R(tx - 0.2, td, 0.05), R(tx - 0.17, td + 0.04, 1.25), red)
		st.box(R(tx + 0.17, td, 0.05), R(tx + 0.2, td + 0.04, 1.25), red)
		st.box(R(tx - 0.2, td, 1.18), R(tx + 0.2, td + 0.04, 1.22), red)
		st.box(R(tx - 0.2, td - 0.25, 0.02), R(tx + 0.2, td, 0.05), Color(0.3, 0.3, 0.32))  # toe plate
		for wx: float in [-0.24, 0.2]:
			st.box(R(tx + wx, td, 0.0), R(tx + wx + 0.05, td + 0.2, 0.2), Color(0.08, 0.08, 0.09))
	# Flattened boxes and a mop bucket in the far-left corner.
	var kraft := Color(0.66, 0.5, 0.32)
	if r0 > 0.2 or part_d + 1.2 < rd0:
		for k in 4:
			st.box(R(0.12, d0 + 0.2 + k * 0.012, 0.0 + k * 0.02), R(0.85, d0 + 0.95, 0.02 + k * 0.02), kraft.darkened(0.05 * k))
		st.box(R(0.15, d0 + 1.15, 0.0), R(0.5, d0 + 1.45, 0.3), Color(0.95, 0.75, 0.1))  # bucket
		st.box(R(0.3, d0 + 1.28, 0.3), R(0.33, d0 + 1.31, 1.35), Color(0.55, 0.42, 0.28))  # mop handle
	# Rota / notice board over the desk.
	st.box(R(W - 0.04, D - 1.25, 1.35), R(W - 0.015, D - 0.15, 2.05), Color(0.6, 0.45, 0.3))
	var papers := [Color(0.97, 0.97, 0.95), Color(1.0, 0.92, 0.55), Color(0.75, 0.9, 1.0), Color(0.97, 0.97, 0.95)]
	for k in papers.size():
		var pd0 := D - 1.15 + k * 0.25
		st.box(R(W - 0.045, pd0, 1.5 + (k % 2) * 0.18), R(W - 0.04, pd0 + 0.2, 1.78 + (k % 2) * 0.18), papers[k])


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
	# Industrial floor safety-yellow pedestrian & loading-bay lane stripes.
	var saf_y := Color(0.92, 0.72, 0.12)
	st.box(R(1.35, 0.8, 0.008), R(1.48, D - 1.4, 0.016), saf_y)
	st.box(R(W - 1.48, 0.8, 0.008), R(W - 1.35, D - 1.4, 0.016), saf_y)
	# Overhead high-bay industrial LED luminaire bars across the warehouse ceiling.
	for lx_f: float in [0.28, 0.72]:
		var lx := W * lx_f
		st.box(R(lx - 0.12, 1.8, H - 0.24), R(lx + 0.12, D - 1.6, H - 0.12), Color(0.24, 0.25, 0.27))
		_glow_quad(R(lx - 0.09, 2.2, H - 0.248), R(lx + 0.09, D - 2.0, H - 0.248), Color(0.96, 0.98, 1.0) * 1.25, true)
	# Parked yellow electric warehouse forklift near the back-right racking bay.
	if W >= 8.5 and D >= 8.0:
		var fx := W - 2.35
		var fz := D - 2.35
		var fy_c := Color(0.92, 0.64, 0.08)
		var fk_dk := Color(0.12, 0.13, 0.14)
		# Counterweight body & cab
		st.box(R(fx - 0.52, fz - 0.72, 0.24), R(fx + 0.52, fz + 0.72, 0.92), fy_c)
		st.box(R(fx - 0.54, fz + 0.25, 0.24), R(fx + 0.54, fz + 0.78, 1.04), fk_dk)
		# Overhead safety roll-cage posts & roof guard
		for sx: float in [-0.46, 0.46]:
			for sz: float in [-0.36, 0.42]:
				st.box(R(fx + sx - 0.04, fz + sz - 0.04, 0.92), R(fx + sx + 0.04, fz + sz + 0.04, 2.02), fk_dk)
		st.box(R(fx - 0.50, fz - 0.42, 2.02), R(fx + 0.50, fz + 0.46, 2.08), fk_dk)
		# Vertical steel mast & twin steel forks with a loaded pallet
		for sx: float in [-0.30, 0.30]:
			st.box(R(fx + sx - 0.05, fz - 0.86, 0.12), R(fx + sx + 0.05, fz - 0.74, 2.45), fk_dk)
			st.box(R(fx + sx - 0.06, fz - 1.72, 0.08), R(fx + sx + 0.06, fz - 0.80, 0.14), Color(0.32, 0.34, 0.36))
		# Four rubber tyres
		for sx: float in [-0.54, 0.54]:
			for sz: float in [-0.46, 0.48]:
				st.box(R(fx + sx - 0.10, fz + sz - 0.22, 0.0), R(fx + sx + 0.10, fz + sz + 0.22, 0.42), fk_dk)
		# Wooden Euro pallet + stacked bulk cases on the forks
		st.box(R(fx - 0.52, fz - 1.70, 0.14), R(fx + 0.52, fz - 0.88, 0.26), Color(0.56, 0.42, 0.24))
		st.box(R(fx - 0.46, fz - 1.64, 0.26), R(fx + 0.46, fz - 0.94, 0.92), Color(0.76, 0.62, 0.44))
		_solid(R(fx - 0.64, fz - 1.75, 0.0), R(fx + 0.64, fz + 0.82, 2.45))
	# Trade counter facing the entrance.
	var tx := (ox.x + ox.y) * 0.5
	st.box(R(tx - 1.8, 4.2, 0.0), R(tx + 1.8, 4.9, 1.05), Color(0.25, 0.27, 0.3))
	st.box(R(tx - 1.85, 4.15, 1.05), R(tx + 1.85, 4.95, 1.1), Color(0.88, 0.88, 0.85))
	_solid(R(tx - 1.8, 4.2, 0.0), R(tx + 1.8, 4.9, 1.1))
	st.box(R(tx - 0.2, 4.6, 1.1), R(tx + 0.2, 4.65, 1.45), Color(0.05, 0.05, 0.06))
	_glow_quad(R(tx - 0.18, 4.58, 1.14), R(tx + 0.18, 4.58, 1.42), Color(0.3, 0.8, 0.5))
	spots.append({"kind": "trade", "pos": R(tx, 3.4, 0.0), "label": "TRADE COUNTER"})
	# Hanging sign over the counter: a board on two rods from the ceiling
	# (the words used to float in mid-air with nothing behind them).
	var sy := minf(H - 1.0, 3.4)
	st.box(R(tx - 2.2, 5.03, sy - 0.48), R(tx + 2.2, 5.09, sy + 0.48), Color(0.1, 0.17, 0.3))
	st.box(R(tx - 2.24, 5.02, sy + 0.48), R(tx + 2.24, 5.1, sy + 0.52), Color(1.0, 0.78, 0.25))
	for e: float in [-1.6, 1.6]:
		st.box(R(tx + e - 0.012, 5.05, sy + 0.52), R(tx + e + 0.012, 5.07, H), Color(0.3, 0.3, 0.32))
	var sign := Label3D.new()
	sign.text = "TRADE COUNTER\nCash & card · Trade prices"
	sign.font_size = 60
	sign.pixel_size = 0.005
	sign.shaded = false
	sign.double_sided = false
	sign.modulate = Color(1.0, 0.85, 0.3)
	sign.position = R(tx, 5.0, sy)
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


# ------------------------------------------------------- head office
## The lobby of the head-office tower: polished marble, walnut walls, a
## reception desk (the HQ panel), lift doors and a feature wall with the
## company's name – yours once you take the offices (ShopStyle.house_hq),
## the tower's own while it's to let.
const WAITING_SOFA := preload("res://assets/models/home_sofa.glb")

func _build_street(st: _Batch) -> void:
	var use := String(unit["street_use"])
	var warm := use in ["hotel", "residential", "cafe", "restaurant"]
	var work := use in ["warehouse", "garage"]
	var accent := Color(0.19, 0.31, 0.25) if warm else Color(0.17, 0.25, 0.35)
	if work:
		accent = Color(0.31, 0.32, 0.33)
	var colours: Array = {
		"bank": [Color(0.17, 0.27, 0.38), Color(0.17, 0.32, 0.27)],
		"fitness": [Color(0.31, 0.17, 0.13), Color(0.19, 0.22, 0.27)],
		"furniture": [Color(0.34, 0.24, 0.15), Color(0.23, 0.30, 0.24)],
		"cafe": [Color(0.31, 0.20, 0.15), Color(0.23, 0.34, 0.29)],
		"restaurant": [Color(0.36, 0.18, 0.14), Color(0.23, 0.21, 0.32)]
	}.get(use, [accent, accent.lightened(0.10)])
	accent = colours[_front_seed % colours.size()]
	var floor_color := Color(0.61, 0.53, 0.44) if warm else Color(0.63, 0.66, 0.66)
	var floor_style := int({"cafe": 3, "restaurant": 3, "furniture": 3, "fitness": 2,
		"garage": 2, "warehouse": 2, "hotel": 4, "residential": 4}.get(use, 1))
	_floor(floor_color, floor_style)
	look = {"ceiling": Color(0.68, 0.67, 0.64), "lights": "none"}
	_shell(st, Color(0.78, 0.77, 0.72), accent)
	var mid := (door.x + door.y) * 0.5
	var height := _front_opening_height()
	var trim := Color(0.10, 0.12, 0.12) if not warm else Color(0.15, 0.20, 0.17)
	var glazing_y := 0.47 if warm else 0.27
	var glass_tint := Color(0.68, 0.78, 0.81, 0.17)
	var head := height - 0.09
	for span: Vector2 in [Vector2(ox.x, door.x), Vector2(door.y, ox.y)]:
		if span.y - span.x < 0.1:
			continue
		_wall_box(st, span.x, span.y, 0.10, 0.25, 0.0, glazing_y, accent)
		_glazed_bays(st, span, Vector2(glazing_y, head), 0.18, 0.047, 1.75, trim, glass_tint)
		_solid(R(span.x, 0.14, glazing_y), R(span.y, 0.23, head))
	st.box(R(ox.x, 0.07, head), R(ox.y, 0.28, height), trim)
	st.box(R(door.x, -0.04, 0.015), R(door.y, 1.4, 0.032), trim.lightened(0.09))
	var jamb := Color(0.49, 0.44, 0.37) if warm else trim.lightened(0.16)
	for side: float in [ox.x, ox.y]:
		var dir := -1.0 if side == ox.x else 1.0
		var outer := side + dir * 0.26
		st.box(R(minf(side, outer), -0.095, 0.0), R(maxf(side, outer), 0.066, height), jamb)
		var bead := side + dir * 0.035
		st.box(R(bead - 0.018, -0.107, 0.08), R(bead + 0.018, -0.095, height - 0.025), jamb.lightened(0.17))
	var fascia_y := height + 0.30
	var face := "condensed"
	var ink := Color(0.97, 0.93, 0.81)
	var left := ox.x - 0.2
	var right := ox.y + 0.2
	if use in ["bank", "hotel", "residential", "furniture"]:
		face = "serif"
		var inset := minf(W * 0.12, 0.95)
		left += inset
		right -= inset
		ink = Color(0.94, 0.84, 0.66)
	elif use in ["cafe", "restaurant"]:
		face = "retro" if _front_seed % 2 == 0 else "script"
	elif work or use == "fitness":
		face = "display"
	var face_col := accent.darkened(0.22)
	st.box(R(left, -0.20, height + 0.03), R(right, 0.03, fascia_y + 0.24), face_col)
	if not work and _front_seed % 3 != 1:
		for y: float in [fascia_y - 0.20, fascia_y + 0.20]:
			st.box(R(left + 0.12, -0.230, y), R(right - 0.12, -0.196, y + 0.018), ink.lerp(accent, 0.5))
	var name := String(unit["name"])
	_street_label(name if face in ["retro", "script"] else name.to_upper(),
		R(mid, -0.235, fascia_y), right - left - 0.42, ink, face, 0.0065)
	_street_label(String(Premises.STREET_TITLES[use]).to_upper(), R(mid, D - 0.07, H * 0.68),
		minf(W - 1.5, 6.8), Color(0.20, 0.23, 0.20))
	_entrance_approach(st, floor_color)
	if work:
		for side: float in [0.6, W - 1.0]:
			for row in range(1, maxi(2, int(D / 2.1))):
				var d := row * 1.8
				_wall_box(st, side - 0.28, side + 0.28, d, d + 1.32, 0.0, 1.65, Color(0.28, 0.31, 0.34))
				for y: float in [0.45, 1.03, 1.52]:
					st.box(R(side - 0.31, d - 0.02, y), R(side + 0.31, d + 1.34, y + 0.07), Color(0.48, 0.39, 0.26))
	elif use in ["cafe", "restaurant"]:
		var d := ENTRY_CLEAR + 0.48
		while d < D - 3.45:
			_cafe_table(st, R(1.5, d, 0), accent)
			if W > 8.0 and use != "cafe":
				_cafe_table(st, R(W - 1.5, d + 0.3, 0), accent)
			d += 2.25 if use == "cafe" else 2.55
		if use == "cafe":
			_window_bar(st, accent)
	elif use == "fitness":
		for i in range(1, int(D / 2.0)):
			var d := i * 1.8
			_wall_box(st, 0.65, 2.2, d, d + 0.59, 0.0, 0.49, Color(0.13, 0.15, 0.17))
			st.box(R(0.73, d - 0.06, 0.26), R(2.28, d + 0.65, 0.33), Color(0.48, 0.49, 0.49))
		# Wall-mounted dumbbell rack & mirror along the right side of the club.
		var r_d0 := ENTRY_CLEAR + 0.4
		var r_d1 := minf(D - 2.8, r_d0 + 3.2)
		if r_d1 > r_d0 + 1.0 and W >= 7.5:
			st.box(R(W - 0.10, r_d0, 0.9), R(W - 0.05, r_d1, 2.35), Color(0.74, 0.80, 0.85))
			_wall_box(st, W - 0.52, W - 0.08, r_d0 + 0.15, r_d1 - 0.15, 0.0, 0.78, Color(0.14, 0.15, 0.17))
			var db_d := r_d0 + 0.35
			while db_d < r_d1 - 0.3:
				st.cylinder(R(W - 0.30, db_d, 0.78), 0.075, 0.14, Color(0.24, 0.25, 0.28), 8)
				db_d += 0.38
	elif use == "furniture":
		for z in range(5, int(D) - 3, 5):
			_street_furniture(st, 3.2, float(z), 0.0)
			if W > 13.0:
				_street_furniture(st, W - 3.2, float(z), 0.0)
	elif use == "convenience":
		for shelf in mini(3, int((D - 2.5) / BAY)):
			var d := 0.95 + float(shelf + 1) * BAY
			_fixture(st, "shelf", shelf, {"back": R(0.09, d, 0.0), "along": Vector3.BACK,
				"out": Vector3.RIGHT, "wall": "left"})

	else:
		_street_lobby_furnishings(st, use, accent)
	var desk := D - 2.1
	var half := minf(W * 0.29, 2.25)
	_wall_box(st, mid - half, mid + half, desk, desk + 0.72, 0.0, 1.03, accent)
	st.box(R(mid - half - 0.04, desk - 0.05, 1.02), R(mid + half + 0.04, desk + 0.77, 1.1), floor_color.lightened(0.21))
	if use == "cafe" or use == "restaurant":
		_street_service_counter(st, mid, half, desk, accent, use == "cafe")
	if public_display and use != "furniture":
		spots.append({"kind": "retail_checkout", "pos": R(mid, desk - 0.64, 0.0)})
	elif use in Premises.STREET_INTERACTIVE:
		var spot_d := {"kind": "street_reception", "pos": R(mid, desk - 0.64, 0.0), "use": use}
		if use == "fitness":
			spot_d["label"] = "TRAIN · FITNESS CLUB"
		spots.append(spot_d)
	till_staff.append(R(mid, desk + 1.05, 0.0))
	door_in = R(mid, 0.92, 0.0)
	door_out = R(mid, -1.5, 0.0)
	for d: float in [D * 0.3, D * 0.73]:
		_glow_quad(R(0.9, d - 0.12, H - 0.02), R(W - 0.9, d + 0.12, H - 0.02), Color(1.0, 0.92, 0.77), true)
	var tint := Color(1.0, 0.88, 0.72) if warm else Color(0.92, 0.96, 1.0)
	for d: float in [D * 0.32, D * 0.70]:
		_light(R(mid, d, H - 0.64), tint, 1.02, clampf(maxf(D * 0.58, W * 0.69), 5.4, 12.0))


func _street_lobby_furnishings(st: _Batch, use: String, accent: Color) -> void:
	var seating_depth := ENTRY_CLEAR + 1.34
	if D < seating_depth + 2.0:
		return
	var walnut := Color(0.38, 0.27, 0.19)
	if use == "residential":
		# Parcel and mail lockers sit against the wall, facing into the lobby.
		_wall_box(st, 0.045, 0.44, seating_depth - 1.05, seating_depth + 0.95, 0.0, 1.69, walnut.darkened(0.2))
		for row in 4:
			for col in 5:
				var d := seating_depth - 0.96 + col * 0.37
				var y := 0.24 + row * 0.33
				st.box(R(0.437, d, y), R(0.462, d + 0.345, y + 0.30), walnut.lightened(0.05 * float((row + col) % 3)))
				st.box(R(0.463, d + 0.09, y + 0.207), R(0.478, d + 0.23, y + 0.225), Color(0.65, 0.58, 0.47))
	else:
		var sofa := WAITING_SOFA.instantiate() as Node3D
		sofa.position = R(0.92, seating_depth, 0.0)
		sofa.rotation.y = PI * 0.5
		_static.add_child(sofa)
		_solid(R(0.41, seating_depth - 1.15, 0), R(1.41, seating_depth + 1.15, 0.88))
		if use == "hotel" and W >= 7.5:
			# Make a check-in lounge with a bordered rug and a cocktail table.
			for inset: float in [0.0, 0.09]:
				st.box(R(0.21 + inset, seating_depth - 1.43 + inset, 0.012 + inset * 0.03),
					R(3.05 - inset, seating_depth + 1.43 - inset, 0.018 + inset * 0.03),
					Color(0.30, 0.22, 0.16) if inset == 0.0 else accent.darkened(0.18))
			st.cylinder(R(2.17, seating_depth, 0.0), 0.29, 0.38, walnut, 14)
			st.cylinder(R(2.17, seating_depth, 0.38), 0.44, 0.051, Color(0.56, 0.54, 0.48), 18)
			_solid(R(1.74, seating_depth - 0.43, 0.0), R(2.60, seating_depth + 0.43, 0.44))
			st.box(R(2.00, seating_depth - 0.15, 0.433), R(2.31, seating_depth + 0.11, 0.451), accent.lightened(0.25))
	if use in ["hotel", "office", "bank"] and W >= 7.6:
		var d := minf(D - 3.0, seating_depth + 0.44)
		var board := Color(0.19, 0.23, 0.22)
		_wall_box(st, W - 0.14, W - 0.03, d - 0.71, d + 0.71, 1.11, 2.12, board)
		var title := String({"hotel": "GUEST SERVICES", "office": "DIRECTORY", "bank": "CLIENT SERVICES"}[use])
		var placard := _street_label(title, R(W - 0.149, d, 1.90), 1.21, Color(0.89, 0.85, 0.73), "condensed", 0.0025)
		placard.rotation.y = -PI * 0.5
		for row in 3:
			var y := 1.30 + row * 0.15
			st.box(R(W - 0.158, d - 0.48, y), R(W - 0.145, d + 0.10 + 0.10 * row, y + 0.022), Color(0.63, 0.61, 0.54))
	var plant := preload("res://assets/models/home_plant.glb").instantiate() as Node3D
	plant.position = R(W - 0.68, seating_depth - 0.75, 0.0)
	_static.add_child(plant)
	_solid(plant.position - Vector3(0.29, 0.0, 0.29), plant.position + Vector3(0.29, 1.11, 0.29))


func _street_service_counter(st: _Batch, mid: float, half: float, depth: float, accent: Color, coffee: bool) -> void:
	var x := mid - half + 0.63
	var steel := Color(0.29, 0.31, 0.32)
	st.box(R(x - 0.38, depth + 0.10, 1.1), R(x + 0.38, depth + 0.63, 1.53), steel)
	if coffee:
		st.box(R(x - 0.38, depth + 0.06, 1.1), R(x + 0.38, depth + 0.14, 1.24), accent)
		for side: float in [-0.18, 0.18]:
			st.cylinder(R(x + side, depth + 0.14, 1.24), 0.073, 0.12, Color(0.94, 0.92, 0.86), 10)
	else:
		for tray in 3:
			var tx := x - 0.28 + tray * 0.28
			st.box(R(tx - 0.1, depth + 0.06, 1.49), R(tx + 0.1, depth + 0.52, 1.54), Color(0.68, 0.62, 0.52))
	var shelf_d := D - 0.12
	st.box(R(mid - half, shelf_d - 0.32, 1.52), R(mid + half, shelf_d, 1.58), accent)
	for k in 5:
		var sx := mid - half * 0.72 + (float(k) * half * 0.36)
		var colour: Color = [Color(0.88, 0.86, 0.79), Color(0.42, 0.29, 0.18)][(_front_seed + k) % 2]
		st.cylinder(R(sx, shelf_d - 0.17, 1.58), 0.092, 0.17 + 0.04 * float(k % 3), colour, 9)


func _street_furniture(st: _Batch, x: float, d: float, h: float) -> void:
	var sofa := WAITING_SOFA.instantiate() as Node3D
	sofa.position = R(x, d, h)
	_static.add_child(sofa)
	_solid(R(x - 1.15, d - 0.46, h), R(x + 1.15, d + 0.49, h + 0.88))
	var walnut := Color(0.42, 0.29, 0.19)
	_wall_box(st, x - 0.68, x + 0.68, d - 1.5, d - 0.88, h + 0.36, h + 0.45, walnut)
	for leg: float in [-0.55, 0.55]:
		st.box(R(x + leg - 0.04, d - 1.44, h), R(x + leg + 0.04, d - 0.92, h + 0.38), walnut.darkened(0.2))


func _fit_sign(label: Label3D, width: float, max_pixel: float) -> void:
	var metrics := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.font_size)
	label.pixel_size = minf(max_pixel, width / maxf(metrics.x, 1.0))
	label.width = width / label.pixel_size


func _street_label(text: String, at: Vector3, width: float, ink: Color, font_key := "condensed", max_pixel := 0.008) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = ShopStyle.font(font_key)
	label.font_size = 64
	label.outline_size = 0
	_fit_sign(label, width, max_pixel)
	label.modulate = ink
	label.position = at
	label.visibility_range_end = 75.0
	_static.add_child(label)
	return label


func _populate_public_room() -> void:
	if till_staff.is_empty() or unit.get("street_use", "") == "residential":
		return
	var seed := String(unit["id"]).hash()
	var attendant := ShopPerson.new(seed, true)
	attendant.position = till_staff[0]
	attendant.rotation.y = 0.0
	_static.add_child(attendant)
	attendant.set_process(false)
	if not public_display or walk.is_empty():
		return
	var visitor := ShopPerson.new(seed + 51)
	visitor.position = door_in
	var destination := R(W * 0.33, D * 0.48, 0.0)
	var route := path(door_in, destination)
	if not route.is_empty():
		visitor.set_path(route)
	_static.add_child(visitor)
	_public_visitor = visitor
	_public_wait = 2.0
	set_process(true)


func _build_lobby(st: _Batch) -> void:
	var is_office := kind == "office"
	var ours := (not office.is_empty()) if is_office else ShopStyle.hq_tier > 0
	var hi := ShopStyle.house_ident(ShopStyle.house) if ours and not ShopStyle.house.is_empty() else {}
	var prim: Color = hi.get("primary", Color(0.1, 0.13, 0.17))
	var acc: Color = hi.get("accent", Color(0.85, 0.72, 0.45))
	var title := String(hi.get("name", "")) if not hi.is_empty() else ""
	if is_office:
		# The company's own name, in its trade's colour.
		title = String(office.get("name", "")) if ours else String(unit.get("name", "OFFICES"))
		if ours:
			acc = Color(String(Offices.type_def(String(office.get("type", ""))).get("colour", "#d9b46e")))
	if title == "":
		title = "HEAD OFFICE" if ours else "MERIDIAN TOWER"
	var walnut := Color(0.24, 0.15, 0.1)
	var stone := Color(0.9, 0.88, 0.84)
	_floor(Color(0.86, 0.84, 0.8), 1)
	look = {"ceiling": Color(0.12, 0.12, 0.13), "lights": "none"}
	_shell(st, Color(0.8, 0.78, 0.74), Color(0.12, 0.12, 0.13))
	var tier := 0 if is_office else (ShopStyle.hq_tier if ours else 0)
	var bronze := Color(0.74, 0.59, 0.32) if tier >= 2 else Color(0.55, 0.42, 0.25)
	# Walnut panelling on the back wall, slim bronze reveals.
	var px := 0.0
	while px < W - 0.01:
		var pw := minf(1.2, W - px)
		st.box(R(px + 0.01, D - 0.08, 0.0), R(px + pw - 0.01, D - 0.02, H), walnut.lightened(0.04 * float(int(px) % 3)))
		st.box(R(px + pw - 0.012, D - 0.085, 0.0), R(px + pw + 0.012, D - 0.06, H), bronze)
		px += pw
	# The feature wall: the name in the company's face over a lit plinth.
	var cx := W * 0.5
	var panel_hw := 3.2 if tier < 2 else (3.7 if tier == 2 else minf(W * 0.44, 4.4))
	st.box(R(cx - panel_hw, D - 0.14, 2.2), R(cx + panel_hw, D - 0.08, 3.9 if tier < 3 else minf(H - 0.35, 4.35)), prim if ours else Color(0.08, 0.08, 0.09))
	_glow_quad(R(cx - panel_hw, D - 0.145, 2.18), R(cx + panel_hw, D - 0.145, 2.22), acc * (1.9 if tier >= 2 else 1.6))
	if tier >= 2:
		# Tier 2+: top brass header & twin vertical architectural light coves framing the brand wall.
		var top_y := 3.9 if tier == 2 else minf(H - 0.35, 4.35)
		st.box(R(cx - panel_hw - 0.04, D - 0.155, top_y), R(cx + panel_hw + 0.04, D - 0.08, top_y + 0.06), bronze)
		for side: float in [-1.0, 1.0]:
			var fx := cx + side * (panel_hw + 0.16)
			st.box(R(fx - 0.06, D - 0.16, 0.12), R(fx + 0.06, D - 0.08, H - 0.15), bronze)
			_glow_quad(R(fx - 0.02, D - 0.165, 0.25), R(fx + 0.02, D - 0.165, H - 0.25), acc * 1.5)
	if tier >= 3:
		# Tier 3 (The Whole Tower): architectural backlit golden crown bars and marble floor runner.
		st.box(R(cx - 2.4, D - 0.16, 3.65), R(cx + 2.4, D - 0.14, 3.71), bronze)
		_glow_quad(R(cx - 2.4, D - 0.165, 3.72), R(cx + 2.4, D - 0.165, 3.75), Color(1.0, 0.88, 0.55) * 1.8)
		st.box(R(cx - 1.15, 0.5, 0.015), R(cx + 1.15, D * 0.54, 0.021), prim.darkened(0.25))
		for side2: float in [-1.15, 1.11]:
			st.box(R(cx + side2, 0.5, 0.016), R(cx + side2 + 0.04, D * 0.54, 0.023), bronze)
	var name_l := Label3D.new()
	name_l.text = title if String(hi.get("face", "")) in ["script", "retro"] else title.to_upper()
	name_l.font = ShopStyle.font(String(hi.get("face", ""))) if not hi.is_empty() else EmpireStyle.font("black")
	name_l.font_size = 120
	name_l.pixel_size = clampf(5.6 / maxf(name_l.text.length() * 70.0, 1.0), 0.002, 0.0065)
	name_l.shaded = false
	name_l.outline_size = 0
	name_l.modulate = acc if ours else Color(0.85, 0.72, 0.45)
	name_l.position = R(cx, D - 0.16, 3.05)
	_static.add_child(name_l)
	var sub := Label3D.new()
	sub.text = ["HEAD OFFICE", "HEAD OFFICE · CORPORATE FLOORS", "HEAD OFFICE · THE WHOLE TOWER"][clampi(ShopStyle.hq_tier - 1, 0, 2)] if ours \
		else "OFFICE SUITES TO LET · ENQUIRE AT RECEPTION"
	if is_office:
		sub.text = ("%s · %d DESKS" % [String(Offices.type_def(String(office.get("type", ""))).get("name", "")).to_upper(), int(office.get("desks", 0))]) \
			if ours else "OFFICE FLOORS TO LET · ENQUIRE AT RECEPTION"
	sub.font_size = 40
	sub.pixel_size = 0.0045
	sub.shaded = false
	sub.outline_size = 0
	sub.modulate = Color(0.92, 0.9, 0.86)
	sub.position = R(cx, D - 0.16, 2.45)
	_static.add_child(sub)
	# Reception desk: a stone-topped block with a brand-coloured front (widens and gains bronze inlays at higher HQ tiers).
	var dd := D * 0.55
	var desk_hw := 2.2 if tier < 2 else (2.6 if tier == 2 else 3.0)
	st.box(R(cx - desk_hw, dd, 0.0), R(cx + desk_hw, dd + 0.8, 1.05), walnut)
	st.box(R(cx - desk_hw - 0.05, dd - 0.05, 1.05), R(cx + desk_hw + 0.05, dd + 0.85, 1.12), stone)
	st.box(R(cx - desk_hw, dd - 0.02, 0.1), R(cx + desk_hw, dd, 0.98), prim if ours else Color(0.16, 0.17, 0.19))
	_glow_quad(R(cx - desk_hw + 0.05, dd - 0.025, 0.05), R(cx + desk_hw - 0.05, dd - 0.025, 0.08), acc * (1.7 if tier >= 2 else 1.4))
	if tier >= 2:
		st.box(R(cx - desk_hw, dd - 0.032, 0.92), R(cx + desk_hw, dd - 0.015, 0.96), bronze)
		st.box(R(cx - desk_hw, dd - 0.032, 0.12), R(cx + desk_hw, dd - 0.015, 0.16), bronze)
		var desk_sig := Label3D.new()
		desk_sig.text = title.to_upper()
		desk_sig.font = name_l.font
		desk_sig.font_size = 56
		desk_sig.pixel_size = clampf((desk_hw * 1.6) / maxf(desk_sig.text.length() * 34.0, 1.0), 0.0016, 0.0036)
		desk_sig.shaded = false
		desk_sig.outline_size = 0
		desk_sig.modulate = bronze if tier >= 3 else acc
		desk_sig.position = R(cx, dd - 0.036, 0.54)
		_static.add_child(desk_sig)
	for mx: float in [-1.2, 1.2]:
		st.box(R(cx + mx - 0.25, dd + 0.25, 1.12), R(cx + mx + 0.25, dd + 0.3, 1.45), Color(0.05, 0.05, 0.06))
		_glow_quad(R(cx + mx - 0.23, dd + 0.245, 1.15), R(cx + mx + 0.23, dd + 0.245, 1.43), Color(0.35, 0.55, 0.85))
	_solid(R(cx - desk_hw - 0.05, dd - 0.05, 0.0), R(cx + desk_hw + 0.05, dd + 0.85, 1.12))
	spots.append({"kind": "office_desk" if is_office else "hq_desk", "pos": R(cx, dd - 0.9, 0.0), "label": "RECEPTION"})
	# Lifts on the side wall: brushed steel doors, lit call panels.
	for i in 3:
		var lz := D * 0.25 + i * 2.1
		if lz + 1.0 > D - 0.4:
			break
		st.box(R(W - 0.1, lz - 0.62, 0.0), R(W - 0.04, lz + 0.62, 2.5), Color(0.7, 0.71, 0.72))
		st.box(R(W - 0.105, lz - 0.01, 0.0), R(W - 0.03, lz + 0.01, 2.5), Color(0.3, 0.3, 0.31))
		st.box(R(W - 0.12, lz - 0.7, 2.5), R(W - 0.03, lz + 0.7, 2.62), Color(0.55, 0.42, 0.25))
		_glow_quad(R(W - 0.125, lz - 0.15, 2.66), R(W - 0.125, lz + 0.15, 2.76), Color(1.0, 0.75, 0.35) * 1.5)
		st.box(R(W - 0.1, lz + 0.8, 1.1), R(W - 0.05, lz + 0.92, 1.35), Color(0.6, 0.6, 0.62))
		_glow_quad(R(W - 0.105, lz + 0.83, 1.17), R(W - 0.105, lz + 0.89, 1.23), Color(0.6, 0.9, 1.0) * 1.6)
	# Waiting area by the window: two sofas round a low table, tall plants.
	var sx := 2.2
	for side: float in [-1.0, 1.0]:
		var sd := 3.2 + side * 1.1
		st.box(R(sx - 1.0, sd - 0.4, 0.0), R(sx + 1.0, sd + 0.4, 0.42), Color(0.2, 0.22, 0.25))
		st.box(R(sx - 1.0, sd + side * 0.25 - 0.15, 0.42), R(sx + 1.0, sd + side * 0.25 + 0.15, 0.85), Color(0.2, 0.22, 0.25))
		_solid(R(sx - 1.0, sd - 0.4, 0.0), R(sx + 1.0, sd + 0.4, 0.85))
	st.box(R(sx - 0.6, 2.85, 0.0), R(sx + 0.6, 3.55, 0.38), stone.darkened(0.5))
	st.box(R(sx - 0.65, 2.8, 0.38), R(sx + 0.65, 3.6, 0.42), Color(0.08, 0.08, 0.09))
	for pp in [R(0.7, D - 0.8, 0.0), R(W - 0.9, 0.9, 0.0), R(0.7, 0.9, 0.0)]:
		st.box(pp + Vector3(-0.28, 0, -0.28), pp + Vector3(0.28, 0.6, 0.28), Color(0.15, 0.15, 0.16))
		_batch_cone(st, pp + Vector3.UP * 0.6, 0.45, 0.05, 1.5, Color(0.17, 0.36, 0.18))
		_batch_cone(st, pp + Vector3.UP * 1.1, 0.35, 0.02, 1.2, Color(0.22, 0.45, 0.2))
	# Glazed entrance: steel mullions either side of an open doorway.
	var oh := _front_opening_height()
	var mid := (ox.x + ox.y) * 0.5
	var frame := Color(0.08, 0.08, 0.09)
	var tint := Color(0.68, 0.77, 0.81, 0.17)
	door = Vector2(mid - 1.3, mid + 1.3)
	for span: Vector2 in [Vector2(ox.x, door.x), Vector2(door.y, ox.y)]:
		_glazed_bays(st, span, Vector2(0.08, oh - 0.12), 0.12, 0.035, 1.65, frame, tint)
		_solid(R(span.x, 0.08, 0.0), R(span.y, 0.16, oh))
	st.box(R(ox.x, 0.08, oh - 0.12), R(ox.y, 0.16, oh), frame)
	# Canopy over the door with the name along its edge.
	st.box(R(mid - 2.6, -2.2, oh + 0.2), R(mid + 2.6, -0.02, oh + 0.42), Color(0.1, 0.1, 0.11))
	_glow_quad(R(mid - 2.5, -2.1, oh + 0.195), R(mid + 2.5, -0.1, oh + 0.195), Color(1.0, 0.9, 0.75) * 0.9, true)
	st.box(R(mid - 2.6, -2.22, oh + 0.2), R(mid + 2.6, -2.2, oh + 0.42), prim if ours else Color(0.1, 0.1, 0.11))
	var can := Label3D.new()
	can.text = name_l.text
	can.font = name_l.font
	can.font_size = 64
	can.pixel_size = clampf(4.4 / maxf(can.text.length() * 38.0, 1.0), 0.0015, 0.005)
	can.shaded = false
	can.outline_size = 0
	can.modulate = acc if ours else Color(0.9, 0.8, 0.6)
	can.position = R(mid, -2.235, oh + 0.31)
	_static.add_child(can)
	# Light: warm downlights and a cool wash on the feature wall (upgraded at HQ tiers 2-3).
	_light(R(W * 0.5, D * 0.5, H - 0.4), Color(1.0, 0.92, 0.8), 1.3 + 0.18 * float(tier), maxf(W, D) * 0.9)
	_light(R(W * 0.5, D - 1.2, H - 0.6), Color(1.0, 0.95, 0.88), 0.8 + 0.15 * float(tier), 5.5)
	if tier >= 3:
		# Architectural suspended brass halo chandelier over the grand lobby.
		var ch_y := H - 0.58
		var ch_d := D * 0.36
		for rod: Vector2 in [Vector2(-1.1, -0.5), Vector2(1.1, -0.5), Vector2(-1.1, 0.5), Vector2(1.1, 0.5)]:
			st.box(R(cx + rod.x - 0.012, ch_d + rod.y - 0.012, ch_y), R(cx + rod.x + 0.012, ch_d + rod.y + 0.012, H), bronze)
		st.box(R(cx - 1.35, ch_d - 0.62, ch_y - 0.05), R(cx + 1.35, ch_d - 0.50, ch_y + 0.05), bronze)
		st.box(R(cx - 1.35, ch_d + 0.50, ch_y - 0.05), R(cx + 1.35, ch_d + 0.62, ch_y + 0.05), bronze)
		st.box(R(cx - 1.35, ch_d - 0.62, ch_y - 0.05), R(cx - 1.23, ch_d + 0.62, ch_y + 0.05), bronze)
		st.box(R(cx + 1.23, ch_d - 0.62, ch_y - 0.05), R(cx + 1.35, ch_d + 0.62, ch_y + 0.05), bronze)
		_glow_quad(R(cx - 1.25, ch_d - 0.52, ch_y - 0.055), R(cx + 1.25, ch_d + 0.52, ch_y - 0.055), Color(1.0, 0.92, 0.72) * 1.7, true)
	var lx := 1.5
	while lx < W - 1.0:
		_glow_quad(R(lx - 0.02, 1.0, H - 0.02), R(lx + 0.02, D - 1.0, H - 0.02), Color(1.0, 0.94, 0.85) * 1.4, true)
		lx += 2.4
	door_in = R(mid, 1.2, 0.0)
	door_out = R(mid, -2.0, 0.0)
	rack_pos = R(mid + 3.5, -3.2, 0.0)


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
		mm.use_custom_data = true
		mm.mesh = shape_mesh(shape)
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_custom_data(i, items[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = goods_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 60.0
		_goods.add_child(mmi)
	# Cases: the stock room's (shop) or the collection pallet's (warehouse).
	var src: Stock = biz.backroom if biz else pallet
	if src and slot_box.has(-1):
		var sb: Array = slot_box[-1]
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_custom_data = true
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
			mm2.set_instance_custom_data(i, EmpireData.colour(list[i]).lerp(Color(0.72, 0.56, 0.36), 0.55))
		var mi2 := MultiMeshInstance3D.new()
		mi2.multimesh = mm2
		mi2.material_override = goods_material()
		_goods.add_child(mi2)
	# Cases put down on the shop floor, stacked by the door.
	if biz and biz.floor_pile and not biz.floor_pile.is_empty():
		var pl: Array = []
		for pid in biz.floor_pile.units:
			for c in Stock.cases_for(pid, biz.floor_pile.qty(pid)):
				pl.append(pid)
		var mm3 := MultiMesh.new()
		mm3.transform_format = MultiMesh.TRANSFORM_3D
		mm3.use_custom_data = true
		mm3.mesh = shape_mesh("case")
		mm3.instance_count = mini(pl.size(), 24)
		for i in mm3.instance_count:
			var col := i % 2
			var row := (i / 2) % 2
			var lvl := i / 4
			var p3 := pile_pos + Vector3(-0.27 + col * 0.54, 0.2 + lvl * 0.4, -0.2 - row * 0.4)
			mm3.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.04 * float((i * 7) % 5 - 2)), p3))
			mm3.set_instance_custom_data(i, EmpireData.colour(pl[i]).lerp(Color(0.72, 0.56, 0.36), 0.55))
		var mi3 := MultiMeshInstance3D.new()
		mi3.multimesh = mm3
		mi3.material_override = goods_material()
		_goods.add_child(mi3)
	# Price tags.
	for lab in _labels.get_children():
		var si: int = lab.get_meta("slot")
		if biz == null or si >= biz.slots.size():
			lab.text = ""
			continue
		var s: Dictionary = biz.slots[si]
		if s["product"] == "":
			lab.text = "—"
			lab.modulate = Color(0.45, 0.45, 0.48)
		else:
			var p := EmpireData.product(s["product"])
			var nm := String(p.get("name", ""))
			if nm.length() > 18:
				nm = nm.substr(0, 17) + "…"
			var out_of := int(s["qty"]) <= 0
			lab.text = "%s\n%s" % [EmpireData.money(biz.price(s["product"]), true), "SOLD OUT" if out_of else nm]
			lab.modulate = Color(0.75, 0.1, 0.1) if out_of else Color(0.08, 0.08, 0.1)
	_update_headers()
	if _dirt and biz:
		(_dirt.material_override as ShaderMaterial).set_shader_parameter("dirt", 1.0 - biz.cleanliness)


## What a shelf bay's header says: the aisle name for most of what's on it.
const AISLES := {"crisps": "SNACKS", "pretzels": "SNACKS", "choc_bar": "SWEETS", "gummies": "SWEETS", "mints": "SWEETS",
	"pick_mix": "SWEETS", "bread": "BAKERY", "sourdough": "BAKERY", "eggs": "GROCERY", "pasta": "GROCERY",
	"beans": "GROCERY", "tea": "GROCERY", "loo_roll": "HOUSEHOLD", "washup": "HOUSEHOLD", "batteries": "HOUSEHOLD",
	"cola": "DRINKS", "water": "DRINKS", "energy": "DRINKS", "juice": "DRINKS", "milk": "DAIRY",
	"trainers": "FOOTWEAR", "boots": "FOOTWEAR", "charger": "ACCESSORIES", "earbuds": "AUDIO",
	"phone_case": "ACCESSORIES"}


func _update_headers() -> void:
	if biz == null:
		return
	for h0 in _headers:
		if not is_instance_valid(h0):
			continue
		var hl := h0 as Label3D
		var fk: Array = hl.get_meta("fixture")
		var count := {}
		for sl: Dictionary in biz.slots:
			if sl["fixture"] == fk[0] and int(sl["unit"]) == int(fk[1]) and String(sl["product"]) != "":
				var a := String(AISLES.get(String(sl["product"]), ""))
				if a != "":
					count[a] = int(count.get(a, 0)) + 1
		var best := ""
		var bn := 0
		for a2 in count:
			if int(count[a2]) > bn:
				bn = int(count[a2])
				best = a2
		hl.text = best if best != "" else ({"clothing": "NEW IN", "phones": "TECH", "bakery": "BAKERY"}.get(type_id, "OFFERS") as String)


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


static var _goods_mat: ShaderMaterial


## The material for goods MultiMeshes (product colour in INSTANCE_CUSTOM).
static func goods_material() -> ShaderMaterial:
	if _goods_mat == null:
		_goods_mat = ShaderMaterial.new()
		_goods_mat.shader = load("res://src/empire/world/goods.gdshader")
	return _goods_mat


## Pack meshes, front (+z) to the aisle. Vertex alpha = how much of the
## product colour a part takes (goods.gdshader): bodies 1, white labels and
## silver rims 0, pastel print panels between. Recognisable at a glance and
## a few dozen triangles each (hundreds share one draw call per shape).
const _T := 1.0          # tinted body
const _FIX := 0.0        # fixed colour


static func _c(r: float, g: float, b: float, a: float) -> Color:
	return Color(r, g, b, a)


static func shape_mesh(shape: String) -> Mesh:
	if _shape_meshes.has(shape):
		return _shape_meshes[shape]
	var sz := shape_size(shape)
	var b := _Batch.new()
	var h := sz * 0.5
	var body := _c(1, 1, 1, _T)
	var label := _c(0.96, 0.96, 0.94, _FIX)
	var pastel := _c(1, 1, 1, 0.3)
	var silver := _c(0.78, 0.79, 0.8, _FIX)
	match shape:
		"can":
			b.cylinder(Vector3(0, -h.y + 0.008, 0), h.x, sz.y - 0.016, body, 8)
			b.cylinder(Vector3(0, -h.y + sz.y * 0.42, 0), h.x * 1.01, sz.y * 0.2, _c(0.72, 0.72, 0.72, _T), 8)
			b.cylinder(Vector3(0, -h.y, 0), h.x * 0.92, 0.008, silver, 8)
			b.cylinder(Vector3(0, h.y - 0.008, 0), h.x * 0.92, 0.008, silver, 8)
		"bottle":
			var r := h.x
			b.cylinder(Vector3(0, -h.y, 0), r, sz.y * 0.56, body, 8)
			b.cylinder(Vector3(0, -h.y + sz.y * 0.2, 0), r * 1.015, sz.y * 0.24, pastel, 8)   # label
			b.cylinder(Vector3(0, -h.y + sz.y * 0.56, 0), r * 0.85, sz.y * 0.08, body, 8)    # shoulder
			b.cylinder(Vector3(0, -h.y + sz.y * 0.64, 0), r * 0.58, sz.y * 0.08, body, 8)
			b.cylinder(Vector3(0, -h.y + sz.y * 0.72, 0), r * 0.36, sz.y * 0.18, body, 8)     # neck
			b.cylinder(Vector3(0, -h.y + sz.y * 0.9, 0), r * 0.42, sz.y * 0.1, _c(0.55, 0.55, 0.55, _T), 8)  # cap
		"cup":
			b.cylinder(Vector3(0, -h.y, 0), h.x * 0.78, sz.y * 0.35, label, 8)
			b.cylinder(Vector3(0, -h.y + sz.y * 0.35, 0), h.x * 0.9, sz.y * 0.4, body, 8)     # sleeve
			b.cylinder(Vector3(0, -h.y + sz.y * 0.75, 0), h.x * 0.95, sz.y * 0.17, label, 8)
			b.cylinder(Vector3(0, h.y - sz.y * 0.08, 0), h.x, sz.y * 0.08, _c(0.92, 0.92, 0.9, _FIX), 8)  # lid
		"bag":
			# A pillow pack: crimped top and bottom, full in the middle, a
			# white window on the front.
			var cr := 0.02
			var mid := Vector3(h.x, 0.0, h.z)
			b.hull([Vector3(-h.x, -h.y + cr, -0.008), Vector3(h.x, -h.y + cr, -0.008), Vector3(mid.x, 0, -mid.z), Vector3(-mid.x, 0, -mid.z),
				Vector3(-h.x, -h.y + cr, 0.008), Vector3(h.x, -h.y + cr, 0.008), Vector3(mid.x, 0, mid.z), Vector3(-mid.x, 0, mid.z)], body)
			b.hull([Vector3(-mid.x, 0, -mid.z), Vector3(mid.x, 0, -mid.z), Vector3(h.x, h.y - cr, -0.008), Vector3(-h.x, h.y - cr, -0.008),
				Vector3(-mid.x, 0, mid.z), Vector3(mid.x, 0, mid.z), Vector3(h.x, h.y - cr, 0.008), Vector3(-h.x, h.y - cr, 0.008)], body)
			b.box(Vector3(-h.x, -h.y, -0.006), Vector3(h.x, -h.y + cr, 0.006), _c(0.85, 0.85, 0.85, _T))
			b.box(Vector3(-h.x, h.y - cr, -0.006), Vector3(h.x, h.y, 0.006), _c(0.85, 0.85, 0.85, _T))
			b.box(Vector3(-h.x * 0.62, -h.y * 0.32, h.z * 0.7), Vector3(h.x * 0.62, h.y * 0.3, h.z + 0.004), label)
			b.box(Vector3(-h.x * 0.5, -h.y * 0.12, h.z + 0.004), Vector3(h.x * 0.5, h.y * 0.12, h.z + 0.007), _c(0.75, 0.75, 0.75, _T))
		"bar":
			b.box(Vector3(-h.x + 0.012, -h.y, -h.z), Vector3(h.x - 0.012, h.y, h.z), body)
			for e: float in [-1.0, 1.0]:
				b.box(Vector3(e * (h.x - 0.012), -h.y * 0.25, -h.z), Vector3(e * h.x, h.y * 0.25, h.z), _c(0.8, 0.8, 0.8, _T))
			b.box(Vector3(-h.x * 0.45, h.y, -h.z * 0.7), Vector3(h.x * 0.45, h.y + 0.002, h.z * 0.7), label)
			b.box(Vector3(-h.x * 0.3, h.y + 0.002, -h.z * 0.3), Vector3(h.x * 0.3, h.y + 0.003, h.z * 0.3), _c(0.6, 0.6, 0.6, _T))
		"carton":
			var ry := h.y - sz.y * 0.16
			b.box(Vector3(-h.x, -h.y, -h.z), Vector3(h.x, ry, h.z), body)
			# Gable top and its seal fin.
			b.hull([Vector3(-h.x, ry, -h.z), Vector3(h.x, ry, -h.z), Vector3(h.x, h.y - 0.012, -0.004), Vector3(-h.x, h.y - 0.012, -0.004),
				Vector3(-h.x, ry, h.z), Vector3(h.x, ry, h.z), Vector3(h.x, h.y - 0.012, 0.004), Vector3(-h.x, h.y - 0.012, 0.004)], _c(0.95, 0.95, 0.95, 0.6))
			b.box(Vector3(-h.x, h.y - 0.014, -0.003), Vector3(h.x, h.y, 0.003), _c(0.95, 0.95, 0.95, 0.6))
			b.box(Vector3(-h.x * 0.8, -h.y * 0.5, h.z), Vector3(h.x * 0.8, h.y * 0.3, h.z + 0.003), pastel)
			b.cylinder(Vector3(h.x * 0.4, ry + 0.01, h.z * 0.4), 0.012, 0.012, _c(0.95, 0.95, 0.95, _FIX), 6)
		"loaf":
			# A sliced loaf in its bag: domed top, a printed band, the twist.
			var ly := -h.y + sz.y * 0.55
			b.box(Vector3(-h.x, -h.y, -h.z), Vector3(h.x, ly, h.z), body)
			b.hull([Vector3(-h.x, ly, -h.z), Vector3(h.x, ly, -h.z), Vector3(h.x * 0.55, h.y, -h.z), Vector3(-h.x * 0.55, h.y, -h.z),
				Vector3(-h.x, ly, h.z), Vector3(h.x, ly, h.z), Vector3(h.x * 0.55, h.y, h.z), Vector3(-h.x * 0.55, h.y, h.z)], _c(1, 1, 1, _T))
			b.box(Vector3(-h.x - 0.003, -h.y * 0.7, -h.z * 0.25), Vector3(h.x + 0.003, ly + 0.01, h.z * 0.25), label)
			b.box(Vector3(-0.012, -0.012, -h.z - 0.04), Vector3(0.012, 0.012, -h.z), _c(0.9, 0.9, 0.88, _FIX))
		"pack":
			# Toilet rolls: four in a printed wrap.
			var rr := minf(h.x * 0.5, h.z) - 0.004
			for ix in 2:
				for iy in 2:
					b.cylinder(Vector3((ix - 0.5) * h.x, -h.y + iy * h.y, 0), rr, h.y - 0.004, body, 8)
			b.box(Vector3(-h.x, -h.y * 0.25, h.z - 0.01), Vector3(h.x, h.y * 0.25, h.z + 0.002), _c(0.25, 0.45, 0.8, _FIX))
			b.box(Vector3(-h.x * 0.6, -h.y * 0.12, h.z + 0.002), Vector3(h.x * 0.6, h.y * 0.12, h.z + 0.004), label)
		"case":
			b.box(-h, h, body)
			b.box(Vector3(-h.x - 0.002, h.y - 0.05, -0.04), Vector3(h.x + 0.002, h.y + 0.002, 0.04), _c(0.78, 0.66, 0.42, _FIX))
			b.box(Vector3(-h.x * 0.45, -h.y * 0.35, h.z), Vector3(h.x * 0.45, h.y * 0.35, h.z + 0.003), _c(0.93, 0.9, 0.82, _FIX))
			b.box(Vector3(-h.x * 0.35, -h.y * 0.15, h.z + 0.003), Vector3(h.x * 0.35, h.y * 0.15, h.z + 0.005), _c(0.4, 0.4, 0.4, _FIX))
		"garment":
			# On a hanger: shoulders and body, sleeves, a hook.
			b.box(Vector3(-h.x * 0.62, -h.y, -h.z), Vector3(h.x * 0.62, h.y - 0.04, h.z), body)
			b.box(Vector3(-h.x, h.y - 0.3, -h.z * 0.8), Vector3(h.x, h.y - 0.04, h.z * 0.8), _c(0.94, 0.94, 0.94, _T))
			b.box(Vector3(-0.1, h.y - 0.05, -0.005), Vector3(0.1, h.y - 0.03, 0.005), _c(0.3, 0.22, 0.15, _FIX))
			b.box(Vector3(-0.005, h.y - 0.03, -0.005), Vector3(0.005, h.y + 0.04, 0.005), silver)
			b.box(Vector3(-0.03, h.y - 0.2, h.z), Vector3(0.03, h.y - 0.12, h.z + 0.004), label)   # swing tag
		"folded":
			b.box(-h, h, body)
			b.box(Vector3(-h.x, -h.y * 0.2, -h.z - 0.002), Vector3(h.x, h.y * 0.2, -h.z + 0.01), _c(0.88, 0.88, 0.88, _T))
			b.box(Vector3(-h.x * 0.15, h.y, h.z * 0.3), Vector3(h.x * 0.15, h.y + 0.002, h.z * 0.7), label)
		"shoebox":
			b.box(-h, h, body)
			b.box(Vector3(-h.x - 0.003, h.y - 0.035, -h.z - 0.003), Vector3(h.x + 0.003, h.y + 0.003, h.z + 0.003), _c(0.25, 0.25, 0.27, _FIX))
			b.box(Vector3(-h.x * 0.6, -h.y * 0.5, h.z), Vector3(h.x * 0.2, h.y * 0.2, h.z + 0.003), label)
		"pastry", "cake":
			b.cylinder(Vector3(0, -h.y, 0), h.x, sz.y, body, 8)
			b.cylinder(Vector3(0, h.y - 0.012, 0), h.x * 0.92, 0.014, _c(0.96, 0.92, 0.85, _T), 8)
		"foodbox":
			b.box(-h, h, _c(0.97, 0.96, 0.94, _FIX))
			b.box(Vector3(-h.x - 0.002, -h.y * 0.4, -h.z - 0.002), Vector3(h.x + 0.002, h.y * 0.3, h.z + 0.002), body)
		"phone":
			b.box(-h, h, body)
			b.box(Vector3(-h.x * 0.88, h.y, -h.z * 0.9), Vector3(h.x * 0.88, h.y + 0.002, h.z * 0.9), _c(0.05, 0.06, 0.08, _FIX))
		_:
			# A printed carton: body, a white panel with the brand mark, a
			# darker top flap.
			b.box(-h, h, body)
			b.box(Vector3(-h.x * 0.8, -h.y * 0.3, h.z), Vector3(h.x * 0.8, h.y * 0.45, h.z + 0.003), label)
			b.box(Vector3(-h.x * 0.55, -h.y * 0.05, h.z + 0.003), Vector3(h.x * 0.55, h.y * 0.25, h.z + 0.005), _c(0.85, 0.85, 0.85, _T))
			b.box(Vector3(-h.x - 0.001, h.y - h.y * 0.12, -h.z - 0.001), Vector3(h.x + 0.001, h.y + 0.001, h.z + 0.001), _c(0.7, 0.7, 0.7, _T))
	var m := b.commit()
	_shape_meshes[shape] = m
	return m


# ------------------------------------------------------------ dressing
var _glass: _Batch


## A transparent box (display counters, hot cabinets): one mesh per room.
func _glass_box(lo: Vector3, hi: Vector3) -> void:
	if _glass == null:
		_glass = _Batch.new()
	_glass.box(lo, hi, Color(0.75, 0.85, 0.9, 0.1))


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
				var dd := ENTRY_CLEAR + 0.12
				var x := lerpf(gx0, gx1, [0.32, 0.50, 0.65][_front_seed % 3])
				while dd + 1.2 < part_d - 1.2:
					_cafe_table(st, R(x, dd + 0.6, 0.0), accent)
					dd += 1.9
			_window_bar(st, accent)
		"stools":
			_window_bar(st, accent)
			if free_mid:
				var dd2 := ENTRY_CLEAR + 0.12
				while dd2 + 1.2 < part_d - 1.2:
					_cafe_table(st, R((gx0 + gx1) * 0.5, dd2 + 0.6, 0.0), Color(0.85, 0.85, 0.86))
					dd2 += 1.9
		"boutique":
			# Mannequins in the window, a mirror, a rug.
			var offset := ENTRY_SIDE + 0.36
			if door.y + offset < W - 0.6:
				_mannequin(R(door.y + offset, 0.75, 0.0), -PI * 0.12)
			if door.x - offset > 0.6:
				_mannequin(R(door.x - offset, 0.75, 0.0), PI * 0.16)
			st.box(R(0.06, part_d - 2.6, 0.2), R(0.08, part_d - 1.6, 2.3), Color(0.75, 0.82, 0.86))
			st.box(R(0.055, part_d - 2.65, 0.15), R(0.075, part_d - 1.55, 2.35), Color(0.75, 0.62, 0.35))
			if not unit.get("flagship", false) and part_d > ENTRY_CLEAR + 1.8:
				var rug_d := ENTRY_CLEAR + 0.45
				st.box(R(gx0, rug_d, 0.0), R(gx1, minf(rug_d + 2.3, part_d - 1.1), 0.016),
					brand.lerp(Color(0.9, 0.86, 0.8), 0.5))
		"plinths":
			# White plinths with a hero device on each, a big brand screen.
			var px := door.y + ENTRY_SIDE + 0.34
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
	# Sized to stay on the 1.2 m board (long wording used to run off both
	# ends and show through, mirrored, from behind).
	lab.pixel_size = minf(0.0036, 1.05 / (float(lab.text.length()) * 52.0 * 0.6))
	lab.outline_size = 0
	lab.shaded = false
	lab.double_sided = false
	lab.modulate = accent
	lab.position = R(cx0 - 0.115, hd, 2.975)
	lab.rotation.y = -PI * 0.5
	_static.add_child(lab)
	var back := lab.duplicate() as Label3D
	back.text = "THANK YOU"
	back.pixel_size = minf(0.0036, 1.05 / (9.0 * 52.0 * 0.6))
	back.position = R(cx0 - 0.025, hd, 2.975)
	back.rotation.y = PI * 0.5
	_static.add_child(back)


## A menu board over the back counter: what the shop sells and its prices,
## laid out line by line in two columns so everything stays on the board.
## Made-here things lead; bottled drinks go last.
func _menu_board(st: _Batch, part_d: float) -> void:
	var x0 := 0.5
	var x1 := minf(W - 2.8, x0 + 4.2)
	if x1 - x0 < 1.5:
		return
	var neon := type_id == "takeaway"
	var y0 := 2.2
	var y1 := 3.45
	var bd := part_d - 0.06
	st.box(R(x0, bd, y0), R(x1, part_d - 0.02, y1), Color(0.08, 0.08, 0.09) if not neon else brand.darkened(0.55))
	# A thin frame in the brand's accent.
	var fr: Color = ident.get("accent", Color(0.8, 0.7, 0.45))
	st.box(R(x0 - 0.03, bd + 0.005, y1), R(x1 + 0.03, part_d - 0.02, y1 + 0.03), fr)
	st.box(R(x0 - 0.03, bd + 0.005, y0 - 0.03), R(x1 + 0.03, part_d - 0.02, y0), fr)
	var top := y1 - 0.12
	if neon:
		# Backlit picture panels of the food along the top.
		var n := 3
		for i in n:
			var a := lerpf(x0 + 0.1, x1 - 0.1, float(i) / n)
			var b := lerpf(x0 + 0.1, x1 - 0.1, float(i + 1) / n) - 0.08
			_glow_quad(R(a, bd - 0.005, y1 - 0.45), R(b, bd - 0.005, y1 - 0.08), [Color(1.0, 0.75, 0.3), Color(0.95, 0.45, 0.25), Color(1.0, 0.9, 0.6)][i] * 1.2)
		top = y1 - 0.6
	# What's on: the shop's own lines (or, before it has any, what its kind sells).
	var pids: Array = []
	if biz:
		for sl: Dictionary in biz.slots:
			var pid := String(sl["product"])
			if pid != "" and not pids.has(pid):
				pids.append(pid)
		if pids.is_empty():
			pids = biz.sellable()
	var drinks := func(p: String) -> bool: return String(EmpireData.product(p).get("fixture", "")) == "fridge"
	var ordered: Array = pids.filter(func(p): return not drinks.call(p)) + pids.filter(func(p): return drinks.call(p))
	var line_h := 0.22
	var rows := maxi(int(floor((top - (y0 + 0.08)) / line_h)) + 1, 1)
	var cols := 2 if x1 - x0 >= 3.0 else 1
	ordered = ordered.slice(0, rows * cols)
	var font := ShopStyle.font("condensed")
	var fs := 48
	var px := 0.0034
	var pad := 0.14
	var cw := (x1 - x0 - pad * 2.0 - 0.25 * (cols - 1)) / cols
	for i in ordered.size():
		var pid: String = ordered[i]
		var col := i / rows
		var row := i % rows
		var cx0 := x0 + pad + col * (cw + 0.25)
		var y := top - row * line_h
		var price := EmpireData.money(biz.price(pid) if biz else EmpireData.rrp(pid), true)
		var pw := font.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px
		var name := String(EmpireData.product(pid)["name"])
		var room := cw - pw - 0.12
		var base := name
		while base.length() > 4 and font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px > room:
			base = base.substr(0, base.length() - 1).strip_edges()
			name = base + "…"
		var nw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px
		for part: Array in [[name, cx0 + nw * 0.5, Color(0.97, 0.95, 0.88)], [price, cx0 + cw - pw * 0.5, Color(1.0, 0.84, 0.42)]]:
			var lab := Label3D.new()
			lab.text = part[0]
			lab.font = font
			lab.font_size = fs
			lab.pixel_size = px
			lab.outline_size = 0
			lab.shaded = false
			lab.modulate = part[2]
			lab.position = R(part[1], bd - 0.012, y)
			_static.add_child(lab)


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
	var x0 := door.y + ENTRY_SIDE
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
func _mannequin(p: Vector3, angle: float) -> void:
	var display := MeshInstance3D.new()
	display.mesh = InteriorKit.mannequin()
	display.position = p
	display.rotation.y = angle
	display.visibility_range_end = 44.0
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_static.add_child(display)
	_solid(p + Vector3(-0.28, 0, -0.24), p + Vector3(0.28, 1.87, 0.24))


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


const FLOOR_DETAIL := [
	"res://assets/textures/pbr/worldstate_retail_ceramic.png",
	"res://assets/textures/pbr/worldstate_retail_ceramic.png",
	"res://assets/textures/pbr/worldstate_pavement_concrete.png",
	"res://assets/textures/pbr/worldstate_retail_oak.png",
	"res://assets/textures/pbr/worldstate_retail_terrazzo.png",
]


func _floor(c: Color, style: int) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, D)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://src/empire/world/shop_floor.gdshader")
	fm.set_shader_parameter("base_col", c)
	fm.set_shader_parameter("room_size", Vector2(W, D))
	var warm := String(unit.get("street_use", "")) in ["hotel", "residential", "restaurant", "cafe"]
	fm.set_shader_parameter("fixture_tint", Color(1.0, 0.92, 0.79) if warm else Color(0.97, 0.98, 1.0))
	fm.set_shader_parameter("style", style)
	fm.set_shader_parameter("surface_detail", load(FLOOR_DETAIL[clampi(style, 0, FLOOR_DETAIL.size() - 1)]))
	var fi := MeshInstance3D.new()
	fi.mesh = pm
	fi.material_override = fm
	fi.position = R(W * 0.5, D * 0.5, 0.012)
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fi.visibility_range_end = 260.0
	_static.add_child(fi)
	# Walkable floor collision (the building's tier was cut away).
	_solid(R(0.0, 0.0, -0.3), R(W, D, 0.0))


func _spot_light(p: Vector3, tint: Color, energy: float, radius: float, beam: float) -> void:
	var light := SpotLight3D.new()
	light.position = p
	light.rotation.x = -PI * 0.5
	light.light_color = tint
	light.light_energy = energy * 1.65
	light.light_specular = 0.31
	light.spot_range = radius
	light.spot_attenuation = 1.18
	light.spot_angle = beam + 8.0
	light.spot_angle_attenuation = 1.25
	var is_own_shop := biz != null and rival.is_empty() and not public_display
	light.distance_fade_enabled = true
	light.distance_fade_begin = 42.0 if is_own_shop else 32.0
	light.distance_fade_length = 12.0
	light.set_meta("open_energy", light.light_energy)
	_static.add_child(light)
	_sales_lights.append(light)


func _light(p: Vector3, c: Color, e: float, r: float) -> void:
	var o := OmniLight3D.new()
	o.position = p
	o.light_color = c
	InteriorKit.tune_light(o, e * 1.8, r)
	# Tighten distance fade on non-player-occupied shops so distant interiors
	# don't waste active mobile lights.
	var is_own_shop := biz != null and rival.is_empty() and not public_display
	o.distance_fade_begin = 42.0 if is_own_shop else 32.0
	o.distance_fade_length = 12.0 if is_own_shop else 8.0
	_static.add_child(o)
	o.set_meta("open_energy", o.light_energy)
	_sales_lights.append(o)


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
	if k == "glass":
		var glazing := ShaderMaterial.new()
		glazing.shader = preload("res://src/empire/world/storefront_glass.gdshader")
		_mat_cache[k] = glazing
		return glazing
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match k:
		"vc":
			m.roughness = 0.7
		"goods":
			m.roughness = 0.45
			m.vertex_color_use_as_albedo = true
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
	var nx := int(ceil(W / CELL))
	var nz := int(ceil((D + 4.0) / CELL))
	for ix in nx:
		for iz in nz:
			var cell := Vector2i(ix, iz)
			var p := cell_pos(cell)
			if p.x < 0.3 or p.x > W - 0.3 or -p.z > D - 0.3:
				continue
			if -p.z < 0.35 and (p.x < door.x + 0.2 or p.x > door.y - 0.2):
				continue
			walk[cell] = true
	for cs: CollisionShape3D in _col.get_children():
		var bs := cs.shape as BoxShape3D
		if bs == null:
			continue
		if bs.size.y < 0.4 and cs.position.y < 0.0:
			continue  # floor
		var b := AABB(cs.position - bs.size * 0.5, bs.size).grow(0.28)
		if b.position.y > 0.5 or b.end.y <= 0.5:
			continue
		var lo := cell_of(Vector3(b.position.x, 0.0, b.end.z))
		var hi := cell_of(Vector3(b.end.x, 0.0, b.position.z))
		for x in range(maxi(0, lo.x), mini(nx - 1, hi.x) + 1):
			for z in range(maxi(0, lo.y), mini(nz - 1, hi.y) + 1):
				var cell := Vector2i(x, z)
				if b.has_point(cell_pos(cell) + Vector3.UP * 0.5):
					walk.erase(cell)


## Grid cell → room position (row 0 is 4 m outside the door).
func cell_pos(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, 4.0 - (c.y + 0.5) * CELL)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor((4.0 - p.z) / CELL)))


## A* over the walk grid (room coords in and out). Empty = no path.
func path(from: Vector3, to: Vector3, avoid := Vector3.INF) -> PackedVector3Array:
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
				if avoid != Vector3.INF:
					# Prefer the open side of an aisle or door when somebody is there.
					var next := cell_pos(nb)
					var separation := Vector2(avoid.x - next.x, avoid.z - next.z).length()
					ng += 6.0 * (1.0 - smoothstep(0.34, 0.83, separation))
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
	if public_display or kind == "street":
		for s: Dictionary in spots:
			if s["kind"] in ["retail_checkout", "street_reception"]:
				var d: Dictionary = {"kind": s["kind"], "world": to_world(s["pos"]), "interior": self}
				if s.has("label"):
					d["label"] = s["label"]
				if s.has("use"):
					d["use"] = s["use"]
				out.append(d)
		return out
	if not rival.is_empty() or (kind == "shop" and biz == null):
		return out  # (a shop to let has its TO LET board outside, nothing inside)
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

	## A convex 8-corner solid, corners ordered like box(): the −z face
	## (lo,lo)(hi,lo)(hi,hi)(lo,hi) then the same at +z. Tapers, gables.
	func hull(v: Array, c: Color) -> void:
		var faces := [[1, 0, 3, 2], [4, 5, 6, 7], [0, 4, 7, 3], [5, 1, 2, 6], [0, 1, 5, 4], [7, 6, 2, 3]]
		var ctr := Vector3.ZERO
		for p: Vector3 in v:
			ctr += p / 8.0
		for f in faces:
			var a: Vector3 = v[f[0]]
			var b2: Vector3 = v[f[1]]
			var c2: Vector3 = v[f[2]]
			var d: Vector3 = v[f[3]]
			var nrm := (b2 - a).cross(d - a)
			if nrm.length() < 1e-9:
				nrm = (c2 - b2).cross(a - b2)
			nrm = nrm.normalized()
			if nrm.dot((a + b2 + c2 + d) * 0.25 - ctr) < 0.0:
				nrm = -nrm
			_quad(a, b2, c2, d, nrm, c)

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
