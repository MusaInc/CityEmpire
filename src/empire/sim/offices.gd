class_name Offices
extends RefCounted
## Office companies on floors of the CBD towers (config/empire/offices.json).
## A company is a record in Empire.offices:
##   {id, unit (office unit id), name, type, desks, level, opened, rent,
##    today {revenue, wages, rent}, history [day reports], lifetime}
## Desks earn every day (and cost their wages), the floor costs rent; the
## day settles at midnight with the shops (Empire.end_day → settle). Each
## company also does something for your shops – the perks below are read by
## the shop economy, so a marketing agency really brings shoppers in.


static func cfg() -> Dictionary:
	return EmpireData.file("offices")


static func types() -> Dictionary:
	return cfg().get("types", {})


static func type_def(t: String) -> Dictionary:
	return types().get(t, {})


static func level_def(lv: int) -> Dictionary:
	var ls: Array = cfg().get("levels", [])
	return ls[clampi(lv - 1, 0, ls.size() - 1)] if not ls.is_empty() else {}


static func at(e: Empire, unit_id: String) -> Dictionary:
	for o in e.offices:
		if String(o["unit"]) == unit_id:
			return o
	return {}


static func by_id(e: Empire, id: String) -> Dictionary:
	for o in e.offices:
		if String(o["id"]) == id:
			return o
	return {}


## Daily rent of an office floor.
static func rent(unit: Dictionary) -> float:
	return roundf(float(unit.get("rent", 40.0)) * float(cfg().get("rent_k", 1.6)))


## What opening a company costs up front: three days' rent + the fit-out.
static func open_cost(unit: Dictionary) -> float:
	return rent(unit) * 3.0 + float(cfg().get("open_cost", 2500))


## Opens a company of `type` on an office floor. "" or why not.
static func open(e: Empire, unit: Dictionary, type: String, name := "") -> String:
	if not at(e, String(unit.get("id", ""))).is_empty():
		return "That floor is already yours"
	if not types().has(type):
		return "Unknown kind of company"
	var cost := open_cost(unit)
	if not e.pay(cost, "property", "Office floor: %s" % unit.get("name", "")):
		return "Not enough money (%s)" % EmpireData.money(cost)
	var td := type_def(type)
	var nm := name if name != "" else "%s %s" % [_company_word(e), String(td.get("suffix", "Ltd"))]
	var o := {"id": e.new_id("o"), "unit": String(unit["id"]), "name": nm, "type": type, "desks": int(cfg().get("start_desks", 2)),
		"level": 1, "opened": e.day, "rent": rent(unit), "pos": unit.get("pos", []), "district": unit.get("district", ""),
		"tower": unit.get("name", ""), "today": {}, "history": [], "lifetime": {"revenue": 0.0, "profit": 0.0}}
	_reset(o)
	e.offices.append(o)
	e._note("%s opened in %s." % [nm, unit.get("name", "the tower")], "good", {"kind": "office", "id": o["id"]})
	e._check_goals()
	e.changed.emit()
	return ""


## The company name: your brand's, else the founder's surname style.
static func _company_word(e: Empire) -> String:
	var b := String(e.brand.get("name", ""))
	if b != "":
		return b
	return ["Harbour", "Meridian", "Northgate", "Sterling", "Atlas"][e.offices.size() % 5]


static func max_desks(o: Dictionary) -> int:
	return int(level_def(int(o["level"])).get("desks", 4))


## Hire (+1) or let go (-1) a desk. "" or why not.
static func set_desks(e: Empire, o: Dictionary, delta: int) -> String:
	var n := int(o["desks"]) + delta
	if n < 1:
		return "Keep at least one desk"
	if n > max_desks(o):
		return "The floor is full – fit out more space"
	if delta < 0:
		# A week's notice (in today's costs, so the day's profit shows it).
		var pay := float(type_def(o["type"]).get("wage", 100.0)) * 0.5
		e.company_cash -= pay
		o["today"]["wages"] = float(o["today"]["wages"]) + pay
		e._book("company", -pay, "wages", "Notice: %s" % o["name"])
	o["desks"] = n
	e.changed.emit()
	return ""


