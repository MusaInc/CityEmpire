class_name Careers
extends RefCounted
## Career progression & economy overhaul (2026-11-26). Pure rules over the
## Empire (state in e.flags["career"]); the game drives courier runs and the
## phone shows it all (career_pages.gd).
##
## Early game – a way back up from nothing, keeping the £650 start:
##   * shift work at any open business you don't own: four hours, paid by
##     the hour at the district's rate, twice a day at most;
##   * courier runs (CourierRun in the game): a parcel to a door 0.5-1.5 km
##     away, paid on arrival, more for being quick.
## Running shops – less repetition, more decisions:
##   * a daily trade target per shop (serve N, sell N units, take £N) with a
##     supplier bonus;
##   * bulk buying: 5/10/15% off at 20/60/150 cases;
##   * automatic restocking without a manager (the supplier's service, a fee
##     per delivery) and a daily purchasing budget per shop for managers and
##     the service alike;
##   * one consolidated report across every shop, office and the club.
## Late game – wealth changes how you play:
##   * a credit line against what the company's worth (cheaper than loans);
##   * tiers by net worth: Established (£250k) – deliveries free; Tycoon (£1m)
##     – a driver takes you anywhere (Explore); Magnate (£5m) – auto-restock
##     costs nothing and your managers buy at the bulk price.

const SHIFT_HOURS := 4
const SHIFTS_A_DAY := 2
const SHIFT_RATE := 11.5           # £/h at district affluence 1.0
const BULK := [[150, 0.15], [60, 0.10], [20, 0.05]]
const AUTO_FEE := 35.0
const TIERS := [[5000000.0, "Magnate"], [1000000.0, "Tycoon"], [250000.0, "Established"], [0.0, "Starting out"]]


static func state(e: Empire) -> Dictionary:
	if not e.flags.has("career"):
		e.flags["career"] = {"shifts": {}, "earned": 0.0, "runs": 0, "targets": {}, "purchasing": {}, "credit": 0.0}
	return e.flags["career"]


# ------------------------------------------------------------ tiers
static func net_worth(e: Empire) -> float:
	return e.net_worth()


static func tier(e: Empire) -> String:
	var nw := net_worth(e)
	for t in TIERS:
		if nw >= float(t[0]):
			return String(t[1])
	return "Starting out"


static func has_perk(e: Empire, perk: String) -> bool:
	var nw := net_worth(e)
	match perk:
		"free_delivery":
			return nw >= 250000.0
		"driver":
			return nw >= 1000000.0
		"magnate":
			return nw >= 5000000.0
	return false


# ------------------------------------------------------------ shift work
static func shift_rate(affluence: float) -> float:
	return roundf(SHIFT_RATE * clampf(affluence, 0.8, 1.5) * 10.0) / 10.0


## "" or why you can't work a shift now.
static func shift_block(e: Empire) -> String:
	var h := e.hour()
	if h < 7.0 or h > 19.0:
		return "Shifts start between 07:00 and 19:00"
	var st := state(e)
	if int(st["shifts"].get(str(e.day), 0)) >= SHIFTS_A_DAY:
		return "You've worked two shifts today – rest"
	return ""


## Four hours' work (the clock moves on; your own shops trade meanwhile).
## Returns the pay, or -1 with nothing done.
static func work_shift(e: Empire, employer: String, affluence: float) -> float:
	if shift_block(e) != "":
		return -1.0
	var pay := shift_rate(affluence) * SHIFT_HOURS
	e.fast_forward(SHIFT_HOURS * 60.0)
	e.personal_cash += pay
	e._book("personal", pay, "wages_in", "Shift at %s" % employer)
	var st := state(e)
	st["shifts"][str(e.day)] = int(st["shifts"].get(str(e.day), 0)) + 1
	st["earned"] = float(st["earned"]) + pay
	e.changed.emit()
	return pay


# ------------------------------------------------------------ courier runs
## Pay for a run of `metres`: base + distance; a bonus for beating the time.
static func courier_pay(metres: float) -> float:
	return roundf(14.0 + metres * 0.035)


static func courier_time(metres: float) -> float:
	return 4.0 + metres / 140.0   # game minutes (a brisk drive; on foot needs hurrying)


static func courier_done(e: Empire, run: Dictionary, minutes_taken: float) -> float:
	var pay := float(run["pay"])
	var bonus := roundf(pay * 0.5) if minutes_taken <= float(run["minutes"]) else 0.0
	e.personal_cash += pay + bonus
	e._book("personal", pay + bonus, "wages_in", "Courier run to %s" % run.get("to_name", "a client"))
	var st := state(e)
	st["runs"] = int(st["runs"]) + 1
	st["earned"] = float(st["earned"]) + pay + bonus
	e.changed.emit()
	return pay + bonus


# ------------------------------------------------------------ daily targets
## Each shop's target for today: {kind, n, bonus, label}. Rolled in the
## morning from the shop's own recent trade, so it stretches without being
## out of reach.
static func roll_targets(e: Empire) -> void:
	var st := state(e)
	var t := {}
	for b: Business in e.businesses:
		var hist: Array = b.history
		var avg_served := 25.0
		var avg_rev := 300.0
		var avg_units := 60.0
		if not hist.is_empty():
			var recent := hist.slice(maxi(0, hist.size() - 3))
			avg_served = recent.reduce(func(a, r): return a + float(r["served"]), 0.0) / recent.size()
			avg_rev = recent.reduce(func(a, r): return a + float(r["revenue"]), 0.0) / recent.size()
			avg_units = recent.reduce(func(a, r): return a + float(r["units"]), 0.0) / recent.size()
		var pick := e.rng.randi() % 3
		var stretch := e.rng.randf_range(1.08, 1.25)
		var target := {}
		match pick:
			0:
				var n := maxi(10, int(ceil(avg_served * stretch)))
				target = {"kind": "served", "n": n, "label": "Serve %d customers" % n}
			1:
				var n2 := maxi(30, int(ceil(avg_units * stretch)))
				target = {"kind": "units", "n": n2, "label": "Sell %d items" % n2}
			_:
				var n3 := maxf(150.0, roundf(avg_rev * stretch / 10.0) * 10.0)
				target = {"kind": "revenue", "n": n3, "label": "Take %s" % EmpireData.money(n3)}
		target["bonus"] = roundf(clampf(avg_rev * 0.08, 25.0, 600.0))
		t[b.id] = target
	st["targets"] = t


