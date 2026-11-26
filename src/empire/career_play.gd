class_name CareerPlay
extends Node
## The playable side of Careers (2026-11-26): courier runs on the GPS, shift
## work at the businesses round you, and the Tycoon's driver.

const RUN_MIN := 500.0
const RUN_MAX := 1500.0
const ARRIVE := 7.0
const SHIFT_REACH := 45.0

var game: EmpireGame
var _t := 0.0


func setup(g: EmpireGame) -> void:
	game = g


func run() -> Dictionary:
	return game.empire.flags.get("courier", {}) if game and game.empire else {}


# ------------------------------------------------------------ courier runs
func start_run() -> String:
	if not run().is_empty():
		return "Finish the run you're on first"
	if not game.gps.ready_net():
		return "Finding the roads…"
	var me := game.player.global_position
	var cands: Array = []
	for u: Dictionary in game.world.street_units + (game.skyport.street_units if game.skyport else []):
		var d := Premises.door_point(u)
		var m := d.distance_to(me)
		if m > RUN_MIN and m < RUN_MAX:
			cands.append([u, d, m])
	if cands.is_empty():
		return "No deliveries going from here – try nearer the centre"
	var pick: Array = cands[game.empire.rng.randi() % cands.size()]
	var u: Dictionary = pick[0]
	var to: Vector3 = (pick[1] as Vector3) + Premises.outward(u) * 1.6
	var metres: float = pick[2]
	var r := {"to": [to.x, to.y, to.z], "to_name": String(u.get("name", "a client")), "pay": Careers.courier_pay(metres),
		"minutes": Careers.courier_time(metres), "start_day": game.empire.day, "start_min": game.empire.minute}
	game.empire.flags["courier"] = r
	game.gps.set_destination(to, "Courier: %s" % r["to_name"], {"kind": "courier"})
	return ""


func cancel_run() -> void:
	game.empire.flags.erase("courier")
	game.gps.clear("cancelled")


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or game == null or game.empire == null or game.player == null:
		return
	_t = 0.5
	var r := run()
	if r.is_empty():
		return
	var to := Vector3(float(r["to"][0]), float(r["to"][1]), float(r["to"][2]))
	var me := game.vehicle_node().global_position if game.vehicle_node() else game.player.global_position
	if Vector2(me.x, me.z).distance_to(Vector2(to.x, to.z)) < ARRIVE and absf(me.y - to.y) < 4.0:
		var taken := float(game.empire.day - int(r["start_day"])) * 1440.0 + game.empire.minute - float(r["start_min"])
		var paid := Careers.courier_done(game.empire, r, taken)
		game.empire.flags.erase("courier")
		game.gps.clear("arrived")
		var quick := taken <= float(r["minutes"])
		game.ui.toast("Delivered to %s: %s%s" % [r["to_name"], EmpireData.money(paid), " (quick-delivery bonus)" if quick else ""], "good")
		Sfx.play("chime", -4.0)
		game.save_game()


# ------------------------------------------------------------ shift work
## Businesses you could work a shift at, nearest first: [[unit, metres], …].
func employers(limit := 4) -> Array:
	var me := game.player.global_position
	var out: Array = []
	for u: Dictionary in game.world.street_units + (game.skyport.street_units if game.skyport else []):
		if game.empire.business_at(String(u.get("id", ""))) != null:
			continue
		out.append([u, Premises.door_point(u).distance_to(me)])
	out.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	return out.slice(0, limit)


func affluence(u: Dictionary) -> float:
	var d := Premises.door_point(u)
	var key := ("west:" if d.x < CityLayout.FAR_SHORE else "east:") + game.layout.district(d.x, d.z)
	return float(EmpireData.district(key).get("affluence", 1.0))


func work_shift(u: Dictionary) -> String:
	if game.driving != "":
		return "Get out of the car first"
	if Premises.door_point(u).distance_to(game.player.global_position) > SHIFT_REACH:
		return "Go there first"
	var why := Careers.shift_block(game.empire)
	if why != "":
		return why
	var pay := Careers.work_shift(game.empire, String(u.get("name", "work")), affluence(u))
	if pay < 0.0:
		return "Couldn't work a shift now"
	game.ui.toast("Four hours at %s: %s earned" % [u.get("name", "work"), EmpireData.money(pay)], "good")
	game.save_game()
	return ""


# ------------------------------------------------------------ the driver (Tycoon)
func driven_to(p: Vector3, yaw: float) -> String:
	if not Careers.has_perk(game.empire, "driver"):
		return "A driver comes with Tycoon status (£1m net worth)"
	if game.driving != "":
		return "Get out of the car first"
	game._teleport(p + Vector3.UP * 0.9, yaw)
	game.ui.toast("Your driver drops you off", "info")
	return ""
