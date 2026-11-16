class_name Venues
extends Node
## Walk-in venues on Skyport Island: the car showrooms and the clothes shops
## are real rooms you walk into (assets/venues/<id>.glb, designed in
## tools/blender/build_venues.py). SkyportIsland carves each room's footprint
## out of its building (SkyportIsland.venues, set by register() before the
## island builds); this node streams the rooms in and out, gives them
## collision, lights, sliding doors, the showroom turntable, display cars you
## inspect (SkyportPlay.displays) and walk-up points that open the dealer /
## clothes screens.
##
## GLB contract: a static "Venue" mesh; moving nodes Door_L/Door_R (slide
## apart), Turntable (turns), RollerDoor; empties car_* (display cars),
## spot_* (walk-up points) and npc_* (staff positions).

## aisle: x (m, right of the door) of a clear walk from the entrance to
## mid-floor (the walk-through check follows it).
const DEFS := {
	"meridian": {"site": "dealer_luxury", "w": 60.0, "d": 28.0, "h": 8.5, "aisle": 0.0},
	"kestrel": {"site": "dealer_budget", "w": 40.0, "d": 20.0, "h": 6.0, "aisle": 2.2},
	"arden": {"site": "clothes_premium", "w": 24.0, "d": 16.0, "h": 5.0, "aisle": 7.0},
	"threadline": {"site": "clothes_everyday", "w": 22.0, "d": 14.0, "h": 4.6, "aisle": 2.5},
}
## The car on the turntable (Meridian's hypercar).
const STAR := {"meridian": "stiletto"}
const FLOOR_LIFT := 0.04
const LOAD_RANGE := 260.0
const FREE_RANGE := 340.0
const REACH := 1.7
const DOOR_OPEN := 4.5

var game: EmpireGame
var rooms := {}            # id -> {node, xf, marks, doors, turntable, cars, spots, ceiling}
var _t := 0.0


## Before the island builds: tell it which rooms to carve.
static func register() -> void:
	var out: Array = []
	for id in DEFS:
		if ResourceLoader.exists("res://assets/venues/%s.glb" % id):
			var d: Dictionary = DEFS[id].duplicate()
			d["id"] = id
			out.append(d)
	SkyportIsland.venues = out


func setup(g: EmpireGame) -> void:
	game = g


## World transform of a venue's front-centre floor point (the GLB's origin).
func venue_xf(id: String) -> Transform3D:
	var v: Dictionary = (game.skyport.plan_data.get("venues", {}) as Dictionary).get(id, {})
	if v.is_empty():
		return Transform3D()
	var o: Vector3 = v["origin"]
	# (4 cm up: the island's paving runs on under the room, flush with its
	# floor, and showed through it as dark slate tiles.)
	return Transform3D(Basis(Vector3.UP, SkyportIsland.wyaw(float(v["yaw"]))), SkyportIsland.w(o) + Vector3.UP * FLOOR_LIFT)


func has_venue(site_id: String) -> bool:
	for id in rooms:
		if DEFS[id]["site"] == site_id:
			return true
	return false


func _process(dt: float) -> void:
	if game == null or game.skyport == null:
		return
	var p := game.player.global_position
	if game.vehicle_node():
		p = game.vehicle_node().global_position
	_t -= dt
	if _t <= 0.0:
		_t = 0.5
		for id in (game.skyport.plan_data.get("venues", {}) as Dictionary):
			var xf := venue_xf(id)
			var d := xf.origin.distance_to(p)
			if d < LOAD_RANGE and not rooms.has(id):
				_load(id, xf)
			elif d > FREE_RANGE and rooms.has(id):
				_free(id)
	for id in rooms:
		_animate(rooms[id], dt, game.player.global_position)


## Load now if the hero is at / inside one (teleports, new games).
func load_near_now(p: Vector3) -> void:
	if game.skyport == null:
		return
	for id in (game.skyport.plan_data.get("venues", {}) as Dictionary):
		var xf := venue_xf(id)
		if xf.origin.distance_to(p) < LOAD_RANGE and not rooms.has(id):
			_load(id, xf)


# ---------------------------------------------------------------- building a room
func _load(id: String, xf: Transform3D) -> void:
	var ps: PackedScene = load("res://assets/venues/%s.glb" % id)
	if ps == null:
		return
	var root: Node3D = ps.instantiate()
	root.name = "Venue_" + id
	game.add_child(root)
	root.global_transform = xf
	var R := {"id": id, "node": root, "xf": xf, "marks": {}, "doors": [], "turntable": null, "cars": [], "spots": [],
		"ceiling": xf.origin.y + float(DEFS[id]["h"]) - 0.4, "door_t": 0.0}
	for n in root.get_children():
		var nm := String(n.name)
		if n is MeshInstance3D:
			_fix_materials(n as MeshInstance3D)
			(n as MeshInstance3D).visibility_range_end = FREE_RANGE
		if nm == "Venue" and n is MeshInstance3D:
			_collide(root, n as MeshInstance3D)
		elif nm.begins_with("Door_"):
			R["doors"].append([n, (n as Node3D).position, -1.0 if nm.ends_with("L") else 1.0])
		elif nm == "Turntable":
			R["turntable"] = n
		elif not (n is MeshInstance3D):
			R["marks"][nm] = (n as Node3D).global_transform
	_lights(root, id)
	_cars(R)
	for nm: String in R["marks"]:
		if nm.begins_with("spot_") and not nm.begins_with("spot_car_"):
			R["spots"].append([nm, (R["marks"][nm] as Transform3D).origin])
	rooms[id] = R


