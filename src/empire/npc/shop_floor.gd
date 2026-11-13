class_name ShopFloor
extends Node
## The shop the player is in, run with walking people. Shoppers the economy
## sends (Business.pending_arrivals) come in from the street, walk to the
## shelves for what they want, decide there (Empire.live_take – the same
## DemandModel as everywhere else), queue, and wait at a till to be served:
## by a cashier on shift, or by the player standing behind the counter and
## pressing SERVE (scan, pay, bag). Wait too long and they put the goods
## back and leave unhappy. Staff are shown at work: cashiers at the tills, a
## stacker carrying cases from the stock room, a cleaner, a manager.
##
## People live in the interior's room frame (ShopInterior coordinates).

signal served(amount: float, items: int, at: Vector3)
signal walked_out(at: Vector3)
signal goods_changed

const MAX_INSIDE := 10

var empire: Empire
var biz: Business
var room: ShopInterior
## Seconds of real time per game minute (the clock speed).
var minutes_per_second := 1.0

var customers: Array = []   # [{p (ShopPerson), shopper, state, wants, basket, wait, till, slot, t, mood}]
var staff_people := {}      # employee id -> {p, role, t, state, till, target}
var scanning := {}          # till -> {c, t, total, items}
var player_till := -1       # the till the player is standing at (-1 none)
var _rng := RandomNumberGenerator.new()
var _goods_dirty := false
var _refresh_t := 0.0


func setup(p_empire: Empire, p_biz: Business, p_room: ShopInterior) -> void:
	empire = p_empire
	biz = p_biz
	room = p_room
	_rng.seed = hash([biz.id, empire.day, int(empire.minute)])
	biz.live = true
	biz.pending_arrivals = 0
	sync_staff()


func _exit_tree() -> void:
	# Anyone still inside: the goods in their baskets go back on the shelves.
	for c in customers:
		if not (c["basket"] as Stock).is_empty():
			empire.put_back(biz, c["basket"])
		if is_instance_valid(c["p"]):
			c["p"].queue_free()
	customers.clear()
	for k in staff_people:
		if is_instance_valid(staff_people[k]["p"]):
			staff_people[k]["p"].queue_free()
	staff_people.clear()
	if biz:
		biz.live = false
		# (Shoppers who were on their way still count: the model takes them.)
		for i in mini(biz.pending_arrivals, 30):
			if biz.has_role("cashier"):
				empire.visit_offscreen(biz)
		biz.pending_arrivals = 0
		biz.player_at_till = false


func _process(dt: float) -> void:
	if empire == null or biz == null:
		return
	var game_dt := dt * minutes_per_second  # game minutes this frame
	# New arrivals from the street.
	while biz.pending_arrivals > 0:
		biz.pending_arrivals -= 1
		if customers.size() >= MAX_INSIDE:
			# A full shop: the model handles them if someone's on a till,
			# else they see the crowd and walk on.
			if biz.has_role("cashier"):
				empire.visit_offscreen(biz)
			continue
		_spawn_customer()
	for c in customers.duplicate():
		_update_customer(c, dt, game_dt)
	_update_staff(dt)
	_update_scans(dt)
	_refresh_t -= dt
	if _goods_dirty and _refresh_t <= 0.0:
		_goods_dirty = false
		_refresh_t = 0.25
		room.refresh_goods()
		goods_changed.emit()


# ------------------------------------------------------------ customers
func _spawn_customer() -> void:
	var shopper := DemandModel.make_shopper(biz, _rng)
	biz.today["customers"] = int(biz.today["customers"]) + 1
	var p := ShopPerson.new(int(shopper["seed"]))
	p.position = room.door_out + Vector3(_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(0.0, 1.5))
	p.blocked_by = _blocked.bind(p)
	room.add_child(p)
	var wants: Array = (shopper["wants"] as Array).duplicate()
	var c := {"p": p, "shopper": shopper, "state": "enter", "wants": wants, "basket": Stock.new(0, "basket"),
		"wait": 0.0, "till": -1, "slot": -1, "t": 0.0, "mood": 0.0, "impulse_done": false}
	customers.append(c)
	p.set_path(room.path(p.position, room.door_in))