static func upgrade(e: Empire, o: Dictionary) -> String:
	var lv := int(o["level"])
	var ls: Array = cfg().get("levels", [])
	if lv >= ls.size():
		return "Already the biggest fit-out"
	var nd: Dictionary = ls[lv]
	var cost := float(nd.get("cost", 0))
	if not e.pay(cost, "upgrade", "Office fit-out: %s" % o["name"]):
		return "Not enough money (%s)" % EmpireData.money(cost)
	o["level"] = lv + 1
	e._note("%s: %s" % [o["name"], nd.get("name", "")], "good", {"kind": "office", "id": o["id"]})
	e.changed.emit()
	return ""


## What a desk earns a day on average (for the UI).
static func per_desk(o: Dictionary) -> float:
	return float(type_def(o["type"]).get("per_desk", 150.0)) * float(level_def(int(o["level"])).get("k", 1.0))


## Expected profit a day (before luck).
static func expected(o: Dictionary) -> float:
	var td := type_def(o["type"])
	return int(o["desks"]) * (per_desk(o) - float(td.get("wage", 100.0))) - float(o["rent"])


static func _reset(o: Dictionary) -> void:
	o["today"] = {"revenue": 0.0, "wages": 0.0, "rent": 0.0}


## Midnight: the day's contracts, wages and rent; returns the total profit
## (Empire.end_day adds it to the company's day).
static func settle(e: Empire) -> float:
	var total := 0.0
	for o in e.offices:
		var td := type_def(o["type"])
		var t: Dictionary = o["today"]
		var luck := e.rng.randf_range(0.85, 1.15)
		var rev := roundf(int(o["desks"]) * per_desk(o) * luck)
		var wages := int(o["desks"]) * float(td.get("wage", 100.0))
		var r := float(o["rent"])
		t["revenue"] = float(t["revenue"]) + rev
		t["wages"] = float(t["wages"]) + wages
		t["rent"] = r
		e.company_cash += rev - wages - r
		e._book("company", rev, "office", "Contracts: %s" % o["name"])
		e._book("company", -wages, "wages", "Salaries: %s" % o["name"])
		e._book("company", -r, "rent", "Office rent: %s" % o["name"])
		var profit := float(t["revenue"]) - float(t["wages"]) - r
		var hist: Array = o["history"]
		hist.append({"day": e.day, "revenue": t["revenue"], "wages": t["wages"], "rent": r, "profit": profit, "desks": o["desks"]})
		if hist.size() > 14:
			o["history"] = hist.slice(hist.size() - 14)
		o["lifetime"]["revenue"] = float(o["lifetime"].get("revenue", 0.0)) + float(t["revenue"])
		o["lifetime"]["profit"] = float(o["lifetime"].get("profit", 0.0)) + profit
		total += profit
		_reset(o)
	return total


# ------------------------------------------------------------- perks
static func _desks(e: Empire, type: String) -> int:
	var n := 0
	for o in e.offices:
		if o["type"] == type:
			n += int(o["desks"])
	return n


## Marketing agency: shoppers ×(1 + this).
static func footfall_bonus(e: Empire) -> float:
	return minf(0.02 * _desks(e, "marketing"), 0.2)


## Property management: rents ×(1 − this).
static func rent_discount(e: Empire) -> float:
	return minf(0.02 * _desks(e, "property"), 0.2)


## Tech studio: card fees ×(1 − this).
static func fee_cut(e: Empire) -> float:
	return minf(0.1 * _desks(e, "tech"), 0.8)


## Logistics: deliveries free (2+ desks).
static func free_delivery(e: Empire) -> bool:
	return _desks(e, "logistics") >= 2


## Logistics with 4+ desks: phone orders arrive the same evening.
static func same_day(e: Empire) -> bool:
	return _desks(e, "logistics") >= 4


## Recruitment: [extra candidates, skill bump, temps cover sick staff].
static func recruitment(e: Empire) -> Array:
	var d := _desks(e, "recruitment")
	return [mini(d, 6), 1 if d >= 3 else 0, d >= 5]
