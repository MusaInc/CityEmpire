class_name Growth
extends RefCounted
## Business levels (2026-11-27): every business grows from an independent
## shop (1) to an established business (2), a major retailer (3) and the
## chain's corporate flagship (4). A level is bought from the company account
## once its requirements are met (config/empire/commerce.json "levels") and
## changes the business for real: more fixtures and tills (the 3-D shop draws
## them – ShopInterior reads Business.level for the fit-out, branding and
## staff uniforms), deeper shelves and stockroom, more shoppers, a nicer shop
## (appeal), automated re-ordering from level 3, and at level 4 regional
## operations that lift every branch of the same trade and cut the chain's
## wholesale prices.
##
## State: Business.level (saved). Live: Business.chain_footfall (refresh()).

const MAX_LEVEL := 4


static func cfg() -> Dictionary:
	return EmpireData.file("commerce")


static func level_def(n: int) -> Dictionary:
	var lv: Array = cfg().get("levels", [])
	return lv[clampi(n, 1, lv.size()) - 1] if not lv.is_empty() else {}


static func level_name(n: int) -> String:
	return String(level_def(n).get("name", "Level %d" % n))


static func cost(b: Business, n: int) -> float:
	var k := float(cfg().get("cost_k", {}).get(b.type_id, 1.0))
	return float(level_def(n).get("cost", 0.0)) * k * (1.5 if b.premises.get("flagship", false) else 1.0)


## Branches of the same trade the company runs (b's own included).
static func branches(e: Empire, type_id: String) -> int:
	return e.businesses.filter(func(x): return x.type_id == type_id).size()


static func _sum7(b: Business, key: String) -> float:
	var v := 0.0
	for r: Dictionary in b.history.slice(maxi(b.history.size() - 7, 0)):
		v += float(r.get(key, 0.0))
	return v


## What the next level needs: [{text, done}] ([] at the top level).
static func needs(e: Empire, b: Business) -> Array:
	if b.level >= MAX_LEVEL:
		return []
	var nd: Dictionary = level_def(b.level + 1).get("needs", {})
	var out: Array = []
	if nd.has("upgrades"):
		out.append({"text": "%d shop upgrades" % int(nd["upgrades"]), "done": b.upgrades.size() >= int(nd["upgrades"]),
			"have": "%d/%d" % [b.upgrades.size(), int(nd["upgrades"])]})
	if nd.has("staff"):
		var n := b.staff.size()
		out.append({"text": "%d staff" % int(nd["staff"]), "done": n >= int(nd["staff"]), "have": "%d/%d" % [n, int(nd["staff"])]})
	if nd.has("days_open"):
		var d := e.day - b.opened_day
		out.append({"text": "Open %d days" % int(nd["days_open"]), "done": d >= int(nd["days_open"]), "have": "%d/%d" % [mini(d, int(nd["days_open"])), int(nd["days_open"])]})
	if nd.get("manager", false):
		out.append({"text": "A manager", "done": b.staff.any(func(s): return s["role"] == "manager"), "have": ""})
	if nd.has("rep"):
		out.append({"text": "Reputation %d" % int(nd["rep"]), "done": b.reputation >= float(nd["rep"]), "have": "%d" % roundi(b.reputation)})
	if nd.has("profit_7"):
		var p := _sum7(b, "profit")
		out.append({"text": "In profit over the last week", "done": b.history.size() > 0 and p > float(nd["profit_7"]), "have": EmpireData.money(p)})
	if nd.has("revenue_7"):
		var r := _sum7(b, "revenue")
		out.append({"text": "%s sales in a week" % EmpireData.money(float(nd["revenue_7"])), "done": r >= float(nd["revenue_7"]), "have": EmpireData.money(r)})
	if nd.has("hq"):
		out.append({"text": "A head office", "done": e.hq_tier() >= int(nd["hq"]), "have": ""})
	if nd.has("branches"):
		var n := branches(e, b.type_id)
		out.append({"text": "%d branches of this trade" % int(nd["branches"]), "done": n >= int(nd["branches"]), "have": "%d/%d" % [n, int(nd["branches"])]})
	return out


