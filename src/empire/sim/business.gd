class_name Business
extends RefCounted
## One business: its premises, fixtures and their product slots, back room,
## prices, upgrades, staff, reputation and day counters. Money never lives
## here: sales and costs go through Empire (company account + ledger).
##
## Slots: every fixture (shelf unit, drinks fridge, coffee machine, pick & mix
## wall) has a fixed number of product slots from the business type. A slot
## holds one product up to its unit capacity; an empty slot can be given any
## product of the same fixture kind. The 3-D shop draws the same list
## (ShopInterior), so what you see on a shelf is exactly the slot's qty.

var id := ""
var type_id := "convenience"
var name := ""
## Premises: {id, name, district (island:district), island, size, rent, price}.
var premises := {}
var owned := false   # bought outright: no rent
var open := true     # the owner's open/closed switch (hours still apply)
var prices := {}     # product id -> price per unit
var slots: Array = []   # [{fixture, unit, product, qty, cap}]
var fixtures := {}      # kind -> count
var upgrades: Array = []
var backroom: Stock
## Every fixture that holds stock, in slot order (the first four as saves
## have always had them).
const FIXTURE_KINDS := ["shelf", "fridge", "coffee", "pickmix", "rail", "table", "cake", "hotcab", "techtable"]
## Cases put down on the shop floor (no limit): they wait by the door until
## there's room in the stockroom (tidy_pile).
var floor_pile: Stock
var reputation := 40.0
var cleanliness := 1.0
var staff: Array = []   # employee dicts (Staff)
var today := {}
var history: Array = []  # last 14 day reports
var lifetime := {"revenue": 0.0, "profit": 0.0, "customers": 0}
var orders: Array = []   # [{units: {id: n}, due_day, fee}] manager re-orders on their way
var opened_day := 1

# --- live state (not saved) ---
## The player is here: shoppers are walking agents (ShopFloor), not the
## statistical model. pending_arrivals is how many the sim has sent.
var live := false
var pending_arrivals := 0
var player_at_till := false
var _arrival_acc := 0.0


func _init(p_id := "", p_type := "convenience") -> void:
	id = p_id
	type_id = p_type
	backroom = Stock.new(0, "backroom")
	floor_pile = Stock.new(0, "floor")
	reset_today()


func type_def() -> Dictionary:
	return EmpireData.business_type(type_id)


func district_key() -> String:
	return String(premises.get("district", "west:suburb"))


func district() -> Dictionary:
	return EmpireData.district(district_key())


func island() -> String:
	return String(premises.get("island", district().get("island", "west")))


func rent_per_day() -> float:
	return 0.0 if owned else float(premises.get("rent", 0.0))


func flagship_scale() -> int:
	if not premises.get("flagship", false):
		return 1
	var area := float(premises.get("size", 360.0))
	return clampi(roundi(area / 92.0), 3, 14)


func expected_backroom_capacity() -> int:
	var scale := flagship_scale()
	var base := int(type_def().get("backroom_cases", 20)) * scale
	if has_upgrade("backroom"):
		base += int(EmpireData.upgrade("backroom").get("backroom", 0)) * scale
	return base


# ------------------------------------------------------------- setup
func setup_new(p_premises: Dictionary, day: int) -> void:
	premises = p_premises.duplicate()
	name = String(premises.get("shop_name", "Corner Shop"))
	opened_day = day
	var t := type_def()
	fixtures = (t.get("base_fixtures", {}) as Dictionary).duplicate()
	var scale_factor := flagship_scale()
	backroom.case_capacity = int(t.get("backroom_cases", 20)) * scale_factor
	if premises.get("flagship", false):
		for key in fixtures:
			if key != "till":
				fixtures[key] = int(fixtures[key]) * (mini(scale_factor, 9) if key == "fridge" else scale_factor)
		fixtures["till"] = 3
	reputation = EmpireData.rep_param("start")
	for pid in EmpireData.product_ids():
		prices[pid] = EmpireData.rrp(pid)
	rebuild_slots()


## Makes `slots` match the fixtures (keeps existing slot contents in order).
func rebuild_slots() -> void:
	var t := type_def()
	var per: Dictionary = t.get("slots_per", {})
	var caps: Dictionary = t.get("slot_units", {})
	var old := {}  # "kind:unit:k" -> slot
	var seen := {}
	for o: Dictionary in slots:
		var base := "%s:%d" % [o["fixture"], int(o["unit"])]
		var k := int(seen.get(base, 0))
		seen[base] = k + 1
		old["%s:%d" % [base, k]] = o
	slots = []
	for kind in FIXTURE_KINDS:
		var n := int(fixtures.get(kind, 0))
		for u in n:
			for k in int(per.get(kind, 0)):
				var s := {"fixture": kind, "unit": u, "product": "", "qty": 0, "cap": int(caps.get(kind, 20))}
				if kind == "coffee":
					s["product"] = "coffee"
				elif kind == "pickmix":
					s["product"] = "pick_mix"
				var o: Dictionary = old.get("%s:%d:%d" % [kind, u, k], {})
				if not o.is_empty():
					s["product"] = o["product"]
					s["qty"] = o["qty"]
				slots.append(s)


