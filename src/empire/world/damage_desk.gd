class_name DamageDesk
extends Node3D
## Property damage and the police response to it (destruction overhaul
## 2026-11-25). Everything the player's car breaks – street furniture
## (Destructibles), storefronts (StorefrontSmash) – is reported here with
## what it costs to put back and whose it is.
##
##  * Damage to your own shops is a repair bill for that business.
##  * Anyone else's (the city's furniture, other traders' windows) is a
##    property-damage charge. Once the total of an incident passes a small
##    threshold a patrol car is sent: it drives the road network from out of
##    sight to the scene with its beacons on and stops there. When it
##    arrives the charge is issued with a fine on top (bigger for repeat
##    offences in the same hour); drive off before it gets there and the
##    charge still comes, with a "left the scene" surcharge.
##  * The patrol waits a little, then drives off and is cleared out of view.
## Session only, like the damage itself (DamageDesk keeps no save state).

signal charged(total: float, memo: String)

const SEND_AT := 250.0          # £ of third-party damage before a patrol is sent
const FINE := 0.25              # fine on top of the damage, first offence
const REPEAT_FINE := 0.2        # + per earlier incident this hour
const LEFT_SCENE := 0.5         # surcharge when you'd gone before they arrived
const LEFT_DIST := 160.0
const ARRIVE_DIST := 14.0
const GIVE_UP := 75.0           # s: a patrol that can't get there issues by post

var game: EmpireGame
var _incident := {}             # {at, cost, own: {unit: cost}, items: n, t}
var _history: Array = []        # real-time ticks (ms) of past incidents
var _patrol: Car
var _driver: AIDriver
var _patrol_t := 0.0
var _patrol_state := ""         # "" | "driving" | "waiting" | "leaving"
var _rng := RandomNumberGenerator.new()


func setup(g: EmpireGame) -> void:
	game = g
	_rng.randomize()


## owner_unit: the unit id when it's one of yours (a repair bill, no police).
func report(what: String, at: Vector3, cost: float, owner_unit := "") -> void:
	if game == null or cost <= 0.0:
		return
	if owner_unit != "":
		var b: Business = game.empire.business_at(owner_unit)
		game.empire.pay(cost, "repairs", "Repairs: %s" % what, b.id if b else "")
		game.ui.toast("Your %s needs repairs: %s" % [what, EmpireData.money(cost)], "warn")
		return
	if _incident.is_empty():
		_incident = {"at": at, "cost": 0.0, "items": 0, "t": 0.0, "what": what}
	_incident["cost"] = float(_incident["cost"]) + cost
	_incident["items"] = int(_incident["items"]) + 1
	_incident["at"] = at
	if float(_incident["cost"]) >= SEND_AT and _patrol_state == "":
		_dispatch(at)


func _physics_process(dt: float) -> void:
	if game == null:
		return
	if not _incident.is_empty():
		_incident["t"] = float(_incident["t"]) + dt
		# Small stuff with no patrol coming is settled quietly after a while.
		if _patrol_state == "" and float(_incident["t"]) > 20.0:
			_issue(false)
	if _patrol_state == "":
		return
	if not is_instance_valid(_patrol):
		_patrol_state = ""
		return
	_patrol_t += dt
	var space := get_world_3d().direct_space_state
	match _patrol_state:
		"driving":
			_driver.update(dt, space)
			var scene: Vector3 = _incident.get("at", _patrol.global_position)
			var me := game.vehicle_node().global_position if game.vehicle_node() else game.player.global_position
			if _patrol.global_position.distance_to(scene) < ARRIVE_DIST or _driver.remaining() <= 2:
				_patrol.throttle = 0.0
				_patrol.brake = 1.0
				_patrol_state = "waiting"
				_patrol_t = 0.0
				_issue(me.distance_to(scene) > LEFT_DIST)
			elif _patrol_t > GIVE_UP:
				_issue(me.distance_to(scene) > LEFT_DIST)
				_leave()
		"waiting":
			_patrol.throttle = 0.0
			_patrol.brake = 1.0
			if _patrol_t > 14.0:
				_leave()
		"leaving":
			_driver.update(dt, space)
			var cam := get_viewport().get_camera_3d()
			var seen := cam != null and cam.is_position_in_frustum(_patrol.global_position) and cam.global_position.distance_to(_patrol.global_position) < 250.0
			if (_patrol_t > 8.0 and not seen) or _patrol_t > 60.0:
				_clear_patrol()