## "" when b can grow now, else why not.
static func block(e: Empire, b: Business) -> String:
	if b.level >= MAX_LEVEL:
		return "Already the flagship"
	for r: Dictionary in needs(e, b):
		if not r["done"]:
			return "Needs: %s" % r["text"]
	var c := cost(b, b.level + 1)
	if e.company_cash < c:
		return "Needs %s in the company account" % EmpireData.money(c)
	return ""


## Grows b one level (paid from the company account). "" = done.
static func grow(e: Empire, b: Business) -> String:
	var why := block(e, b)
	if why != "":
		return why
	var n := b.level + 1
	var c := cost(b, n)
	if not e.pay(c, "upgrade", "%s: %s fit-out" % [b.name, level_name(n)], b.id):
		return "Not enough money"
	apply_level(b, n)
	b.add_rep(3.0)
	refresh(e)
	e.stats["levels_bought"] = int(e.stats.get("levels_bought", 0)) + 1
	e._note("%s is now a %s" % [b.name, level_name(n)], "good", {"kind": "biz", "id": b.id})
	e.changed.emit()
	return ""


## The fit-out for level n: fixtures, tills, deeper shelves and stockroom.
static func apply_level(b: Business, n: int) -> void:
	var d := level_def(n)
	var main := main_fixture(b)
	var adds := int(d.get("adds", 0)) - int(level_def(b.level).get("adds", 0))
	if main != "" and adds > 0:
		b.fixtures[main] = int(b.fixtures.get(main, 0)) + adds
	var tills := int(d.get("tills", 0)) - int(level_def(b.level).get("tills", 0))
	if tills > 0:
		b.fixtures["till"] = b.tills() + tills
	b.level = n
	b.rebuild_slots()
	b.backroom.case_capacity = maxi(b.expected_backroom_capacity(), b.backroom.cases_used())


## The fixture a level adds more of: the first stock fixture of the type.
static func main_fixture(b: Business) -> String:
	for k in b.type_def().get("base_fixtures", {}):
		if k != "till":
			return String(k)
	return ""


static func cap_k(b: Business) -> float:
	return float(level_def(b.level).get("cap_k", 1.0))


static func backroom_k(b: Business) -> float:
	return float(level_def(b.level).get("backroom_k", 1.0))


static func footfall(b: Business) -> float:
	return float(level_def(b.level).get("footfall", 0.0)) + b.chain_footfall


static func quality(b: Business) -> float:
	return float(level_def(b.level).get("quality", 0.0))


## Level 3+ re-orders itself (no auto-restock fee, no manager needed).
static func automated(b: Business) -> bool:
	return bool(level_def(b.level).get("auto", false))


## Regional operations: each flagship lifts the other branches of its trade.
static func refresh(e: Empire) -> void:
	var lift := {}
	for b: Business in e.businesses:
		if b.level >= MAX_LEVEL:
			lift[b.type_id] = float(lift.get(b.type_id, 0.0)) + float(level_def(MAX_LEVEL).get("chain_footfall", 0.0))
	for b: Business in e.businesses:
		b.chain_footfall = 0.0 if b.level >= MAX_LEVEL else minf(float(lift.get(b.type_id, 0.0)), 0.2)


## Wholesale multiplier from flagships (the chain's buying power).
static func wholesale_k(e: Empire) -> float:
	var n := e.businesses.filter(func(x): return x.level >= MAX_LEVEL).size()
	return 1.0 - minf(float(n) * float(level_def(MAX_LEVEL).get("chain_wholesale", 0.0)), 0.09)


static func max_level(e: Empire) -> int:
	var m := 0
	for b: Business in e.businesses:
		m = maxi(m, b.level)
	return m