## End of day: pays the bonus for targets met (before today's figures reset).
static func settle_targets(e: Empire) -> float:
	var st := state(e)
	var paid := 0.0
	for b: Business in e.businesses:
		var tg: Dictionary = st["targets"].get(b.id, {})
		if tg.is_empty():
			continue
		var have := float(b.today.get(String(tg["kind"]), 0))
		if have >= float(tg["n"]):
			var bonus := float(tg["bonus"])
			e.company_cash += bonus
			e._book("company", bonus, "bonus", "Supplier bonus: %s hit its target" % b.name, b.id)
			paid += bonus
	if paid > 0.0:
		e._note("Daily targets met: %s in supplier bonuses" % EmpireData.money(paid), "good", {"kind": "tab", "id": "businesses"})
	return paid


# ------------------------------------------------------------ purchasing
## Bulk discount on an order of `cases` cases (1.0 = list price).
static func bulk_k(e: Empire, cases: int, by_manager := false) -> float:
	if by_manager and has_perk(e, "magnate"):
		return 1.0 - float(BULK[0][1])
	for tier_: Array in BULK:
		if cases >= int(tier_[0]):
			return 1.0 - float(tier_[1])
	return 1.0


static func purchasing(e: Empire, biz_id: String) -> Dictionary:
	var p: Dictionary = state(e)["purchasing"]
	if not p.has(biz_id):
		p[biz_id] = {"auto": false, "budget": 400.0}
	return p[biz_id]


static func auto_fee(e: Empire) -> float:
	return 0.0 if has_perk(e, "magnate") else AUTO_FEE


# ------------------------------------------------------------ financing
## A revolving credit line against the business: up to a third of what
## the shops, offices and club are worth, at half the loan rate.
static func credit_limit(e: Empire) -> float:
	var worth := 0.0
	for b: Business in e.businesses:
		worth += float(b.lifetime.get("revenue", 0.0)) * 0.05 + 4000.0
	worth += float(e.offices.size()) * 15000.0 + Club.value(e)
	return roundf(worth / 3.0 / 1000.0) * 1000.0


static func draw_credit(e: Empire, amount: float) -> String:
	var st := state(e)
	if float(st["credit"]) + amount > credit_limit(e):
		return "Over your credit limit (%s)" % EmpireData.money(credit_limit(e))
	st["credit"] = float(st["credit"]) + amount
	e.company_cash += amount
	e._book("company", amount, "loan", "Credit line drawn")
	e.changed.emit()
	return ""


static func repay_credit(e: Empire, amount: float) -> String:
	var st := state(e)
	var a := minf(amount, float(st["credit"]))
	if a <= 0.0:
		return "Nothing owed"
	if e.company_cash < a:
		return "Not enough company cash"
	e.company_cash -= a
	st["credit"] = float(st["credit"]) - a
	e._book("company", -a, "loan", "Credit line repaid")
	e.changed.emit()
	return ""


## Daily interest on the credit line (end of day).
static func credit_interest(e: Empire) -> float:
	var owed := float(state(e)["credit"])
	if owed <= 0.0:
		return 0.0
	var i := owed * 0.0012
	e.company_cash -= i
	e._book("company", -i, "interest", "Credit line interest")
	return i


# ------------------------------------------------------------ report
## Last `days` days across the portfolio: per shop and totals.
static func report(e: Empire, days := 7) -> Dictionary:
	var rows: Array = []
	var tot := {"revenue": 0.0, "profit": 0.0, "customers": 0, "stockouts": 0, "walked_out": 0}
	for b: Business in e.businesses:
		var h: Array = b.history.slice(maxi(0, b.history.size() - days))
		var r := {"name": b.name, "id": b.id, "revenue": 0.0, "profit": 0.0, "customers": 0, "stockouts": 0, "walked_out": 0,
			"reputation": b.reputation, "manager": b.has_role("manager"), "auto": bool(purchasing(e, b.id)["auto"])}
		for d: Dictionary in h:
			for k in ["revenue", "profit"]:
				r[k] = float(r[k]) + float(d.get(k, 0.0))
			for k2 in ["customers", "stockouts", "walked_out"]:
				r[k2] = int(r[k2]) + int(d.get(k2, 0))
		for k3 in tot:
			tot[k3] = (tot[k3] as float) + float(r[k3]) if k3 in ["revenue", "profit"] else int(tot[k3]) + int(r[k3])
		var advice := ""
		if int(r["stockouts"]) > maxi(5, int(r["customers"]) / 10):
			advice = "Running out of stock – raise its budget or turn on auto-restock"
		elif int(r["walked_out"]) > maxi(5, int(r["customers"]) / 12):
			advice = "Queues are losing customers – hire a cashier or add a till"
		elif float(r["profit"]) < 0.0:
			advice = "Losing money – check prices and wages"
		r["advice"] = advice
		rows.append(r)
	rows.sort_custom(func(a, b): return float(a["profit"]) > float(b["profit"]))
	return {"rows": rows, "total": tot, "offices": e.offices.size(), "club": Club.value(e)}