func _blocked(at: Vector3, me: ShopPerson) -> bool:
	for c in customers:
		var o: ShopPerson = c["p"]
		if o != me and o.position.distance_to(at) < 0.4 and o.position.distance_to(me.position) > 0.05:
			return true
	return false


func _update_customer(c: Dictionary, dt: float, game_dt: float) -> void:
	var p: ShopPerson = c["p"]
	c["t"] = float(c["t"]) + dt
	match String(c["state"]):
		"enter":
			if p.arrived():
				_next_want(c)
		"to_shelf":
			if p.arrived():
				c["state"] = "pick"
				c["t"] = 0.0
				var sb: Array = room.slot_box.get(int(c["slot"]), [])
				if not sb.is_empty():
					p.face_goal = (sb[0] as Vector3) + (sb[1] as Vector3) * float(sb[3]) * 0.5
		"pick":
			if float(c["t"]) > 1.1:
				var pid: String = c["want"]
				var before := (c["basket"] as Stock).total_units()
				var res := empire.live_take(biz, c["shopper"], pid, c["basket"])
				match res:
					"buy":
						_goods_dirty = true
						p.carry = 0.45
					"stockout":
						p.say("?", Color(1.0, 0.8, 0.3))
					"too_expensive":
						p.say("£!", Color(1.0, 0.45, 0.35))
				if res == "buy" and (c["basket"] as Stock).total_units() == before:
					pass
				_next_want(c)
		"queue":
			c["wait"] = float(c["wait"]) + game_dt
			_queue_step(c)
			if float(c["wait"]) > float(c["shopper"]["patience"]):
				_give_up(c)
		"at_till":
			c["wait"] = float(c["wait"]) + game_dt
			var t: int = c["till"]
			if scanning.has(t) and scanning[t]["c"] == c:
				return
			if _cashier_at(t) and p.arrived():
				_start_scan(t, c, false)
			elif float(c["wait"]) > float(c["shopper"]["patience"]) * 2.2:
				_give_up(c)
		"leave":
			if p.arrived():
				customers.erase(c)
				p.queue_free()


## Next wanted product: walk to its shelf, or decide on the spot when the
## shop doesn't sell it. Then the impulse grab, then the queue.
func _next_want(c: Dictionary) -> void:
	var p: ShopPerson = c["p"]
	var wants: Array = c["wants"]
	while not wants.is_empty():
		var pid: String = wants.pop_front()
		var si := biz.slot_with(pid)
		if si < 0:
			# On display but empty, or not sold at all: the shelf tells them.
			for i in biz.slots.size():
				if biz.slots[i]["product"] == pid:
					si = i
					break
		if si < 0 or not room.slot_pick.has(si):
			empire.live_take(biz, c["shopper"], pid, c["basket"])  # (not_stocked)
			continue
		c["want"] = pid
		c["slot"] = si
		c["state"] = "to_shelf"
		p.face_goal = Vector3.INF
		p.set_path(room.path(p.position, room.slot_pick[si] + Vector3(_rng.randf_range(-0.3, 0.3), 0, 0)))
		return
	if not c["impulse_done"]:
		c["impulse_done"] = true
		var imp := DemandModel.impulse_pick(biz, c["shopper"])
		if imp != "":
			c["wants"] = [imp]
			(c["shopper"]["wants"] as Array).append(imp)
			(c["shopper"]["wtp"] as Dictionary)[imp] = EmpireData.rrp(imp) * float(c["shopper"].get("spend_k", 1.0))
			_next_want(c)
			return
	if (c["basket"] as Stock).is_empty():
		_leave(c, "")
		return
	c["state"] = "queue"
	c["wait"] = 0.0
	_queue_step(c)


func _queue_index(c: Dictionary) -> int:
	var i := 0
	for o in customers:
		if o == c:
			return i
		if o["state"] == "queue":
			i += 1
	return i


