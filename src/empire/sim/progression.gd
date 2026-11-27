class_name Progression
extends RefCounted
## Career stages (2026-11-27; commerce.json "stages"): Entrepreneur →
## Business owner → Regional investor → Corporate executive → Tycoon →
## Billionaire. Each stage has three steps measured from the live game (no
## separate bookkeeping); finishing them moves you up and is announced. The
## last stage's £1bn target keeps going long after 100 hours. Saved:
## Empire.flags.stage (index of the current stage).


static func stages() -> Array:
	return EmpireData.file("commerce").get("stages", [])


static func index(e: Empire) -> int:
	return clampi(int(e.flags.get("stage", 0)), 0, maxi(stages().size() - 1, 0))


static func current(e: Empire) -> Dictionary:
	return stages()[index(e)] if not stages().is_empty() else {}


static func measure(e: Empire, k: String) -> float:
	match k:
		"businesses":
			return float(e.businesses.size())
		"profit_days":
			return float(e.stats.get("profitable_days", 0))
		"revenue_total":
			var v := 0.0
			for b: Business in e.businesses:
				v += float(b.lifetime.get("revenue", 0.0))
			return maxf(v, float(e.stats.get("revenue", 0.0)))
		"staff":
			var n := 0
			for b: Business in e.businesses:
				n += b.staff.size()
			return float(n + SupplyChain.fleet(e).size())
		"level_max":
			return float(Growth.max_level(e))
		"warehouse":
			return 1.0 if SupplyChain.has_warehouse(e) else 0.0
		"fleet":
			return float(SupplyChain.fleet(e).size())
		"contracts_done":
			return float(e.stats.get("contracts_done", 0))
		"hq":
			return float(e.hq_tier())
		"industries":
			return float(Company.industries(e))
		"acquired":
			return float(e.stats.get("rivals_bought", 0))
		"tower":
			return 1.0 if e.hq_tier() >= 3 or Ventures.owns_estate(e, "tower_offices") else 0.0
		"islands":
			return float(Company.islands(e))
		"net_worth":
			return e.net_worth()
	return 0.0


## The current stage's steps: [{t, n, have, done}].
static func steps(e: Empire, stage := -1) -> Array:
	var s: Dictionary = stages()[index(e) if stage < 0 else stage]
	var out: Array = []
	for st: Dictionary in s.get("steps", []):
		var have := measure(e, String(st["k"]))
		out.append({"t": st["t"], "n": float(st["n"]), "have": have, "done": have >= float(st["n"]), "k": st["k"]})
	return out


static func progress(e: Empire) -> float:
	var ss := steps(e)
	if ss.is_empty():
		return 1.0
	var f := 0.0
	for s: Dictionary in ss:
		f += clampf(float(s["have"]) / maxf(float(s["n"]), 1.0), 0.0, 1.0)
	return f / ss.size()


## Moves up as many stages as are complete (announces each). Returns true
## when the stage changed.
static func check(e: Empire) -> bool:
	var moved := false
	while index(e) < stages().size() - 1 and steps(e).all(func(s): return s["done"]):
		e.flags["stage"] = index(e) + 1
		moved = true
		var s := current(e)
		e._note("You're a %s now. Next: %s" % [s["name"], String(s["goal"]).to_lower()], "good", {"kind": "tab", "id": "commerce"})
	if index(e) == stages().size() - 1 and steps(e).all(func(s): return s["done"]) and not e.flags.get("billionaire", false):
		e.flags["billionaire"] = true
		e._note("Billionaire. The city runs on your companies.", "good")
		moved = true
	return moved