func slot_indices(kind: String) -> Array:
	var out: Array = []
	for i in slots.size():
		if slots[i]["fixture"] == kind:
			out.append(i)
	return out


## Units of a product on the shop floor (all slots).
func shelf_qty(pid: String) -> int:
	var n := 0
	for s: Dictionary in slots:
		if s["product"] == pid:
			n += int(s["qty"])
	return n


func shelf_units() -> int:
	var n := 0
	for s: Dictionary in slots:
		n += int(s["qty"])
	return n


func stocked_products() -> Array:
	var out: Array = []
	for s: Dictionary in slots:
		if s["product"] != "" and not out.has(s["product"]):
			out.append(s["product"])
	return out


func can_hold(slot_i: int, pid: String) -> bool:
	if slot_i < 0 or slot_i >= slots.size():
		return false
	var s: Dictionary = slots[slot_i]
	if String(EmpireData.product(pid).get("fixture", "")) != s["fixture"]:
		return false
	return s["product"] == pid or int(s["qty"]) == 0


## Puts up to n units of pid from `src` onto slot i. Returns units moved.
func shelve(src: Stock, slot_i: int, pid: String, n: int) -> int:
	if not can_hold(slot_i, pid):
		return 0
	var s: Dictionary = slots[slot_i]
	var moved := mini(mini(n, src.qty(pid)), int(s["cap"]) - int(s["qty"]))
	if moved <= 0:
		return 0
	src._add(pid, -moved)
	s["product"] = pid
	s["qty"] = int(s["qty"]) + moved
	return moved


## Takes up to n units back off slot i into `dst` (clearing a slot, or a
## shopper's basket). Returns units moved.
func unshelve(dst: Stock, slot_i: int, n: int) -> int:
	if slot_i < 0 or slot_i >= slots.size():
		return 0
	var s: Dictionary = slots[slot_i]
	var pid: String = s["product"]
	if pid == "":
		return 0
	var moved := mini(mini(n, int(s["qty"])), dst.room_for(pid))
	if moved <= 0:
		return 0
	s["qty"] = int(s["qty"]) - moved
	dst._add(pid, moved)
	return moved


## Slot to take pid from (fullest first), or -1.
func slot_with(pid: String) -> int:
	var best := -1
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s["product"] == pid and int(s["qty"]) > 0 and (best < 0 or int(s["qty"]) > int(slots[best]["qty"])):
			best = i
	return best


## Best slot to put pid on: the emptiest slot already showing it, else an
## empty slot of the right fixture. -1 if nowhere.
func slot_for(pid: String) -> int:
	var fx := String(EmpireData.product(pid).get("fixture", ""))
	var best := -1
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s["fixture"] == fx and s["product"] == pid and int(s["qty"]) < int(s["cap"]):
			if best < 0 or int(s["qty"]) < int(slots[best]["qty"]):
				best = i
	if best >= 0:
		return best
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s["fixture"] == fx and int(s["qty"]) == 0 and (s["product"] == "" or s["product"] == pid):
			return i
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s["fixture"] == fx and int(s["qty"]) == 0:
			return i
	return -1


# ------------------------------------------------------------- range
## Does this shop sell pid? Its kind's goods (less what the kind leaves out:
## a bakery isn't a grocer), and only when there's a fixture to show it on.
func sells(pid: String) -> bool:
	return EmpireData.type_sells(type_id, pid) and int(fixtures.get(String(EmpireData.product(pid).get("fixture", "")), 0)) > 0


## Everything this shop sells, most wanted first.
func sellable() -> Array:
	var out: Array = EmpireData.product_ids().filter(func(p): return sells(p))
	out.sort_custom(func(a, b): return float(EmpireData.product(a).get("demand", 1.0)) > float(EmpireData.product(b).get("demand", 1.0)))
	return out


