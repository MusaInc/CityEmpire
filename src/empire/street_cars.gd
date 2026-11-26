class_name StreetCars
extends Node
## Stealing cars and keeping them in garages (2026-11-26: "i want to steal
## cars, allow character to drive any car and also add garages").
##
## Stealing: on foot, walk up to any car that's stopped or crawling – city,
## Westbank and Skyport traffic, a parked car, a settled wreck – and STEAL
## CAR. Wrecks.take lifts it out of the street; it becomes an ordinary
## vehicle record flagged "stolen" (model by body: the street_* models for
## the traffic fleet, the showroom model for a bought-car body), spawned and
## entered with the normal door animation, so everything your own cars do
## (driving, damage, cargo, audio, camera) works on it. Walk away from a
## stolen car and leave it (STOLEN_TOW m) and it's towed: gone.
##
## Garages: buy a lock-up at any Motor Works (phone · Garage). It holds
## LOCKUP_SLOTS cars and you can use it at every Motor Works. Stop at a Motor
## Works door in a car and STORE IN GARAGE: the car is put away (hidden,
## saved) – a stolen car you store becomes yours. Take it out from the
## phone: at a Motor Works it's brought out to the kerb free, anywhere else
## it's delivered like any of your cars.

const STEAL_REACH := 1.35        # m from the car's side
const STOLEN_TOW := 220.0        # m: a stolen car you've left this far behind is towed
const RELEASE_AWAY := 160.0      # m: a taken traffic car's slot goes back to traffic
const GARAGE_REACH := 12.0       # m from a Motor Works door to store a car
const LOCKUP_PRICE := 12000.0
const LOCKUP_EXTEND := 9000.0
const LOCKUP_SLOTS := 4
const MODEL_FOR_BODY := {
	"civ_compact": "street_compact", "civ_sedan": "street_sedan", "civ_taxi": "street_taxi",
	"civ_suv": "street_suv", "civ_van": "street_van", "civ_police": "street_police",
	"civ_ambulance": "street_ambulance", "kestrel": "hatch", "marlin": "saloon", "scout": "scout",
	"warden": "warden", "goliath": "goliath", "vanta": "vanta", "brute": "brute", "halcyon": "halcyon",
	"stiletto": "stiletto", "courier_van": "van", "civ_box": "box",
}

var game: EmpireGame
var _releases: Array = []        # [[Traffic, id, Vector3 where]]
var _t := 0.0


func setup(g: EmpireGame) -> void:
	game = g


static func model_for(body: String) -> String:
	return String(MODEL_FOR_BODY.get(body, "street_sedan"))


# ------------------------------------------------------------ stealing
## The nearest car you could steal from where you stand ({} if none).
func spot_near(p: Vector3) -> Dictionary:
	if game.wrecks == null:
		return {}
	var c := game.wrecks.stealable(p, STEAL_REACH)
	if c.is_empty():
		return {}
	var body := String(CityWorld.CAR_KINDS[int(c["k"])][2]) if int(c["k"]) >= 0 else "civ_sedan"
	if c["src"] == "wreck":
		body = String(((c["wreck"] as Dictionary)["car"] as Car).spec.get("body", "civ_sedan"))
	c["kind"] = "steal_car"
	c["model"] = model_for(body)
	return c


func prompt(s: Dictionary) -> Array:
	var name := String(EmpireData.vehicle_model(String(s.get("model", ""))).get("name", "car"))
	return ["STEAL %s" % name.to_upper(), true]


func steal(s: Dictionary) -> void:
	var got := game.wrecks.take(s)
	var body: String = got[0]
	var xf: Transform3D = got[1]
	var col: Color = got[2]
	if not (got[5] as Array).is_empty():
		_releases.append([got[5][0], got[5][1], xf.origin])
	var model := model_for(body)
	var v := game.empire.add_vehicle(model, xf.origin, xf.basis.get_euler().y)
	v["stolen"] = true
	v["paint"] = col.to_html(false)
	if not (got[3] as Dictionary).is_empty():
		v["damage"] = got[3]
		v["dent_state"] = got[4]
	var c := game._spawn_car(v)
	if c == null:
		game.empire.vehicles.erase(v)
		return
	# Exactly where it stood (no kerb search: you're standing at its door).
	c.place(Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * 0.05))
	c.park_lock = false
	game.ui.toast("Stolen: %s. Keep it by storing it in a garage." % String(EmpireData.vehicle_model(model).get("name", "car")), "warn")
	Settings.haptic(30, 0.4)
	# Let it settle on its wheels (a car still dropping onto them counts as
	# moving and the door won't open), then get in.
	var vid := String(v["id"])
	await get_tree().create_timer(0.35, false).timeout
	if not is_instance_valid(c) or game.cars.get(vid) != c:
		return
	c.linear_velocity = Vector3.ZERO
	c.angular_velocity = Vector3.ZERO
	game.enter_vehicle(vid, true)
	if game.driving == "" and not game.vehicle_access.active():
		game.enter_vehicle(vid, false)   # (no clear door to walk round to: straight in)



