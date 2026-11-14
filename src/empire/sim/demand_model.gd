class_name DemandModel
extends RefCounted
## How shoppers behave. One model drives both the walking customers in the
## shop you're standing in (ShopFloor agents) and the statistical simulation
## of every other shop, so a business earns the same way whether you watch
## it or not.
##
##  * Footfall: district shoppers per hour × time-of-day curve × reputation
##    (0.5..1.5) × upgrades (signage) × nearby competition.
##  * Each shopper comes in wanting 1-3 things, picked by the district's
##    category mix (Estates buy groceries, the Financial District buys coffee
##    and drinks), and has a private willingness to pay for each: the
##    recommended price × district affluence × a personal spread, raised by a
##    nicer, cleaner shop. They buy if the shelf has it and the price is
##    within that; otherwise it's a lost sale (and a reputation hit if the
##    shop normally sells it). Some grab an impulse snack.
##  * The aggregate demand curve therefore falls smoothly with price: a
##    small markup loses few sales, a big one loses most (test_economy).


static func arrivals_per_hour(b: Business, hour: float, competitors := 0.0, k := 1.0) -> float:
	var d := b.district()
	var rep := 0.5 + b.reputation / 100.0
	var comp := pow(float(EmpireData.economy().get("competition_factor", 0.75)), competitors)
	# (A clothing or phone shop sees fewer, bigger-spending shoppers than a
	# corner shop: the type's footfall_k.)
	var tk := float(b.type_def().get("footfall_k", 1.0))
	return float(d.get("footfall", 6.0)) * float(EmpireData.economy().get("footfall_scale", 1.0)) * EmpireData.hour_curve(hour) * rep * (1.0 + b.footfall_bonus()) * comp * k * tk


## Multiplier on what shoppers will pay: upgrades (lighting, floor) and a clean shop.
static func appeal(b: Business) -> float:
	return (1.0 + b.quality_bonus()) * (0.82 + 0.18 * clampf(b.cleanliness, 0.0, 1.0))


static func make_shopper(b: Business, rng: RandomNumberGenerator, mix_k := {}) -> Dictionary:
	var d := b.district()
	var bk: Dictionary = EmpireData.economy().get("basket", {})
	var tb: Array = b.type_def().get("basket", [bk.get("min", 1), bk.get("max", 3)])
	var n := rng.randi_range(int(tb[0]), int(tb[1]))
	var mix: Dictionary = (d.get("mix", {}) as Dictionary).duplicate()
	for c in mix_k:
		mix[c] = float(mix.get(c, 0.5)) * float(mix_k[c])
	var allowed: Array = b.type_def().get("categories", [])
	var wants: Array = []
	for i in n:
		var pid := _pick_product(mix, allowed, rng, b.fixtures)
		if pid != "" and not wants.has(pid):
			wants.append(pid)
	var spread: Array = EmpireData.economy().get("wtp_spread", [0.9, 1.7])
	var aff := float(d.get("affluence", 1.0))
	var wtp := {}
	for pid in wants:
		wtp[pid] = EmpireData.rrp(pid) * aff * rng.randf_range(float(spread[0]), float(spread[1]))
	var pat: Array = EmpireData.economy().get("patience_minutes", [6, 14])
	return {"wants": wants, "wtp": wtp, "patience": rng.randf_range(float(pat[0]), float(pat[1])),
		"impulse": rng.randf() < float(bk.get("impulse", 0.2)), "seed": rng.randi(),
		"spend_k": aff * rng.randf_range(float(spread[0]), float(spread[1]))}


static func _pick_product(mix: Dictionary, allowed: Array, rng: RandomNumberGenerator, fixtures := {}) -> String:
	var total := 0.0
	for c in allowed:
		total += float(mix.get(c, 0.5))
	var r := rng.randf() * total
	var cat := String(allowed[0]) if not allowed.is_empty() else ""
	for c in allowed:
		r -= float(mix.get(c, 0.5))
		if r <= 0.0:
			cat = c
			break
	var pool: Array = []
	var wsum := 0.0
	for pid in EmpireData.product_ids():
		var p := EmpireData.product(pid)
		# (Only things this shop could have a place for: a bakery's shelf
		# holds loaves, not the milk that needs a fridge.)
		if p["cat"] == cat and (fixtures.is_empty() or int(fixtures.get(String(p.get("fixture", "")), 0)) > 0):
			pool.append(pid)
			wsum += float(p.get("demand", 1.0))
	var q := rng.randf() * wsum
	for pid in pool:
		q -= float(EmpireData.product(pid).get("demand", 1.0))
		if q <= 0.0:
			return pid
	return pool[-1] if not pool.is_empty() else ""


## What happens when the shopper reaches the shelf for `pid`: "buy" (with
## qty), "stockout" (the shop sells it but the shelf is empty),
## "not_stocked" (the shop doesn't sell it) or "too_expensive".
static func decide(b: Business, shopper: Dictionary, pid: String) -> Dictionary:
	var stocked := b.stocked_products().has(pid)
	if not stocked:
		return {"result": "not_stocked"}
	if b.shelf_qty(pid) <= 0:
		return {"result": "stockout"}
	var limit := float(shopper["wtp"].get(pid, EmpireData.rrp(pid))) * appeal(b)
	if b.price(pid) > limit:
		return {"result": "too_expensive"}
	# Cheap relative to what they'd pay: sometimes two.
	var two := b.price(pid) < limit * 0.75 and (int(shopper.get("seed", 0)) + pid.hash()) % 4 == 0
	return {"result": "buy", "qty": 2 if two else 1}


## Impulse buy at the end of the trip: the cheapest-looking sweet or snack on
## the shelves they'd pay for, or "".
static func impulse_pick(b: Business, shopper: Dictionary) -> String:
	if not shopper.get("impulse", false):
		return ""
	var k := float(shopper.get("spend_k", 1.0)) * appeal(b)
	var best := ""
	var best_r := 1e9
	for pid in b.stocked_products():
		var cat := String(EmpireData.product(pid).get("cat", ""))
		if not cat in ["sweets", "snacks", "drinks"] or b.shelf_qty(pid) <= 0 or shopper["wants"].has(pid):
			continue
		var r := b.price(pid) / (EmpireData.rrp(pid) * k)
		if r <= 1.0 and r < best_r:
			best_r = r
			best = pid
	return best


## The share of shoppers who'd pay `price` for pid in this business
## (analytic: used by the pricing panel's demand hint and the tests).
static func buy_share(b: Business, pid: String, p: float) -> float:
	var spread: Array = EmpireData.economy().get("wtp_spread", [0.9, 1.7])
	var aff := float(b.district().get("affluence", 1.0))
	var lo := EmpireData.rrp(pid) * aff * float(spread[0]) * appeal(b)
	var hi := EmpireData.rrp(pid) * aff * float(spread[1]) * appeal(b)
	return clampf((hi - p) / maxf(hi - lo, 0.001), 0.0, 1.0)