## Units of each product the shop floor shows when it's full: the slots a
## product already has, and the empty slots shared out (products without a
## place first, most wanted first).
func shelf_targets() -> Dictionary:
	var out := {}
	var free := {}   # fixture -> [cap, ...]
	for s: Dictionary in slots:
		var pid := String(s["product"])
		if pid != "" and (sells(pid) or int(s["qty"]) > 0):
			out[pid] = int(out.get(pid, 0)) + int(s["cap"])
		elif pid == "" or int(s["qty"]) == 0:
			if not free.has(s["fixture"]):
				free[s["fixture"]] = []
			free[s["fixture"]].append(int(s["cap"]))
	var range_ := sellable()
	for fx in free:
		var pool: Array = range_.filter(func(p): return String(EmpireData.product(p)["fixture"]) == fx)
		if pool.is_empty():
			continue
		var order: Array = pool.filter(func(p): return not out.has(p)) + pool.filter(func(p): return out.has(p))
		var i := 0
		for cap: int in free[fx]:
			var pid: String = order[i % order.size()]
			out[pid] = int(out.get(pid, 0)) + cap
			i += 1
	return out


# ------------------------------------------------------------ pricing
func price(pid: String) -> float:
	return float(prices.get(pid, EmpireData.rrp(pid)))


## Prices are kept between 40% and 300% of the recommended retail price.
func set_price(pid: String, p: float) -> void:
	var r := EmpireData.rrp(pid)
	prices[pid] = snappedf(clampf(p, r * 0.4, r * 3.0), 0.05)


# ----------------------------------------------------------- upgrades
func has_upgrade(u: String) -> bool:
	return upgrades.has(u)


func available_upgrades() -> Array:
	var out: Array = []
	for u in type_def().get("upgrades", []):
		if not upgrades.has(u):
			out.append(u)
	return out


func apply_upgrade(u: String) -> void:
	if upgrades.has(u):
		return
	upgrades.append(u)
	var d := EmpireData.upgrade(u)
	for k in d.get("adds", {}):
		fixtures[k] = int(fixtures.get(k, 0)) + int(d["adds"][k])
	if d.has("backroom"):
		backroom.case_capacity += int(d["backroom"]) * flagship_scale()
	rebuild_slots()


func _upgrade_sum(key: String) -> float:
	var v := 0.0
	for u in upgrades:
		v += float(EmpireData.upgrade(u).get(key, 0.0))
	return v


func quality_bonus() -> float:
	return _upgrade_sum("quality")


func footfall_bonus() -> float:
	return _upgrade_sum("footfall")


func dirt_factor() -> float:
	return maxf(1.0 + _upgrade_sum("dirt"), 0.2)


func has_honest_staff() -> bool:
	for e in staff:
		if not e.get("off", false) and String(e.get("role", "")) in ["cashier", "manager"] and Staff.has_trait(e, "honest"):
			return true
	return false


func theft_rate() -> float:
	var rate := float(EmpireData.upgrade("security").get("theft", 0.005)) if has_upgrade("security") \
		else float(EmpireData.file("business_types").get("theft_base", 0.03))
	if has_honest_staff():
		rate *= 0.5
	return rate


func utilities_per_day() -> float:
	return float(EmpireData.economy().get("utilities_base", 5.0)) + float(type_def().get("utilities", 0.0)) \
		+ _upgrade_sum("utilities")


func tills() -> int:
	return int(fixtures.get("till", 1))


# ------------------------------------------------------------ staff
func staff_with(role: String) -> Array:
	return staff.filter(func(e): return e["role"] == role and not e.get("off", false))


func has_role(role: String) -> bool:
	return not staff_with(role).is_empty()


func wages_per_hour() -> float:
	var w := 0.0
	for e in staff:
		if not e.get("off", false):
			w += float(e["wage"])
	return w


# ------------------------------------------------------------- hours
var _custom_hours := Vector2i(-1, -1)


func set_hours(opens: int, closes: int) -> bool:
	if opens < 0 or closes > 24 or opens >= closes:
		return false
	_custom_hours = Vector2i(opens, closes)
	return true


func reset_hours() -> void:
	_custom_hours = Vector2i(-1, -1)


func hours() -> Vector2:
	if _custom_hours.x >= 0:
		return Vector2(_custom_hours)
	var t := type_def()
	return Vector2(float(t.get("open", 7)), float(t.get("close", 22)))


func within_hours(hour: float) -> bool:
	var h := hours()
	return hour >= h.x and hour < h.y


## Customers come in: the switch is on, it's opening hours, and someone can
## take their money (the owner in person, or a cashier on shift).
func trading(hour: float) -> bool:
	if not open or not within_hours(hour):
		return false
	return live or has_role("cashier")