func _queue_step(c: Dictionary) -> void:
	var p: ShopPerson = c["p"]
	# A free till? (each till takes one customer at a time)
	var qi := _queue_index(c)
	if qi == 0:
		for t in room.till_customer.size():
			if not _till_taken(t):
				c["state"] = "at_till"
				c["till"] = t
				p.set_path(room.path(p.position, room.till_customer[t]))
				p.face_goal = room.till_staff[t]
				return
	var spot: Vector3 = room.queue[mini(qi, room.queue.size() - 1)]
	if p.path.is_empty() or p.path[p.path.size() - 1].distance_to(spot) > 0.2:
		p.set_path(room.path(p.position, spot))
		p.face_goal = room.till_customer[0]


func _till_taken(t: int) -> bool:
	for o in customers:
		if o["state"] == "at_till" and int(o["till"]) == t:
			return true
	return false


func _give_up(c: Dictionary) -> void:
	empire.put_back(biz, c["basket"])
	_goods_dirty = true
	biz.today["walked_out"] = int(biz.today["walked_out"]) + 1
	biz.add_rep(EmpireData.rep_param("left_unserved"))
	(c["p"] as ShopPerson).say("✕", Color(1.0, 0.35, 0.3), 2.5)
	walked_out.emit(room.to_world((c["p"] as ShopPerson).position))
	_leave(c, "")


func _leave(c: Dictionary, _why: String) -> void:
	var p: ShopPerson = c["p"]
	for t in scanning.keys():
		if scanning[t]["c"] == c:
			scanning.erase(t)
	c["state"] = "leave"
	p.face_goal = Vector3.INF
	p.carry = 0.0
	p.set_path(room.path(p.position, room.door_out + Vector3(_rng.randf_range(-2.0, 2.0), 0, 1.0)))


# ---------------------------------------------------------------- tills
func _cashier_at(t: int) -> bool:
	for k in staff_people:
		var s: Dictionary = staff_people[k]
		if s["role"] == "cashier" and int(s["till"]) == t and (s["p"] as ShopPerson).arrived():
			return true
	return false


## The player pressed SERVE at till t. Returns false if nobody's waiting there.
func player_serve(t: int) -> bool:
	if scanning.has(t):
		return false
	for c in customers:
		if c["state"] == "at_till" and int(c["till"]) == t and (c["p"] as ShopPerson).arrived():
			_start_scan(t, c, true)
			return true
	return false


## Someone standing at till t waiting to pay (for the SERVE prompt).
func waiting_at(t: int) -> bool:
	for c in customers:
		if c["state"] == "at_till" and int(c["till"]) == t and (c["p"] as ShopPerson).arrived():
			return not scanning.has(t)
	return false


func scanning_at(t: int) -> bool:
	return scanning.has(t)


func _start_scan(t: int, c: Dictionary, by_player: bool) -> void:
	var items := (c["basket"] as Stock).total_units()
	var speed := 1.0
	if not by_player:
		for k in staff_people:
			if staff_people[k]["role"] == "cashier" and int(staff_people[k]["till"]) == t:
				speed = Staff.speed(staff_people[k]["e"])
	scanning[t] = {"c": c, "t": 0.0, "dur": (0.5 + 0.38 * items) / speed, "by_player": by_player,
		"items": items, "beeps": 0}


func _update_scans(dt: float) -> void:
	for t in scanning.keys():
		var s: Dictionary = scanning[t]
		s["t"] = float(s["t"]) + dt
		var c: Dictionary = s["c"]
		var beep_every := float(s["dur"]) / maxf(float(s["items"]), 1.0)
		if int(float(s["t"]) / beep_every) > int(s["beeps"]) and int(s["beeps"]) < int(s["items"]):
			s["beeps"] = int(s["beeps"]) + 1
			Sfx.play("beep", -6.0, 1.0 + 0.04 * float(int(s["beeps"]) % 3))
		if float(s["t"]) >= float(s["dur"]):
			scanning.erase(t)
			var server := {}
			if not s["by_player"]:
				for k in staff_people:
					if staff_people[k]["role"] == "cashier" and int(staff_people[k]["till"]) == t:
						server = staff_people[k]["e"]
			var items := (c["basket"] as Stock).total_units()
			var amount := empire.checkout(biz, c["basket"], server)
			# Quick service and a fair price leave a good impression.
			var waited := float(c["wait"])
			var rep := EmpireData.rep_param("visit_ok")
			if waited > float(c["shopper"]["patience"]) * 0.7:
				rep += EmpireData.rep_param("slow_queue") * 0.5
			biz.add_rep(rep)
			var p: ShopPerson = c["p"]
			p.say("+" + EmpireData.money(amount, true), Color(0.5, 1.0, 0.6), 1.4)
			served.emit(amount, items, room.to_world(p.position))
			p.carry = 0.7
			_leave(c, "paid")