func _physics_process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or game == null or game.empire == null or game.player == null:
		return
	_t = 1.0
	var me := game.player.global_position
	var dn := game.vehicle_node()
	if dn:
		me = dn.global_position
	# Taken traffic cars' slots go back to traffic once you're well away.
	for i in range(_releases.size() - 1, -1, -1):
		var r: Array = _releases[i]
		if not is_instance_valid(r[0]):
			_releases.remove_at(i)
		elif (r[2] as Vector3).distance_to(me) > RELEASE_AWAY:
			(r[0] as Traffic).release(int(r[1]))
			_releases.remove_at(i)
	# Stolen cars you've left behind are towed.
	for v in game.empire.vehicles.duplicate():
		if not v.get("stolen", false) or v.get("stored", "") != "" or String(v["id"]) == game.driving:
			continue
		var c: Car = game.cars.get(String(v["id"]))
		var at: Vector3 = c.global_position if c and is_instance_valid(c) else game.vehicle_position(String(v["id"]))
		if at.distance_to(me) > STOLEN_TOW:
			if c and is_instance_valid(c):
				c.queue_free()
			game.cars.erase(String(v["id"]))
			game.empire.vehicles.erase(v)
			game.ui.toast("The stolen %s you left has been towed" % String(EmpireData.vehicle_model(String(v["model"])).get("name", "car")), "info")


# ------------------------------------------------------------ garages
func lockup_slots() -> int:
	return int(game.empire.flags.get("lockup_slots", 0))


func stored() -> Array:
	return game.empire.vehicles.filter(func(x): return String(x.get("stored", "")) != "")


func room() -> int:
	return lockup_slots() - stored().size()


func buy_lockup() -> String:
	var first := lockup_slots() == 0
	var price := LOCKUP_PRICE if first else LOCKUP_EXTEND
	if not game.empire.pay(price, "property", "Lock-up garage" if first else "Lock-up extension"):
		return "Not enough money"
	game.empire.flags["lockup_slots"] = lockup_slots() + LOCKUP_SLOTS
	game.empire.changed.emit()
	return ""


## Stopped in a car at a Motor Works door with room in your lock-up: the
## Motor Works unit, else {}.
func store_spot() -> Dictionary:
	if game.driving == "" or room() <= 0:
		return {}
	var c: Car = game.cars.get(game.driving)
	if c == null or Vector2(c.linear_velocity.x, c.linear_velocity.z).length() > 1.15:
		return {}
	var ng := game.nearest_garage(c.global_position)
	if (ng[0] as Dictionary).is_empty() or float(ng[1]) > GARAGE_REACH:
		return {}
	return ng[0]


func store_current(unit: Dictionary) -> void:
	var vid := game.driving
	var c: Car = game.cars.get(vid)
	var v := game.empire.vehicle(vid)
	if c == null or v.is_empty():
		return
	game.exit_vehicle(false)
	if game.driving != "":
		return   # (couldn't get out)
	var was_stolen: bool = v.get("stolen", false)
	v.erase("stolen")
	v["stored"] = String(unit.get("name", "Motor Works"))
	var door := Premises.door_point(unit)
	v["pos"] = [door.x, door.y, door.z]
	game._store_damage(v, c)
	_hide(c)
	game.ui.toast(("It's yours now: %s is in your lock-up" if was_stolen else "%s put away in your lock-up") %
		String(EmpireData.vehicle_model(String(v["model"])).get("name", "car")), "good")
	Sfx.play("chime", -6.0)
	game.save_game()


func _hide(c: Car) -> void:
	if not c.has_meta("lockup_layers"):
		c.set_meta("lockup_layers", [c.collision_layer, c.collision_mask])
	c.visible = false
	c.freeze = true
	c.collision_layer = 0
	c.collision_mask = 0
	c.process_mode = Node.PROCESS_MODE_DISABLED


## After the cars are spawned (load): stored ones stay in the lock-up.
func apply_stored() -> void:
	for v in stored():
		var c: Car = game.cars.get(String(v["id"]))
		if c and is_instance_valid(c):
			_hide(c)


## Out of the lock-up: at a Motor Works (within 40 m) to its kerb, free;
## elsewhere delivered to you like any car. "" or why not.
func take_out(vid: String) -> String:
	var v := game.empire.vehicle(vid)
	var c: Car = game.cars.get(vid)
	if v.is_empty() or c == null:
		return "Not found"
	if game.driving != "":
		return "Get out of the car first"
	var me := game.player.global_position
	var ng := game.nearest_garage(me)
	var at_garage := not (ng[0] as Dictionary).is_empty() and float(ng[1]) < 40.0
	var from := Premises.door_point(ng[0]) if at_garage else me
	var spot_r: Dictionary = game.safe.road_spot(from + Vector3.DOWN * 0.9, c.spec["size"],
		{"exclude": [c.get_rid(), game.player.get_rid()], "min_d": 3.5})
	if not spot_r["ok"]:
		return "No clear road here – walk to a street"
	if not at_garage:
		var fee := 120.0
		if not game.empire.pay(fee, "vehicle", "Car brought from your lock-up"):
			return "Costs %s – not enough money" % EmpireData.money(fee)
	var xf: Transform3D = spot_r["xf"]
	c.process_mode = Node.PROCESS_MODE_INHERIT
	c.visible = true
	var lm: Array = c.get_meta("lockup_layers", [c.collision_layer, c.collision_mask])
	c.collision_layer = int(lm[0])
	c.collision_mask = int(lm[1])
	c.remove_meta("lockup_layers")
	c.freeze = false
	c.linear_velocity = Vector3.ZERO
	c.angular_velocity = Vector3.ZERO
	c.place(Transform3D(xf.basis, xf.origin + xf.basis.y * 0.35))
	v.erase("stored")
	v["pos"] = [xf.origin.x, xf.origin.y, xf.origin.z]
	v["yaw"] = xf.basis.get_euler().y
	game.save_game()
	return ""