func _dispatch(at: Vector3) -> void:
	var net: RoadNet = game.gps.net if game.gps and game.gps.ready_net() else null
	if net == null:
		return
	var cam := get_viewport().get_camera_3d()
	var field := net.flow_field(at)
	for attempt in 14:
		var ang := _rng.randf() * TAU
		var q := at + Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(130.0, 210.0)
		var n := net.nearest(q, Vector3.ZERO, 40.0, -1, true)
		if n.is_empty():
			continue
		var p := net.lane_point(n["lane"], n["s"])
		if cam and cam.is_position_in_frustum(p) and cam.global_position.distance_to(p) < 260.0:
			continue
		if absf(p.y - at.y) > 12.0:
			continue
		var route := net.route(field, n["lane"], n["s"], 420.0)
		if route.size() < 8:
			continue
		var end := route[route.size() - 1]
		if Vector2(end.x - at.x, end.z - at.z).length() > 45.0:
			continue
		var dir := net.lane_dir(n["lane"], n["s"])
		var c := Car.new()
		c.setup(CarCatalog.police_spec("patrol"), "police")
		c.name = "Patrol"
		add_child(c)
		var v := CarVisual.new()
		c.add_child(v)
		v.setup(c)
		c.visual = v
		c.place(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p + Vector3.UP * 0.4), dir * 8.0)
		v.set_siren(true)
		v.set_beacon_lights(true)
		_driver = AIDriver.new(c)
		_driver.skill = 0.88
		_driver.speed_cap = 19.0
		_driver.set_path(route)
		_patrol = c
		_patrol_state = "driving"
		_patrol_t = 0.0
		game.ui.toast("Police are on their way to the damage", "warn")
		return


func _issue(left_scene: bool) -> void:
	if _incident.is_empty():
		return
	var cost := float(_incident["cost"])
	var now := Time.get_ticks_msec()
	_history = _history.filter(func(t): return now - int(t) < 3600000)
	var police := _patrol_state != "" or cost >= SEND_AT
	var fine := 0.0
	if police:
		fine = cost * (FINE + REPEAT_FINE * _history.size())
		if left_scene:
			fine += cost * LEFT_SCENE
	var total := roundf(cost + fine)
	var memo := "Property damage (%d item%s)" % [int(_incident["items"]), "" if int(_incident["items"]) == 1 else "s"]
	if police:
		memo += " + police fine" + (" (left the scene)" if left_scene else "")
	# (An empty pocket goes into the overdraft like fuel does: the bill stands.)
	if not game.empire.pay(total, "fines", memo):
		game.empire.company_cash -= total
	game.ui.toast("%s: %s" % [memo, EmpireData.money(total)], "bad" if police else "warn")
	charged.emit(total, memo)
	_history.append(now)
	_incident = {}


func _leave() -> void:
	if not is_instance_valid(_patrol):
		_patrol_state = ""
		return
	_patrol.visual.set_siren(false)
	_patrol.visual.set_beacon_lights(false)
	var net: RoadNet = game.gps.net
	var n := net.nearest(_patrol.global_position, -_patrol.global_basis.z, 30.0, -1, true)
	if not n.is_empty():
		var pts := PackedVector3Array()
		var s: float = n["s"]
		for i in 60:
			pts.append(net.lane_point(n["lane"], s + i * 4.0))
		_driver.set_path(pts)
	_patrol.brake = 0.0
	_patrol_state = "leaving"
	_patrol_t = 0.0


func _clear_patrol() -> void:
	if is_instance_valid(_patrol):
		_patrol.queue_free()
	_patrol = null
	_driver = null
	_patrol_state = ""


func active_patrol() -> Car:
	return _patrol if is_instance_valid(_patrol) else null