func _free(id: String) -> void:
	var R: Dictionary = rooms[id]
	for key in R["cars"]:
		if game.skyport_play.displays.has(key):
			game.skyport_play.displays[key].queue_free()
			game.skyport_play.displays.erase(key)
	(R["node"] as Node).queue_free()
	rooms.erase(id)


static var _glass_mat: StandardMaterial3D
static var _tint_mat: StandardMaterial3D


## glTF transmission doesn't import: glass becomes a light alpha pane.
func _fix_materials(mi: MeshInstance3D) -> void:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.albedo_color = Color(0.78, 0.86, 0.9, 0.16)
		_glass_mat.roughness = 0.04
		_glass_mat.metallic_specular = 0.8
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tint_mat = _glass_mat.duplicate()
		_tint_mat.albedo_color = Color(0.4, 0.46, 0.5, 0.3)
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m == null:
			continue
		var rn := String(m.resource_name)
		if rn.begins_with("floor_") and m is BaseMaterial3D and (m as BaseMaterial3D).roughness < 0.45:
			# (No reflection probe indoors: a mirror floor reflects the sky and
			# turns dark blue. Satin reads as polished under the room lights.)
			var fm := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			fm.roughness = 0.45
			mi.set_surface_override_material(i, fm)
		match rn:
			"glass_clear":
				mi.set_surface_override_material(i, _glass_mat)
			"glass_tint":
				mi.set_surface_override_material(i, _tint_mat)