## What the shop is doing now, for every screen that shows it:
## [key, label, tone] – key: trading / closed / after_hours / no_stock /
## no_cashier; tone: good / warn / bad / muted.
func status(hour: float) -> Array:
	if not open:
		return ["closed", "CLOSED", "muted"]
	if not within_hours(hour):
		return ["after_hours", "CLOSED · opens %02d:00" % int(hours().x), "muted"]
	if shelf_units() == 0:
		return ["no_stock", "OUT OF STOCK", "bad"]
	if not live and not has_role("cashier"):
		return ["no_cashier", "NO ONE ON THE TILL", "warn"]
	return ["trading", "TRADING", "good"]


## Shelves filled, 0..1 (of what the fixtures hold).
func shelf_fill() -> float:
	var cap := 0
	for s in slots:
		cap += int(s["cap"])
	return float(shelf_units()) / float(maxi(cap, 1))


## Profit of the last closed day ({} before the first day ends).
func last_day() -> Dictionary:
	return history[-1] if not history.is_empty() else {}


# ------------------------------------------------------------ reports
func reset_today() -> void:
	today = {"revenue": 0.0, "cogs": 0.0, "customers": 0, "served": 0, "units": 0, "stockouts": 0,
		"not_stocked": 0, "too_expensive": 0, "walked_out": 0, "stolen": 0, "stolen_cost": 0.0,
		"wages": 0.0, "rent": 0.0, "utilities": 0.0, "fees": 0.0, "other": 0.0, "by_product": {}}


func add_rep(v: float) -> void:
	reputation = clampf(reputation + v, 0.0, 100.0)


func stock_units() -> int:
	return shelf_units() + backroom.total_units() + floor_pile.total_units()


## Moves cases from the floor pile into the stockroom while it has room.
## Returns units moved.
func tidy_pile() -> int:
	var moved := 0
	for pid in floor_pile.units.keys():
		moved += Stock.transfer(floor_pile, backroom, pid, floor_pile.qty(pid))
	return moved


# --------------------------------------------------------------- save
func to_dict() -> Dictionary:
	var sl: Array = []
	for s: Dictionary in slots:
		sl.append({"fixture": s["fixture"], "unit": s["unit"], "product": s["product"], "qty": s["qty"], "cap": s["cap"]})
	return {"id": id, "type": type_id, "name": name, "premises": premises.duplicate(true), "owned": owned,
		"open": open, "prices": prices.duplicate(), "slots": sl, "fixtures": fixtures.duplicate(),
		"upgrades": upgrades.duplicate(), "backroom": backroom.to_dict(), "floor_pile": floor_pile.to_dict(), "reputation": reputation,
		"cleanliness": cleanliness, "staff": staff.duplicate(true), "today": today.duplicate(true),
		"history": history.duplicate(true), "lifetime": lifetime.duplicate(), "orders": orders.duplicate(true),
		"opened_day": opened_day, "open_hour": _custom_hours.x, "close_hour": _custom_hours.y}


static func from_dict(d: Dictionary) -> Business:
	var b := Business.new(String(d.get("id", "")), String(d.get("type", "convenience")))
	b.name = String(d.get("name", "Shop"))
	b.premises = d.get("premises", {})
	b.owned = bool(d.get("owned", false))
	b.open = bool(d.get("open", true))
	b.set_hours(int(d.get("open_hour", -1)), int(d.get("close_hour", -1)))
	for pid in d.get("prices", {}):
		b.prices[String(pid)] = float(d["prices"][pid])
	for pid in EmpireData.product_ids():
		if not b.prices.has(pid):
			b.prices[pid] = EmpireData.rrp(pid)
	b.fixtures = d.get("fixtures", {})
	for k in b.fixtures:
		b.fixtures[k] = int(b.fixtures[k])
	b.upgrades = d.get("upgrades", [])
	b.backroom = Stock.from_dict(d.get("backroom", {}))
	b.floor_pile = Stock.from_dict(d.get("floor_pile", {"cap": 0, "label": "floor"}))
	b.floor_pile.case_capacity = 0
	b.reputation = float(d.get("reputation", 40.0))
	b.cleanliness = float(d.get("cleanliness", 1.0))
	b.staff = d.get("staff", [])
	b.history = d.get("history", [])
	b.lifetime = d.get("lifetime", b.lifetime)
	b.orders = d.get("orders", [])
	b.opened_day = int(d.get("opened_day", 1))
	if d.has("today"):
		b.today.merge(d["today"], true)
	b.rebuild_slots()
	var saved: Array = d.get("slots", [])
	for i in mini(saved.size(), b.slots.size()):
		var s: Dictionary = saved[i]
		if s.get("fixture") == b.slots[i]["fixture"]:
			var pid := String(s.get("product", ""))
			if pid == "" or EmpireData.products().has(pid):
				b.slots[i]["product"] = pid
				b.slots[i]["qty"] = clampi(int(s.get("qty", 0)), 0, int(b.slots[i]["cap"]))
	return b