# ---------------------------------------------------------------- staff
## Makes the people on shift match the business's staff list.
func sync_staff() -> void:
	var ids := {}
	var till_n := 0
	for e in biz.staff:
		ids[e["id"]] = true
		if not staff_people.has(e["id"]):
			var p := ShopPerson.new(int(e.get("look", 7)), true)
			p.position = room.rack_pos if e["role"] != "cashier" else room.till_staff[0]
			room.add_child(p)
			p.say(String(e["name"]).get_slice(" ", 0), Color(0.75, 0.95, 0.85), 2.0)
			staff_people[e["id"]] = {"p": p, "role": e["role"], "e": e, "t": _rng.randf_range(0.0, 3.0), "state": "idle",
				"till": -1}
	for k in staff_people.keys():
		if not ids.has(k):
			staff_people[k]["p"].queue_free()
			staff_people.erase(k)
	for k in staff_people:
		var s: Dictionary = staff_people[k]
		if s["role"] == "cashier":
			s["till"] = till_n if till_n < room.till_staff.size() else -1
			till_n += 1


func _update_staff(dt: float) -> void:
	var open := biz.within_hours(empire.hour()) and biz.open
	for k in staff_people:
		var s: Dictionary = staff_people[k]
		var p: ShopPerson = s["p"]
		s["t"] = float(s["t"]) - dt
		match String(s["role"]):
			"cashier":
				var t: int = s["till"]
				var spot: Vector3 = room.till_staff[t] if t >= 0 else room.office_pos
				if p.arrived() and p.position.distance_to(spot) > 0.3:
					p.set_path(room.path(p.position, spot))
				p.face_goal = room.till_customer[t] if t >= 0 else Vector3.INF
			"stocker":
				if float(s["t"]) > 0.0 or not p.arrived():
					continue
				if s["state"] == "to_shelf":
					s["state"] = "back"
					p.set_carry(false)
					p.set_path(room.path(p.position, room.rack_pos))
					s["t"] = 1.5
				elif open and biz.backroom.total_units() > 0 and not room.slot_pick.is_empty():
					var keys := room.slot_pick.keys()
					var si: int = keys[_rng.randi() % keys.size()]
					s["state"] = "to_shelf"
					var pid: String = biz.slots[si]["product"] if si < biz.slots.size() else ""
					p.set_carry(true, EmpireData.colour(pid).lerp(Color(0.7, 0.55, 0.35), 0.5) if pid != "" else Color(0.7, 0.55, 0.35))
					p.set_path(room.path(p.position, room.slot_pick[si]))
					s["t"] = 2.5
					_goods_dirty = true
				else:
					s["t"] = 3.0
			"cleaner", "manager":
				if float(s["t"]) > 0.0 or not p.arrived():
					continue
				var cells := room.walk.keys()
				if cells.is_empty():
					continue
				var dest := room.cell_pos(cells[_rng.randi() % cells.size()])
				if -dest.z < 0.8:
					continue
				if s["role"] == "manager" and _rng.randf() < 0.5:
					dest = room.office_pos
				p.set_path(room.path(p.position, dest))
				s["t"] = _rng.randf_range(3.0, 7.0)
			"driver":
				p.visible = false  # out on the road with the van


func customer_count() -> int:
	return customers.size()


func queue_length() -> int:
	return customers.filter(func(c): return c["state"] == "queue" or c["state"] == "at_till").size()
