class_name EmpireData
extends RefCounted
## Read-only game data from config/empire/*.json, loaded once and cached.
## Everything tunable about the economy lives in those files, not in code:
## products, districts, business types and upgrades, staff roles, vehicles
## and career milestones.

const DIR := "res://config/empire/"

static var _cache := {}


static func file(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var f := FileAccess.open(DIR + name + ".json", FileAccess.READ)
	var d: Dictionary = {}
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			d = parsed
	if d.is_empty():
		push_error("EmpireData: cannot read %s.json" % name)
	_cache[name] = d
	return d


# ------------------------------------------------------------ products
static var _products := {}


static func products() -> Dictionary:
	if _products.is_empty():
		for p: Dictionary in file("products").get("products", []):
			_products[p["id"]] = p
	return _products


static func product(id: String) -> Dictionary:
	return products().get(id, {})


static func product_ids() -> Array:
	return products().keys()


static func categories() -> Dictionary:
	return file("products").get("categories", {})


static func case_qty(id: String) -> int:
	return int(product(id).get("case_qty", 1))


## Wholesale cost of one unit (case cost spread over the case).
static func unit_cost(id: String) -> float:
	var p := product(id)
	return float(p.get("case_cost", 0.0)) / maxf(float(p.get("case_qty", 1)), 1.0)


static func rrp(id: String) -> float:
	return float(product(id).get("rrp", 1.0))


static func colour(id: String) -> Color:
	return Color.from_string(String(product(id).get("colour", "#888888")), Color.GRAY)


# ------------------------------------------------------------- economy
static func economy() -> Dictionary:
	return file("economy")


static func district(key: String) -> Dictionary:
	var d: Dictionary = economy().get("districts", {})
	return d.get(key, d.get("west:suburb", {}))


static func hour_curve(hour: float) -> float:
	var c: Array = economy().get("hour_curve", [])
	if c.size() != 24:
		return 1.0
	var h := fposmod(hour, 24.0)
	var i := int(h)
	return lerpf(float(c[i]), float(c[(i + 1) % 24]), h - float(i))


static func rep_param(key: String) -> float:
	return float(economy().get("reputation", {}).get(key, 0.0))


# ------------------------------------------------------ business types
static func business_type(id: String) -> Dictionary:
	return file("business_types").get("types", {}).get(id, {})


static func business_types() -> Dictionary:
	return file("business_types").get("types", {})


static func upgrade(id: String) -> Dictionary:
	return file("business_types").get("upgrades", {}).get(id, {})


# --------------------------------------------------------------- staff
static func role(id: String) -> Dictionary:
	return file("staff").get("roles", {}).get(id, {})


static func roles() -> Dictionary:
	return file("staff").get("roles", {})


static func trait_info(id: String) -> Dictionary:
	return file("staff").get("traits", {}).get(id, {})


# ------------------------------------------------------------ vehicles
static func vehicle_model(id: String) -> Dictionary:
	return file("vehicles").get("models", {}).get(id, {})


static func vehicle_models() -> Dictionary:
	return file("vehicles").get("models", {})


static func hq() -> Dictionary:
	return file("hq")


# -------------------------------------------------------------- career
static func chapters() -> Array:
	return file("career").get("chapters", [])


## Money formatting for the UI: £1,234 or £12.50.
static func money(v: float, pence := false) -> String:
	var neg := v < 0.0
	var cents := int(round(absf(v) * 100.0))
	if not pence:
		cents = int(round(absf(v))) * 100
	var whole := cents / 100
	var s := str(whole)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	if pence:
		out += ".%02d" % (cents % 100)
	return ("-£" if neg and cents > 0 else "£") + out