## Walls, floor, counters and stock collide like the shops (hero + people).
func _collide(root: Node3D, mi: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = CityWorld.HUMAN_LAYER | 1
	body.collision_mask = 0
	root.add_child(body)
	var faces := PackedVector3Array()
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		var nm := String(m.resource_name) if m else ""
		# Lights flush with ceilings / floors and glass doors' panes aside, everything is solid.
		if nm.begins_with("led") or nm == "screen":
			continue
		var arr := mi.mesh.surface_get_arrays(i)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			faces.append_array(vs)
		else:
			for k in (ix as PackedInt32Array):
				faces.append(vs[k])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = mi.transform
	body.add_child(cs)


func _lights(root: Node3D, id: String) -> void:
	var d: Dictionary = DEFS[id]
	var W := float(d["w"])
	var D := float(d["d"])
	var H := float(d["h"])
	var nx := clampi(int(W / 14.0), 2, 4)
	var nz := clampi(int(D / 12.0), 1, 2)
	var warm := id == "arden" or id == "meridian"
	# Indoors the floor would take its ambient from the blue zenith sky (dark
	# slate floors): an interior probe gives the room its own ambient light
	# and reflections (rendered once, on load).
	var pr := ReflectionProbe.new()
	pr.name = "RoomProbe"
	pr.interior = true
	pr.update_mode = ReflectionProbe.UPDATE_ONCE
	pr.size = Vector3(W, H, D)
	pr.position = Vector3(0, H * 0.5, -D * 0.5)
	pr.origin_offset = Vector3(0, -H * 0.5 + 1.6, 0)
	pr.box_projection = true
	pr.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	pr.ambient_color = Color(1.0, 0.93, 0.84) if warm else Color(0.95, 0.96, 1.0)
	pr.ambient_color_energy = 0.55
	pr.max_distance = maxf(W, D) * 1.5
	pr.blend_distance = 0.5
	root.add_child(pr)
	for i in nx:
		for k in nz:
			var o := OmniLight3D.new()
			o.position = Vector3(-W * 0.5 + W * (i + 0.5) / nx, H - 0.8, -D * (k + 0.5) / nz)
			o.light_color = Color(1.0, 0.9, 0.78) if warm else Color(0.96, 0.98, 1.0)
			o.light_energy = 1.5
			o.omni_range = maxf(W / nx, D / nz) * 1.1 + 2.0
			o.omni_attenuation = 0.8
			o.shadow_enabled = false
			o.distance_fade_enabled = true
			o.distance_fade_begin = 80.0
			o.distance_fade_length = 30.0
			root.add_child(o)


## Display cars on the car_* marks (inspect = the usual vehicle card).
func _cars(R: Dictionary) -> void:
	var id := String(R["id"])
	var sid := String(DEFS[id]["site"])
	var stock: Array = SkyportPlay.STOCK.get(sid, [])
	if stock.is_empty():
		return
	var names: Array = (R["marks"] as Dictionary).keys().filter(func(n: String) -> bool:
		return n.begins_with("car_") and n != "car_handover")
	names.sort()
	var k := 0
	for nm: String in names:
		var model := String(STAR.get(id, "")) if nm == "car_turntable" and STAR.has(id) else String(stock[k % stock.size()])
		if nm != "car_turntable":
			k += 1
		var xf: Transform3D = R["marks"][nm]
		var c := Car.new()
		c.name = "Showroom_" + model
		c.setup(game._car_spec(model), "display")
		game.add_child(c)
		var vis := CarVisual.new()
		c.add_child(vis)
		vis.setup(c)
		c.visual = vis
		# (The marks' -Z faces the car's nose; cars face -Z too.)
		c.place(Transform3D(xf.basis, xf.origin + Vector3.UP * 0.35))
		c.freeze = true
		c.set_meta("site", sid)
		c.set_meta("model", model)
		var key := "%s/in/%s" % [sid, nm]
		game.skyport_play.displays[key] = c
		R["cars"].append(key)
		if nm == "car_turntable":
			R["star"] = c


# ---------------------------------------------------------------- life
func _animate(R: Dictionary, dt: float, hero: Vector3) -> void:
	var xf: Transform3D = R["xf"]
	# Doors: slide apart while anyone (the hero) is near the entrance.
	var near := false
	if not (R["doors"] as Array).is_empty():
		var dc: Vector3 = xf * Vector3(((R["doors"][0][1] as Vector3).x + (R["doors"][-1][1] as Vector3).x) * 0.5, 0.0, 0.0)
		near = Vector2(dc.x - hero.x, dc.z - hero.z).length() < DOOR_OPEN and absf(dc.y - hero.y) < 3.0
	R["door_t"] = move_toward(float(R["door_t"]), 1.0 if near else 0.0, dt * 1.6)
	var e := float(R["door_t"])
	e = e * e * (3.0 - 2.0 * e)
	for dd: Array in R["doors"]:
		var n: Node3D = dd[0]
		var base: Vector3 = dd[1]
		var leaf := absf(base.x - ((R["doors"][0][1] as Vector3).x + (R["doors"][-1][1] as Vector3).x) * 0.5) * 2.0
		n.position = base + Vector3(float(dd[2]) * leaf * 0.95 * e, 0.0, 0.0)
	var tt: Node3D = R["turntable"]
	if tt:
		tt.rotate_y(dt * 0.18)
		var star: Car = R.get("star")
		if star and is_instance_valid(star):
			var c := tt.global_position
			var off := star.global_position - c
			var rot := Basis(Vector3.UP, dt * 0.18)
			star.global_transform = Transform3D(rot * star.global_basis, c + rot * Vector3(off.x, 0.0, off.z) + Vector3(0, off.y, 0))


## Inside a room: the ceiling height (camera + indoor walking), else INF.
func ceiling_at(p: Vector3) -> float:
	for id in rooms:
		var R: Dictionary = rooms[id]
		var q: Vector3 = (R["xf"] as Transform3D).affine_inverse() * p
		var d: Dictionary = DEFS[id]
		if absf(q.x) < float(d["w"]) * 0.5 and q.z < 0.2 and q.z > -float(d["d"]) and q.y > -1.0 and q.y < float(d["h"]):
			return float(R["ceiling"])
	return INF


## Walk-up points inside (sales desks, configurator, till, fitting rooms...):
## they open the site's own screens through SkyportPlay ("sky_site").
func spot_near(p: Vector3) -> Dictionary:
	var best := {}
	var bd := REACH
	for id in rooms:
		for s: Array in rooms[id]["spots"]:
			var q: Vector3 = s[1]
			var d := Vector2(q.x - p.x, q.z - p.z).length()
			if d < bd and absf(q.y - p.y + 0.95) < 2.0:
				bd = d
				best = {"kind": "sky_site", "site": DEFS[id]["site"], "venue_spot": s[0], "world": q, "d": d}
	return best


static func spot_label(spot: String) -> String:
	if spot.begins_with("spot_sales"):
		return "TALK TO SALES"
	if spot.begins_with("spot_look"):
		return "SHOP THIS LOOK"
	return {"spot_turntable": "SEE THE STAR CAR", "spot_configurator": "CONFIGURATOR", "spot_handover": "COLLECT YOUR CAR",
		"spot_till": "PAY AT THE TILL", "spot_fitting": "FITTING ROOM", "spot_shoes": "SHOES", "spot_watches": "WATCHES & JEWELLERY"
		}.get(spot, "BROWSE") as String
