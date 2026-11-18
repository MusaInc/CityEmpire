class_name Empire
extends RefCounted
## The whole game state of City Empire and the economy that runs it. No
## nodes, no rendering: the 3-D game (EmpireGame) reads and drives it, the
## tests run it headless at thousands of game-minutes a second, and it saves
## to one versioned dictionary (to_dict / from_dict).
##
## Money: personal savings (you) and the company account (every business
## banks its takings there and pays its bills from it). Profit is accrual
## style: revenue − cost of the goods sold − running costs, so buying stock
## isn't a "loss" (it's stock, valued at its weighted average cost).
##
## Time: `minute` of `day`. advance() steps whole game minutes; each minute
## every trading business gets shoppers (as walking agents in the shop the
## player is in, statistically everywhere else), staff do their work and
## shelves get messier. At midnight the day closes: wages, rent, utilities,
## shrinkage, loan interest, a report per business, career milestones.

signal notified(text: String, kind: String)  # kind: info / good / warn / bad
signal sold(biz_id: String, amount: float)
signal day_ended(report: Dictionary)
signal goal_done(goal: Dictionary)
signal changed
signal won

const VERSION := 6

var seed := 1
var day := 1
var minute := 450.0
var personal_cash := 0.0
var company_cash := 0.0
var businesses: Array = []      # Business
var vehicles: Array = []        # {id, model, cargo (Stock), condition, km, pos, yaw, driver}
var properties: Array = []      # {id, kind, name, price, let, income}
var loans: Array = []           # {id, principal, rate, day, due}
## The goods in the player's hands (a stack of cases).
var carried := Stock.new(3, "hands")
## Bought at a wholesaler, waiting on the collection bay: wholesaler id -> Stock.
var pallets := {}
## Weighted average purchase cost per unit (stock valuation and COGS).
var avg_cost := {}
var stats := {}
var goals_done: Array = []
var candidates: Array = []
var ledger: Array = []          # recent money movements, newest last
var log: Array = []             # notifications, newest last
var day_reports: Array = []     # company-wide day summaries (last 30)
var flags := {}                 # one-off tutorial / notice flags
## City life (CityLife): today's weather, tomorrow's forecast, running
## events, the rival chain's stores and the news feed.
var weather := "sunny"
var forecast := "cloudy"
var events: Array = []
var rivals: Array = []
var firms: Array = []           # independent shops (CityLife firms)
var news: Array = []
## Your brand (ShopStyle.house): {name, primary, accent, face, sign}; {} = none.
var brand := {}
## Head office: {tier, paid, day}; {} = none (config hq.json).
var hq := {}
## Office companies (Offices) and the football club (Club).
var offices: Array = []
var club := {}
## The city's shop units (set by the game from Premises; not saved).
var market: Array = []

var rng := RandomNumberGenerator.new()
var _id_n := 0
var _hour_served := {}          # business id -> shoppers served this hour (offscreen queue capacity)
var _carry_minutes := 0.0


func new_game(p_seed := 1) -> void:
	seed = p_seed
	rng.seed = hash([seed, "empire"])
	var st: Dictionary = EmpireData.economy().get("start", {})
	day = int(st.get("day", 1))
	minute = float(st.get("hour", 7.5)) * 60.0
	personal_cash = float(st.get("personal_cash", 650.0))
	company_cash = float(st.get("company_cash", 0.0))
	stats = {"cases_bought": 0, "units_bought": 0, "units_sold": 0, "units_stolen": 0, "units_shelved": 0,
		"sales": 0, "revenue": 0.0, "profitable_days": 0, "upgrades": 0, "hires": 0, "km": 0.0,
		"spent_stock": 0.0, "days": 0, "rivals_bought": 0, "inspections_passed": 0, "best_day": 0.0, "firms_bought": 0,
		"campaigns": 0}
	candidates = Staff.candidates(day, seed)
	add_vehicle("hatch", Vector3.ZERO, 0.0)
	CityLife.start(self)
	Club.ensure(self)


# ----------------------------------------------------------------- time
func hour() -> float:
	return minute / 60.0


func clock_text() -> String:
	var m := int(minute)
	return "%02d:%02d" % [m / 60, m % 60]


func weekday() -> String:
	return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][(day - 1) % 7]


## Steps the world `minutes` game-minutes forward (fractions carry over).
func advance(minutes: float) -> void:
	_carry_minutes += minutes
	while _carry_minutes >= 1.0:
		_carry_minutes -= 1.0
		_minute_tick()
		minute += 1.0
		if minute >= 1440.0:
			minute -= 1440.0
			end_day()


func _minute_tick() -> void:
	var h := hour()
	var new_hour := int(minute) % 60 == 0
	if new_hour:
		_hour_served.clear()
	if int(minute) == 360:
		_deliver_orders()
	if int(minute) == 360 or int(minute) == 19 * 60 or int(minute) == 13 * 60:
		Ventures.deliver_imports(self)
	if int(minute) == 21 * 60 + 5:
		_manager_reorders()
	if int(minute) == 19 * 60:
		_deliver_orders()   # (same-day orders: your logistics firm)
	CityLife.minute(self)
	Club.minute(self)
	for b: Business in businesses:
		_staff_work(b, h)
		if b.trading(h):
			# Arrivals this minute: whole part + a random draw on the
			# fraction (mean exact, and they don't come like clockwork).
			var lam := DemandModel.arrivals_per_hour(b, h, competitors_near(b), CityLife.footfall_k(self, b)) / 60.0
			var n := int(lam) + (1 if rng.randf() < lam - floorf(lam) else 0)
			if b.live:
				b.pending_arrivals += n
			else:
				for i in n:
					visit_offscreen(b)
		if b.within_hours(h) and b.open:
			b.today["wages"] = float(b.today["wages"]) + b.wages_per_hour() / 60.0


# ------------------------------------------------------------- shoppers
## A shopper in a shop nobody is watching: browse, take, queue, pay.
func visit_offscreen(b: Business) -> void:
	var shopper := DemandModel.make_shopper(b, rng, CityLife.mix_k(self))
	var basket := Stock.new(0, "basket")
	b.today["customers"] = int(b.today["customers"]) + 1
	var mood := 0.0
	for pid in shopper["wants"]:
		mood += _browse(b, shopper, pid, basket)
	var imp := DemandModel.impulse_pick(b, shopper)
	if imp != "":
		b.unshelve(basket, b.slot_with(imp), 1)
	if basket.is_empty():
		b.add_rep(mood)
		return
	# The till: cashiers serve so many an hour; beyond that the queue backs up.
	var cap := 0.0
	for e in b.staff_with("cashier"):
		cap += Staff.serve_rate(e)
	cap = minf(cap, float(b.tills()) * Staff.serve_rate({"skill": 5, "traits": []}))
	var served := int(_hour_served.get(b.id, 0))  # (int(): JSON loads numbers as floats)
	if float(served) >= cap:
		put_back(b, basket)
		b.today["walked_out"] = int(b.today["walked_out"]) + 1
		b.add_rep(mood + EmpireData.rep_param("slow_queue"))
		return
	_hour_served[b.id] = served + 1
	checkout(b, basket, b.staff_with("cashier")[0] if b.has_role("cashier") else {})
	b.add_rep(mood + EmpireData.rep_param("visit_ok"))


## One wanted product at the shelf: takes it into the basket if bought.
## Returns the reputation change.
func _browse(b: Business, shopper: Dictionary, pid: String, basket: Stock) -> float:
	var r := DemandModel.decide(b, shopper, pid)
	match String(r["result"]):
		"buy":
			var left := int(r["qty"])
			while left > 0:
				var si := b.slot_with(pid)
				if si < 0:
					break
				left -= b.unshelve(basket, si, left)
			return 0.0
		"stockout":
			b.today["stockouts"] = int(b.today["stockouts"]) + 1
			return EmpireData.rep_param("stockout")
		"too_expensive":
			b.today["too_expensive"] = int(b.today["too_expensive"]) + 1
			# Only a real markup hurts the name: a shopper on a tight budget
			# at a fair price just doesn't buy.
			var fair := EmpireData.rrp(pid) * float(b.district().get("affluence", 1.0))
			var over := clampf((b.price(pid) / fair - 1.05) / 0.35, 0.0, 1.0)
			return EmpireData.rep_param("too_expensive") * over
		_:
			b.today["not_stocked"] = int(b.today["not_stocked"]) + 1
			return 0.0


## The live shop: a walking shopper reached a shelf (ShopFloor calls this).
func live_take(b: Business, shopper: Dictionary, pid: String, basket: Stock) -> String:
	var r := DemandModel.decide(b, shopper, pid)
	var mood := _browse(b, shopper, pid, basket)
	b.add_rep(mood)
	return String(r["result"])


## Basket goods go back on the shelves (a shopper gave up in the queue).
func put_back(b: Business, basket: Stock) -> void:
	for pid in basket.units.keys():
		var guard := 0
		while basket.qty(pid) > 0 and guard < 20:
			guard += 1
			var si := b.slot_for(pid)
			if si < 0 or b.shelve(basket, si, pid, basket.qty(pid)) == 0:
				# Shelves full/reassigned meanwhile: it goes to the back room.
				Stock.transfer(basket, b.backroom, pid, basket.qty(pid))
				if basket.qty(pid) > 0:
					b.backroom.case_capacity += 1  # (never lose goods: squeeze it in)
					Stock.transfer(basket, b.backroom, pid, basket.qty(pid))
				break


## Payment at the till. `server` is the cashier dict ({} = the owner).
func checkout(b: Business, basket: Stock, server := {}) -> float:
	var total := 0.0
	var cogs := 0.0
	var units := 0
	for pid in basket.units.keys():
		var n := basket.qty(pid)
		total += b.price(pid) * float(n)
		cogs += unit_cost(pid) * float(n)
		units += n
		var bp: Dictionary = b.today["by_product"]
		bp[pid] = int(bp.get(pid, 0)) + n
		basket.destroy(pid, n)
	if units == 0:
		return 0.0
	var fee := total * float(EmpireData.economy().get("card_fee", 0.015)) * 0.6 * (1.0 - Offices.fee_cut(self))
	company_cash += total - fee
	b.today["revenue"] = float(b.today["revenue"]) + total
	b.today["cogs"] = float(b.today["cogs"]) + cogs
	b.today["fees"] = float(b.today["fees"]) + fee
	b.today["units"] = int(b.today["units"]) + units
	b.today["served"] = int(b.today["served"]) + 1
	b.lifetime["revenue"] = float(b.lifetime.get("revenue", 0.0)) + total
	b.lifetime["customers"] = int(b.lifetime.get("customers", 0)) + 1
	stats["units_sold"] = int(stats["units_sold"]) + units
	stats["sales"] = int(stats["sales"]) + 1
	stats["revenue"] = float(stats["revenue"]) + total
	if "friendly" in server.get("traits", []):
		b.add_rep(float(EmpireData.trait_info("friendly").get("rep", 0.1)))
	sold.emit(b.id, total)
	if int(stats["sales"]) == 1:
		_note("First sale! %s" % EmpireData.money(total, true), "good")
	_check_goals()
	return total


func unit_cost(pid: String) -> float:
	return float(avg_cost.get(pid, EmpireData.unit_cost(pid)))


# ---------------------------------------------------------------- staff
func _staff_work(b: Business, h: float) -> void:
	if not b.within_hours(h) or not b.open:
		return
	for e: Dictionary in b.staff:
		if e.get("off", false):
			continue
		match String(e["role"]):
			"stocker":
				var budget := float(EmpireData.role("stocker").get("rate", 90)) * Staff.speed(e) / 60.0
				e["_acc"] = float(e.get("_acc", 0.0)) + budget
				var n := int(e["_acc"])
				if n > 0:
					e["_acc"] = float(e["_acc"]) - float(n)
					restock_from_backroom(b, n)
			"cleaner":
				b.cleanliness = minf(b.cleanliness + float(EmpireData.role("cleaner").get("rate", 0.3)) * Staff.speed(e) / 60.0, 1.0)
		if int(minute) % 60 == 0 and Staff.gain_xp(e, 1.0):
			_note("%s (%s) is now skill %d" % [e["name"], EmpireData.role(e["role"]).get("name", ""), e["skill"]], "good")


## Moves up to n units from the back room onto the shelves: anything in
## the back room that isn't on display gets an empty slot first, then the
## emptiest slots are topped up. Returns units moved.
func restock_from_backroom(b: Business, n: int) -> int:
	b.tidy_pile()
	var moved := 0
	var shown := b.stocked_products()
	for pid in b.backroom.units.keys():
		if moved >= n or shown.has(pid):
			continue
		var si := b.slot_for(pid)
		if si >= 0:
			moved += b.shelve(b.backroom, si, pid, mini(n - moved, 6))
			shown.append(pid)
	var guard := 0
	while moved < n and guard < 4096:
		guard += 1
		var best := -1
		var best_fill := 1.0
		for i in b.slots.size():
			var s: Dictionary = b.slots[i]
			var pid: String = s["product"]
			if pid == "" or b.backroom.qty(pid) <= 0:
				continue
			var fill := float(s["qty"]) / float(s["cap"])
			if fill < best_fill:
				best_fill = fill
				best = i
		var pid2 := ""
		if best >= 0:
			pid2 = b.slots[best]["product"]
		else:
			# Every slot showing something is full: spare empty slots take
			# whatever there's most of in the back that goes on them.
			for i in b.slots.size():
				var s2: Dictionary = b.slots[i]
				if String(s2["product"]) != "" or int(s2["qty"]) > 0:
					continue
				var most := 0
				for q in b.backroom.units:
					if b.can_hold(i, q) and b.backroom.qty(q) > most:
						most = b.backroom.qty(q)
						pid2 = q
				if pid2 != "":
					best = i
					break
		if best < 0:
			break
		var m := b.shelve(b.backroom, best, pid2, mini(n - moved, 6))
		if m <= 0:
			break
		moved += m
	stats["units_shelved"] = int(stats["units_shelved"]) + moved
	return moved


## Today's job seekers: more, and better, with your recruitment agency.
func fresh_candidates() -> Array:
	var rec := Offices.recruitment(self)
	var cs := Staff.candidates(day, seed, Staff.daily_count() + int(rec[0]))
	if int(rec[1]) > 0:
		for c in cs:
			c["skill"] = mini(int(c["skill"]) + int(rec[1]), 5)
			c["wage"] = Staff.wage_for(c)
	return cs


## Today's best job seeker for a role: most skilled, then cheapest (the
## careless only if there's no one else). {} if nobody.
func best_candidate(role: String) -> Dictionary:
	var best := {}
	var best_v := -INF
	for c: Dictionary in candidates:
		if c["role"] != role:
			continue
		var v := float(c["skill"]) * 10.0 - float(c["wage"]) - (15.0 if (c.get("traits", []) as Array).has("careless") else 0.0)
		if v > best_v:
			best_v = v
			best = c
	return best


func hire(b: Business, cand: Dictionary) -> bool:
	if not candidates.has(cand):
		return false
	candidates.erase(cand)
	var e := cand.duplicate(true)
	e["hired_day"] = day
	e["business"] = b.id
	b.staff.append(e)
	stats["hires"] = int(stats["hires"]) + 1
	_note("Hired %s as %s at %s" % [e["name"], EmpireData.role(e["role"]).get("name", ""), b.name], "good", {"kind": "biz", "id": b.id, "tab": "staff"})
	_check_goals()
	changed.emit()
	return true


func fire(b: Business, e: Dictionary) -> void:
	for x in b.staff.duplicate():
		if x["id"] == e["id"]:
			b.staff.erase(x)
	# A day's notice pay (in the shop's day, so its profit shows it).
	var pay := float(e["wage"]) * 8.0
	company_cash -= pay
	b.today["other"] = float(b.today.get("other", 0.0)) + pay
	_book("company", -pay, "wages", "Notice pay: %s" % e["name"], b.id)
	changed.emit()


# --------------------------------------------------------------- money
## Pays from the company account first and any shortfall from personal
## savings (the owner putting money in). false = can't afford it (nothing paid).
func pay(amount: float, cat: String, memo: String, biz := "") -> bool:
	if amount <= 0.0:
		return true
	if not can_afford(amount):
		return false
	var from_co := clampf(company_cash, 0.0, amount)
	var from_me := amount - from_co
	if from_co > 0.0:
		company_cash -= from_co
		_book("company", -from_co, cat, memo, biz)
	if from_me > 0.0:
		personal_cash -= from_me
		_book("personal", -from_me, cat, memo, biz)
	changed.emit()
	return true


func can_afford(amount: float) -> bool:
	return maxf(company_cash, 0.0) + maxf(personal_cash, 0.0) >= amount - 0.0001


func transfer_to_company(amount: float) -> bool:
	if amount <= 0.0 or personal_cash < amount:
		return false
	personal_cash -= amount
	company_cash += amount
	_book("personal", -amount, "transfer", "Into the company")
	_book("company", amount, "transfer", "From your savings")
	changed.emit()
	return true


func draw_from_company(amount: float) -> bool:
	if amount <= 0.0 or company_cash < amount:
		return false
	company_cash -= amount
	personal_cash += amount
	_book("company", -amount, "transfer", "Owner's draw")
	_book("personal", amount, "transfer", "From the company")
	changed.emit()
	return true


func _book(acct: String, amount: float, cat: String, memo: String, biz := "") -> void:
	ledger.append({"day": day, "min": int(minute), "acct": acct, "amount": snappedf(amount, 0.01), "cat": cat,
		"memo": memo, "biz": biz})
	if ledger.size() > 300:
		ledger = ledger.slice(ledger.size() - 300)


## A notification. `ref` says what it's about ({kind: biz|unit|vehicle|tab,
## id, tab}) so tapping it opens that (EmpireUI.open_ref); read it from
## last_ref while `notified` is being handled.
var last_ref := {}


func _note(text: String, kind := "info", ref := {}) -> void:
	log.append({"day": day, "min": int(minute), "text": text, "kind": kind, "ref": ref})
	if log.size() > 80:
		log = log.slice(log.size() - 80)
	last_ref = ref
	notified.emit(text, kind)
	last_ref = {}


# ----------------------------------------------------------- wholesale
## Buys `order` ({pid: cases}) at a wholesaler; the goods wait on its
## collection bay (pallet). Returns "" or an error.
func buy_wholesale(wholesaler: String, order: Dictionary, price_k := 1.0) -> String:
	var cost := 0.0
	for pid in order:
		cost += case_price(pid) * float(order[pid]) * price_k
	if cost <= 0.0:
		return "Nothing in the basket"
	if not pay(cost, "stock", "Wholesale: %d lines" % order.size()):
		return "Not enough money (%s)" % EmpireData.money(cost, true)
	var pal: Stock = pallets.get(wholesaler, null)
	if pal == null:
		pal = Stock.new(0, "pallet")
		pallets[wholesaler] = pal
	for pid in order:
		var units := int(order[pid]) * EmpireData.case_qty(pid)
		_receive(pal, pid, units, case_price(pid) * price_k / EmpireData.case_qty(pid))
		stats["cases_bought"] = int(stats["cases_bought"]) + int(order[pid])
	stats["spent_stock"] = float(stats["spent_stock"]) + cost
	_check_goals()
	changed.emit()
	return ""


## Today's wholesale price of one case (deals and shortages from CityLife).
func case_price(pid: String) -> float:
	return float(EmpireData.product(pid).get("case_cost", 0.0)) * CityLife.price_k(self, pid) * hq_wholesale_k()


## Goods entering the economy at `unit_price`: updates the average cost.
func _receive(dst: Stock, pid: String, units: int, unit_price: float) -> void:
	var held := total_units_of(pid)
	var old := unit_cost(pid)
	avg_cost[pid] = (old * float(held) + unit_price * float(units)) / float(maxi(held + units, 1))
	dst.create(pid, units)
	stats["units_bought"] = int(stats["units_bought"]) + units


## Every unit of pid anywhere in the empire.
func total_units_of(pid: String) -> int:
	var n := carried.qty(pid)
	for w in pallets:
		n += (pallets[w] as Stock).qty(pid)
	for v in vehicles:
		n += (v["cargo"] as Stock).qty(pid)
	for b: Business in businesses:
		n += b.backroom.qty(pid) + b.shelf_qty(pid) + b.floor_pile.qty(pid)
	return n


func total_units() -> int:
	var n := 0
	for pid in EmpireData.product_ids():
		n += total_units_of(pid)
	return n


func stock_value() -> float:
	var v := 0.0
	for pid in EmpireData.product_ids():
		v += float(total_units_of(pid)) * unit_cost(pid)
	return v


## Phone order for next-morning delivery to a shop's back room.
func order_delivery(b: Business, order: Dictionary, by_manager := false) -> String:
	var cost := 0.0
	var units := {}
	for pid in order:
		var c := int(order[pid])
		if c <= 0:
			continue
		cost += case_price(pid) * float(c)
		units[pid] = c * EmpireData.case_qty(pid)
	if units.is_empty():
		return "Nothing to order"
	var fee := delivery_fee(b)
	if not pay(cost + fee, "stock", "Delivery order%s" % (" (manager)" if by_manager else ""), b.id):
		return "Not enough money (%s)" % EmpireData.money(cost + fee, true)
	var unit_prices := {}
	for pid in units:
		unit_prices[pid] = case_price(pid) / EmpireData.case_qty(pid)
	var due := day + (1 if minute >= 360.0 else 0)
	if Offices.same_day(self) and minute < 18.0 * 60.0:
		due = day   # your logistics firm brings it this evening (19:00)
	b.orders.append({"units": units, "cost": cost, "fee": fee, "due": due, "unit_prices": unit_prices})
	stats["spent_stock"] = float(stats["spent_stock"]) + cost
	b.today["fees"] = float(b.today["fees"]) + fee
	changed.emit()
	return ""


## One-tap stock: the cases that fill b's shelves (`full`: and put a
## shelf's worth of each line in the stockroom as well, while it has room).
## Counts what's already there, on order, on the floor and `in_transit`
## ({pid: units}, e.g. in your van). Cases are taken a round at a time over
## the range (most wanted first), so a smaller `max_cases` or `budget` still
## gives a spread of everything rather than lots of one thing.
## Returns {"cases": {pid: n}, "count": n, "cost": £, "short": "why it stopped early" or ""}.
func restock_plan(b: Business, full := false, max_cases := 9999, budget := INF, in_transit := {}) -> Dictionary:
	var targets := b.shelf_targets()
	var order: Array = b.sellable().filter(func(p): return targets.has(p))
	var pending := {}
	for o: Dictionary in b.orders:
		for pid in o["units"]:
			pending[pid] = int(pending.get(pid, 0)) + int(o["units"][pid])
	var need := {}   # pid -> [cases for the shelves, extra cases for the stockroom]
	var spare_room := b.backroom.case_capacity - b.backroom.cases_used() - b.floor_pile.cases_used()
	for pid in order:
		var cq := EmpireData.case_qty(pid)
		var have := b.shelf_qty(pid) + b.backroom.qty(pid) + b.floor_pile.qty(pid) + int(pending.get(pid, 0)) + int(in_transit.get(pid, 0))
		var shelf_cases := int(ceil(float(maxi(int(targets[pid]) - have, 0)) / float(cq)))
		# What's left over from those cases waits in the stockroom too.
		var left := shelf_cases * cq + have - int(targets[pid])
		var extra := 0
		if full:
			extra = maxi(int(ceil(float(int(targets[pid]) - maxi(left, 0)) / float(cq))), 0)
		need[pid] = [shelf_cases, extra]
		spare_room -= int(ceil(float(maxi(left, 0)) / float(cq)))
	# Rounds: one case of each line that still needs one, shelves first.
	var tickets: Array = []
	for phase in 2:
		var more := true
		while more:
			more = false
			for pid in order:
				if int(need[pid][phase]) > 0:
					if phase == 1:
						if spare_room <= 0:
							continue
						spare_room -= 1
					need[pid][phase] = int(need[pid][phase]) - 1
					tickets.append(pid)
					more = true
	var cases := {}
	var count := 0
	var cost := 0.0
	var short := ""
	for pid in tickets:
		if count >= max_cases:
			short = "space"
			break
		var c := case_price(pid)
		if cost + c > budget:
			short = "money"
			continue
		cases[pid] = int(cases.get(pid, 0)) + 1
		count += 1
		cost += c
	return {"cases": cases, "count": count, "cost": cost, "short": short}


## A driver with a company van collects for free; otherwise the wholesaler delivers for a fee.
func delivery_fee(b: Business) -> float:
	if Offices.free_delivery(self):
		return 0.0
	if b.has_role("driver") and vehicles.any(func(v): return v["model"] in ["van", "box"]):
		return 0.0
	return float(EmpireData.economy().get("wholesale_delivery_fee", 35.0))


func _deliver_orders() -> void:
	for b: Business in businesses:
		var keep: Array = []
		for o: Dictionary in b.orders:
			if int(o["due"]) <= day:
				var u: Dictionary = o["units"]
				for pid in u:
					var units := int(u[pid])
					var room := b.backroom.room_for(pid)
					if room < units:
						b.backroom.case_capacity += Stock.cases_for(pid, units - room)  # stacked in the aisle
					var cost := float(o.get("unit_prices", {}).get(pid, EmpireData.unit_cost(pid)))
					_receive(b.backroom, pid, units, cost)
				_note("Delivery arrived at %s" % b.name, "info", {"kind": "biz", "id": b.id, "tab": "stock"})
			else:
				keep.append(o)
		b.orders = keep
		# Overflow from deliveries settles back to the racking size overnight.
		var base := int(b.type_def().get("backroom_cases", 20))
		if b.has_upgrade("backroom"):
			base += int(EmpireData.upgrade("backroom").get("backroom", 0))
		b.backroom.case_capacity = maxi(base, b.backroom.cases_used())


## Managers top up for tomorrow: anything on sale with under half a
## day's shelf-fill in total gets cases ordered (company money only).
func _manager_reorders() -> void:
	for b: Business in businesses:
		if not b.has_role("manager"):
			continue
		# Any line short of a shelf-fill gets two shelf-fills' worth (deliveries
		# stack in the aisle when the racking's full); company money only.
		var order := {}
		var budget := company_cash - 200.0
		var targets := b.shelf_targets()
		for pid in b.sellable():
			if not targets.has(pid):
				continue
			var cap := int(targets[pid])
			var pending := 0
			for o: Dictionary in b.orders:
				pending += int(o["units"].get(pid, 0))
			var have := b.shelf_qty(pid) + b.backroom.qty(pid) + pending
			if have < cap:
				var cases := int(ceil(float(cap * 2 - have) / float(EmpireData.case_qty(pid))))
				var room := b.backroom.room_for(pid) / maxi(EmpireData.case_qty(pid), 1)
				cases = mini(cases, maxi(room, 1))
				var c := case_price(pid) * cases
				if c <= budget and cases > 0:
					order[pid] = cases
					budget -= c
		if not order.is_empty():
			var err := order_delivery(b, order, true)
			if err == "":
				_note("%s: manager ordered %d lines for the morning" % [b.name, order.size()], "info", {"kind": "biz", "id": b.id, "tab": "stock"})
			else:
				_note("%s: manager couldn't re-order – %s" % [b.name, err], "warn", {"kind": "tab", "id": "bank"})


# ------------------------------------------------------------ premises
func new_id(prefix: String) -> String:
	_id_n += 1
	return "%s%d" % [prefix, _id_n]


func business(id: String) -> Business:
	for b: Business in businesses:
		if b.id == id:
			return b
	return null


func business_at(premises_id: String) -> Business:
	for b: Business in businesses:
		if b.premises.get("id", "") == premises_id:
			return b
	return null


## Rent: three days up front as a deposit (kept) + the daily rent from then on.
func rent_premises(premises: Dictionary, type_id := "convenience") -> Business:
	if business_at(premises.get("id", "")) != null or CityLife.is_taken(self, premises.get("id", "")):
		return null
	var deposit := float(premises.get("rent", 0.0)) * 3.0
	if not pay(deposit, "rent", "Deposit: %s" % premises.get("name", "")):
		return null
	var b := _open_business(premises, type_id)
	_note("You rented %s. Stock it up and open!" % b.name, "good", {"kind": "biz", "id": b.id, "tab": "stock"})
	return b


func buy_premises(premises: Dictionary, type_id := "convenience") -> Business:
	var existing := business_at(premises.get("id", ""))
	var price := float(premises.get("price", 0.0))
	if CityLife.is_taken(self, premises.get("id", "")):
		return null
	if existing and existing.owned:
		return null
	if not pay(price, "property", "Bought %s" % premises.get("name", "")):
		return null
	if existing:
		existing.owned = true
		_note("You now own the freehold of %s: no more rent." % existing.name, "good")
		_check_goals()
		return existing
	var b := _open_business(premises, type_id)
	b.owned = true
	_note("You bought %s." % b.name, "good", {"kind": "biz", "id": b.id, "tab": "overview"})
	_check_goals()
	return b


func _open_business(premises: Dictionary, type_id: String) -> Business:
	var b := Business.new(new_id("b"), type_id)
	b.setup_new(premises, day)
	businesses.append(b)
	_check_goals()
	changed.emit()
	return b


## Closing a business for good (quality audit 2026-11-18: there was no way
## out of a losing shop – a bad location's rent, utilities and hangar-like
## costs ran every day forever). What it settles, as {cash, stock, orders,
## freehold}: the goods in it go to a clearance trader at half their cost;
## orders on their way are cancelled and the goods refunded (delivery fees
## and import freight are not); staff get their notice pay (fire); a
## freehold is sold at 90% of the price (agent and legal fees); a lease
## simply ends (the deposit stays with the landlord).
const CLEARANCE_K := 0.5
const FREEHOLD_SALE_K := 0.9


func close_value(b: Business) -> Dictionary:
	var stock := 0.0
	for pid in EmpireData.product_ids():
		stock += float(b.backroom.qty(pid) + b.shelf_qty(pid) + b.floor_pile.qty(pid)) * unit_cost(pid) * CLEARANCE_K
	var orders := 0.0
	for o: Dictionary in b.orders:
		orders += float(o.get("cost", 0.0))
	for o: Dictionary in flags.get("imports", []):
		if String(o.get("biz", "")) == b.id:
			for pid in o["lines"]:
				orders += float(EmpireData.product(pid).get("case_cost", 0.0)) * float(o["lines"][pid])
	var free := float(b.premises.get("price", 0.0)) * FREEHOLD_SALE_K if b.owned else 0.0
	var notice := 0.0
	for s in b.staff:
		notice += float(s["wage"]) * 8.0
	return {"stock": stock, "orders": orders, "freehold": free, "notice": notice,
		"cash": stock + orders + free - notice}


func close_business(b: Business) -> Dictionary:
	if not b in businesses:
		return {}
	var v := close_value(b)
	for s in b.staff.duplicate():
		fire(b, s)
	var back := float(v["stock"]) + float(v["orders"]) + float(v["freehold"])
	company_cash += back
	if back > 0.0:
		_book("company", back, "property" if b.owned else "sales",
			"%s: %s" % [b.name, "sold (freehold, stock, cancelled orders)" if b.owned else "closed (stock cleared, cancelled orders)"], b.id)
	flags["imports"] = (flags.get("imports", []) as Array).filter(func(o): return String(o.get("biz", "")) != b.id)
	businesses.erase(b)
	stats["closed"] = int(stats.get("closed", 0)) + 1
	_note("%s is closed for good: %s back after notice pay" % [b.name, EmpireData.money(float(v["cash"]))], "info")
	changed.emit()
	return v


func buy_upgrade(b: Business, u: String) -> String:
	if b.has_upgrade(u) or not u in b.type_def().get("upgrades", []):
		return "Not available"
	var cost := float(EmpireData.upgrade(u).get("cost", 0.0))
	if not pay(cost, "upgrade", "%s: %s" % [b.name, EmpireData.upgrade(u).get("name", u)], b.id):
		return "Not enough money (%s)" % EmpireData.money(cost)
	b.apply_upgrade(u)
	stats["upgrades"] = int(stats["upgrades"]) + 1
	_note("%s fitted at %s" % [EmpireData.upgrade(u).get("name", u), b.name], "good")
	_check_goals()
	changed.emit()
	return ""


## Nearby shops compete for the same shoppers (premises "pos"): yours and
## QuikSave count 1 each, the independents a fraction (CityLife.firms_near).
func competitors_near(b: Business) -> float:
	var p = b.premises.get("pos", null)
	if not p is Array or (p as Array).size() < 3:
		return 0.0
	var me := Vector3(p[0], p[1], p[2])
	var r := float(EmpireData.economy().get("competition_radius", 140.0))
	var n := float(b.premises.get("rivals", 0)) + float(CityLife.rivals_near(self, b)) + CityLife.firms_near(self, b)
	for o: Business in businesses:
		if o == b:
			continue
		var q = o.premises.get("pos", null)
		if q is Array and (q as Array).size() >= 3 and Vector3(q[0], q[1], q[2]).distance_to(me) < r:
			n += 1.0
	return n


# ------------------------------------------------------------ vehicles
func add_vehicle(model: String, pos: Vector3, yaw: float) -> Dictionary:
	var m := EmpireData.vehicle_model(model)
	var v := {"id": new_id("v"), "model": model, "cargo": Stock.new(int(m.get("cargo", 8)), "cargo"),
		"condition": 1.0, "km": 0.0, "pos": [pos.x, pos.y, pos.z], "yaw": yaw}
	vehicles.append(v)
	changed.emit()
	return v


func buy_vehicle(model: String, pos: Vector3, yaw: float) -> Dictionary:
	var price := float(EmpireData.vehicle_model(model).get("price", 0.0))
	if not pay(price, "vehicle", "Bought a %s" % EmpireData.vehicle_model(model).get("name", model)):
		return {}
	var v := add_vehicle(model, pos, yaw)
	_note("New %s! It's parked outside." % EmpireData.vehicle_model(model).get("name", model), "good")
	_check_goals()
	return v


func vehicle(id: String) -> Dictionary:
	for v in vehicles:
		if v["id"] == id:
			return v
	return {}


## Driving costs fuel and wears the vehicle (km since the last call).
func drive(v: Dictionary, km: float) -> void:
	if km <= 0.0 or v.get("test", false):
		return
	v["km"] = float(v["km"]) + km
	stats["km"] = float(stats["km"]) + km
	v["condition"] = maxf(float(v["condition"]) - km * float(EmpireData.file("vehicles").get("wear_per_km", 0.004)), 0.0)
	var fuel := km * float(EmpireData.economy().get("fuel_per_km", 0.2))
	v["_fuel"] = float(v.get("_fuel", 0.0)) + fuel
	if float(v["_fuel"]) >= 5.0:  # filled up in £5 lots
		var f := float(v["_fuel"])
		v["_fuel"] = 0.0
		if not pay(f, "fuel", "Fuel"):
			company_cash -= f
			_book("company", -f, "fuel", "Fuel (overdraft)")


func service_vehicle(v: Dictionary) -> String:
	var cost := float(EmpireData.file("vehicles").get("service_cost", 80.0)) * (1.5 - float(v["condition"]) * 0.5)
	if not pay(cost, "vehicle", "Service"):
		return "Not enough money"
	v["condition"] = 1.0
	return ""


# --------------------------------------------------------------- loans
func loan_limit() -> float:
	var l: Dictionary = EmpireData.economy().get("loan", {})
	var owed := 0.0
	for x in loans:
		owed += float(x["principal"])
	return maxf(maxf(float(l.get("min_offer", 1500)), net_worth() * float(l.get("max_factor", 0.8))) - owed, 0.0)


func take_loan(amount: float) -> bool:
	if amount <= 0.0 or amount > loan_limit() + 0.01:
		return false
	var l: Dictionary = EmpireData.economy().get("loan", {})
	loans.append({"id": new_id("l"), "principal": amount, "rate": float(l.get("daily_rate", 0.004)), "day": day,
		"due": day + int(l.get("term_days", 30))})
	company_cash += amount
	_book("company", amount, "loan", "Bank loan")
	_note("Loan of %s paid into the company account" % EmpireData.money(amount), "info")
	changed.emit()
	return true


func repay_loan(loan: Dictionary, amount: float) -> bool:
	amount = minf(amount, float(loan["principal"]))
	if amount <= 0.0 or not pay(amount, "loan", "Loan repayment"):
		return false
	loan["principal"] = float(loan["principal"]) - amount
	if float(loan["principal"]) <= 0.01:
		loans.erase(loan)
		_note("Loan repaid in full", "good")
	changed.emit()
	return true


# ------------------------------------------------------------ property
func buy_property(p: Dictionary) -> bool:
	for q in properties:
		if q["id"] == p["id"]:
			return false
	if not pay(float(p.get("price", 0.0)), "property", "Bought %s" % p.get("name", "")):
		return false
	var rec := p.duplicate(true)
	rec["let"] = false
	properties.append(rec)
	_note("You bought %s" % p.get("name", "a property"), "good")
	_check_goals()
	changed.emit()
	return true


func owns_property(id: String) -> bool:
	return properties.any(func(q): return q["id"] == id)


## Letting a home out: rent comes in every day (≈ 0.45% of its price).
func set_let(id: String, let: bool) -> void:
	for q in properties:
		if q["id"] == id:
			q["let"] = let


# ---------------------------------------------------------------- day
func end_day() -> void:
	var report := {"day": day, "businesses": [], "revenue": 0.0, "profit": 0.0, "personal": 0.0}
	for b: Business in businesses:
		b.tidy_pile()  # (cases left on the floor go into the stockroom overnight)
		var t := b.today
		# Shrinkage: a share of the shelf stock walks out (less with CCTV).
		var stolen := 0
		var stolen_cost := 0.0
		for s: Dictionary in b.slots:
			if s["product"] == "" or int(s["qty"]) == 0:
				continue
			var lose := 0
			var expect := float(s["qty"]) * b.theft_rate() * (0.5 + 0.5 * float(int(t["customers"]) > 0))
			lose = int(expect) + (1 if rng.randf() < expect - floorf(expect) else 0)
			lose = mini(lose, int(s["qty"]))
			if lose > 0:
				s["qty"] = int(s["qty"]) - lose
				stolen += lose
				stolen_cost += unit_cost(s["product"]) * lose
		stats["units_stolen"] = int(stats["units_stolen"]) + stolen
		t["stolen"] = stolen
		t["stolen_cost"] = stolen_cost
		t["rent"] = b.rent_per_day() * (1.0 - Offices.rent_discount(self))
		t["utilities"] = b.utilities_per_day() if b.open else b.utilities_per_day() * 0.3
		var costs := float(t["wages"]) + float(t["rent"]) + float(t["utilities"])
		company_cash -= costs
		_book("company", -float(t["wages"]), "wages", "Wages: %s" % b.name, b.id)
		_book("company", -float(t["rent"]), "rent", "Rent: %s" % b.name, b.id)
		_book("company", -float(t["utilities"]), "utilities", "Utilities: %s" % b.name, b.id)
		var gross := float(t["revenue"]) - float(t["cogs"])
		var other := float(t.get("other", 0.0))
		var profit := gross - costs - float(t["fees"]) - stolen_cost - other
		var rep := {"day": day, "biz": b.id, "name": b.name, "revenue": t["revenue"], "cogs": t["cogs"],
			"gross": gross, "wages": t["wages"], "rent": t["rent"], "utilities": t["utilities"], "fees": t["fees"],
			"theft": stolen_cost, "other": other, "profit": profit, "customers": t["customers"], "served": t["served"],
			"stockouts": t["stockouts"], "not_stocked": t["not_stocked"], "too_expensive": t["too_expensive"],
			"walked_out": t["walked_out"], "reputation": b.reputation, "units": t["units"],
			"top": _top_products(t["by_product"])}
		b.history.append(rep)
		if b.history.size() > 14:
			b.history = b.history.slice(b.history.size() - 14)
		b.lifetime["profit"] = float(b.lifetime.get("profit", 0.0)) + profit
		report["businesses"].append(rep)
		report["revenue"] = float(report["revenue"]) + float(t["revenue"])
		report["profit"] = float(report["profit"]) + profit
		# Reputation drifts back toward the middle; dirt builds overnight a little.
		var mid := EmpireData.rep_param("daily_decay_to")
		b.reputation = lerpf(b.reputation, mid, EmpireData.rep_param("daily_decay"))
		b.reset_today()
	# Office companies and the club settle their own days.
	var op := Offices.settle(self)
	var cp := Club.settle(self)
	report["offices"] = op
	report["club"] = cp
	report["profit"] = float(report["profit"]) + op + cp
	# Personal side: loans, let properties.
	for l in loans:
		var interest := float(l["principal"]) * float(l["rate"])
		company_cash -= interest
		_book("company", -interest, "interest", "Loan interest")
		report["profit"] = float(report["profit"]) - interest
		if day >= int(l["due"]) and not flags.has("due_" + String(l["id"])):
			flags["due_" + String(l["id"])] = true
			_note("A loan is past its term: repay it from Finances when you can", "warn", {"kind": "tab", "id": "bank"})
	for q in properties:
		if q.get("let", false):
			var inc := float(q.get("price", 0.0)) * 0.0045
			personal_cash += inc
			_book("personal", inc, "rent_in", "Tenant rent: %s" % q.get("name", ""))
			report["personal"] = float(report["personal"]) + inc
	# Skyport ventures: rents, upkeep, the dealership, hangar/marina fees
	# (part of the day's profit like any other business).
	var vt := Ventures.end_day(self)
	report["ventures"] = vt
	report["profit"] = float(report["profit"]) + float(vt["rent"]) - float(vt["upkeep"]) + float(vt["dealer"]) - float(vt["fees"])
	if hq_tier() > 0:
		var up := float(hq_def(hq_tier()).get("upkeep", 0.0))
		company_cash -= up
		_book("company", -up, "rent", "Head office upkeep")
		report["profit"] = float(report["profit"]) - up
	if company_cash < 0.0:
		var od := -company_cash * 0.01
		company_cash -= od
		_book("company", -od, "interest", "Overdraft interest")
		_note("Company account overdrawn: %s. Move savings in or take a loan." % EmpireData.money(company_cash), "bad", {"kind": "tab", "id": "bank"})
	if not businesses.is_empty() and float(report["profit"]) > 0.0:
		stats["profitable_days"] = int(stats["profitable_days"]) + 1
	stats["days"] = int(stats["days"]) + 1
	if float(report["profit"]) > float(stats.get("best_day", 0.0)):
		stats["best_day"] = float(report["profit"])
	day_reports.append({"day": day, "revenue": report["revenue"], "profit": report["profit"],
		"company": company_cash, "personal": personal_cash, "net_worth": net_worth()})
	if day_reports.size() > 30:
		day_reports = day_reports.slice(day_reports.size() - 30)
	day += 1
	candidates = fresh_candidates()
	report["weather"] = weather
	CityLife.new_day(self)
	report["tomorrow"] = weather
	_check_goals()
	day_ended.emit(report)
	changed.emit()


static func _top_products(bp: Dictionary) -> Array:
	var ks := bp.keys()
	ks.sort_custom(func(a, b): return int(bp[a]) > int(bp[b]))
	return ks.slice(0, 3)


# -------------------------------------------------------------- worth
func premises_value() -> float:
	var v := 0.0
	for b: Business in businesses:
		if b.owned:
			v += float(b.premises.get("price", 0.0))
	return v


func vehicles_value() -> float:
	var v := 0.0
	for x in vehicles:
		v += vehicle_value(x)
	return v


## What a trader pays for a vehicle (and what it counts for in net worth).
func vehicle_value(x: Dictionary) -> float:
	if x.get("test", false):
		return 0.0
	return float(EmpireData.vehicle_model(x["model"]).get("price", 0.0)) * 0.6 * (0.5 + 0.5 * float(x["condition"]))


## Why a vehicle can't be sold now ("" = it can). (Aircraft and boats kept
## costing hangar/marina fees every day with no way to part with them.)
func sell_vehicle_block(x: Dictionary) -> String:
	if x.is_empty() or x.get("test", false):
		return "Not yours to sell"
	if not (x["cargo"] as Stock).is_empty():
		return "Unload its cargo first"
	if vehicle_value(x) <= 0.0:
		return "No trader would pay for it"
	return ""


func sell_vehicle(x: Dictionary) -> float:
	if sell_vehicle_block(x) != "":
		return -1.0
	var val := vehicle_value(x)
	vehicles.erase(x)
	company_cash += val
	_book("company", val, "vehicle", "Sold the %s" % EmpireData.vehicle_model(x["model"]).get("name", x["model"]))
	changed.emit()
	return val


func net_worth() -> float:
	var debt := 0.0
	for l in loans:
		debt += float(l["principal"])
	var props := 0.0
	for q in properties:
		props += float(q.get("price", 0.0))
	return personal_cash + company_cash + stock_value() + premises_value() + vehicles_value() + props \
		+ float(hq.get("paid", 0.0)) + Club.value(self) + Ventures.assets_value(self) - debt


# -------------------------------------------------------------- career
func stat(key: String) -> float:
	match key:
		"businesses":
			return float(businesses.size())
		"staff":
			var n := 0
			for b: Business in businesses:
				n += b.staff.size()
			return float(n)
		"managers":
			return float(businesses.filter(func(b): return b.has_role("manager")).size())
		"vans":
			return float(vehicles.filter(func(v): return v["model"] in ["van", "box"]).size())
		"east_businesses":
			return float(businesses.filter(func(b): return b.island() == "east").size())
		"properties":
			return float(properties.size() + businesses.filter(func(b): return b.owned).size())
		"net_worth":
			return net_worth()
		"rival_gone":
			return 1.0 if flags.get("rival_gone", false) else 0.0
		"hq_tier":
			return float(hq_tier())
		"offices":
			return float(offices.size())
		"office_desks":
			var n2 := 0
			for o in offices:
				n2 += int(o["desks"])
			return float(n2)
		"club_owned":
			return 1.0 if club.get("owned", false) else 0.0
		"trophies":
			return float(club.get("trophies", 0))
		"branded":
			return 1.0 if String(brand.get("name", "")) != "" else 0.0
		"owned_both":
			var w := businesses.any(func(b): return b.owned and b.island() == "west")
			var e := businesses.any(func(b): return b.owned and b.island() == "east")
			return 1.0 if w and e else 0.0
	return float(stats.get(key, 0.0))


func _check_goals() -> void:
	for ch in EmpireData.chapters():
		for g in ch["goals"]:
			if goals_done.has(g["id"]):
				continue
			if stat(g["stat"]) >= float(g["value"]):
				goals_done.append(g["id"])
				_note("Goal complete: %s" % g["text"], "good", {"kind": "tab", "id": "goals"})
				goal_done.emit(g)
	if not flags.get("won", false) and all_goals_done():
		flags["won"] = true
		flags["won_day"] = day
		won.emit()


func all_goals_done() -> bool:
	for ch in EmpireData.chapters():
		for g in ch["goals"]:
			if not goals_done.has(g["id"]):
				return false
	return true


## The chapter you're in and its next open goals (for the HUD objective).
func current_goals(n := 3) -> Array:
	for ch in EmpireData.chapters():
		var open: Array = []
		for g in ch["goals"]:
			if not goals_done.has(g["id"]):
				open.append(g)
		if not open.is_empty():
			return [ch["name"], open.slice(0, n)]
	return ["Tycoon", []]


# ---------------------------------------------------------------- save
# -------------------------------------------------- brand & head office
## What a rebrand costs now (new signs on every shop; the first one's free
## before you have a shop).
func rebrand_cost() -> float:
	return float(EmpireData.hq().get("rebrand_per_shop", 400)) * businesses.size()


## Sets your brand (see ShopStyle.house_ident). "" = done.
func set_brand(b: Dictionary) -> String:
	var nm := String(b.get("name", "")).strip_edges()
	if nm.length() < 2:
		return "Give your company a name"
	if nm.length() > 22:
		return "Keep the name to 22 letters"
	var cost := rebrand_cost() if String(brand.get("name", "")) != "" else 0.0
	if cost > 0.0 and not pay(cost, "other", "New signs: %s" % nm):
		return "New signs cost %s" % EmpireData.money(cost)
	brand = b.duplicate()
	brand["name"] = nm
	_note("Your shops now trade as %s." % nm, "good")
	_check_goals()
	changed.emit()
	return ""


func hq_tier() -> int:
	return int(hq.get("tier", 0))


func hq_def(tier: int) -> Dictionary:
	var ts: Array = EmpireData.hq().get("tiers", [])
	return ts[tier - 1] if tier >= 1 and tier <= ts.size() else {}


## Why the next head-office tier can't be bought ("" = it can).
func hq_block(tier: int) -> String:
	var d := hq_def(tier)
	if d.is_empty():
		return "Nothing bigger"
	if tier != hq_tier() + 1:
		return "Take the floors below first"
	if businesses.size() < int(d.get("shops", 0)):
		return "Needs %d shops (you have %d)" % [int(d["shops"]), businesses.size()]
	if not can_afford(float(d["price"])):
		return "Costs %s" % EmpireData.money(float(d["price"]))
	return ""


func buy_hq(tier: int) -> String:
	var why := hq_block(tier)
	if why != "":
		return why
	var d := hq_def(tier)
	if not pay(float(d["price"]), "property", "Head office: %s" % d["name"]):
		return "Not enough money"
	hq = {"tier": tier, "paid": float(hq.get("paid", 0.0)) + float(d["price"]), "day": day}
	_note("Head office: %s." % d["name"], "good")
	_check_goals()
	changed.emit()
	return ""


func hq_wholesale_k() -> float:
	return 1.0 - float(hq_def(hq_tier()).get("wholesale", 0.0))


func hq_footfall_k() -> float:
	return 1.0 + float(hq_def(hq_tier()).get("footfall", 0.0))


func campaign_def(id: String) -> Dictionary:
	for c in EmpireData.hq().get("campaigns", []):
		if c["id"] == id:
			return c
	return {}


## A campaign running now (its event), or {}.
func campaign_running() -> Dictionary:
	for ev in events:
		if ev.get("kind") == "campaign":
			return ev
	return {}


func campaign_block(id: String) -> String:
	var c := campaign_def(id)
	if c.is_empty():
		return "?"
	if hq_tier() < int(c.get("tier", 1)):
		return "Needs %s" % String(hq_def(int(c.get("tier", 1))).get("name", "a head office"))
	if businesses.is_empty():
		return "No shops to advertise"
	if not campaign_running().is_empty():
		return "A campaign is running"
	if not can_afford(float(c["cost"])):
		return "Costs %s" % EmpireData.money(float(c["cost"]))
	return ""


func run_campaign(id: String) -> String:
	var why := campaign_block(id)
	if why != "":
		return why
	var c := campaign_def(id)
	if not pay(float(c["cost"]), "other", "Marketing: %s" % c["name"]):
		return "Not enough money"
	events.append({"kind": "campaign", "id": id, "k": 1.0 + float(c.get("footfall", 0.0)),
		"until": day + int(c.get("days", 3)) - 1, "text": "%s: %s" % [String(brand.get("name", "Your shops")), c["name"]]})
	for b: Business in businesses:
		b.add_rep(float(c.get("rep", 0)))
	stats["campaigns"] = int(stats.get("campaigns", 0)) + 1
	_note("%s running for %d days." % [c["name"], int(c["days"])], "good")
	_check_goals()
	changed.emit()
	return ""


func to_dict() -> Dictionary:
	var vs: Array = []
	for v in vehicles:
		if v.get("test", false):
			continue  # (a test drive is never saved)
		var d: Dictionary = v.duplicate(true)
		d["cargo"] = (v["cargo"] as Stock).to_dict()
		vs.append(d)
	var bs: Array = []
	for b: Business in businesses:
		bs.append(b.to_dict())
	var pal := {}
	for w in pallets:
		pal[w] = (pallets[w] as Stock).to_dict()
	return {"version": VERSION, "seed": seed, "day": day, "minute": minute, "personal_cash": personal_cash,
		"company_cash": company_cash, "businesses": bs, "vehicles": vs, "properties": properties.duplicate(true),
		"loans": loans.duplicate(true), "carried": carried.to_dict(), "pallets": pal, "avg_cost": avg_cost.duplicate(),
		"stats": stats.duplicate(), "goals_done": goals_done.duplicate(), "candidates": candidates.duplicate(true),
		"ledger": ledger.duplicate(true), "log": log.duplicate(true), "day_reports": day_reports.duplicate(true),
		"flags": flags.duplicate(), "id_n": _id_n, "rng_state": str(rng.state),
		"hour_served": _hour_served.duplicate(), "carry": _carry_minutes, "weather": weather, "forecast": forecast,
		"events": events.duplicate(true), "rivals": rivals.duplicate(true), "news": news.duplicate(true),
		"firms": firms.duplicate(true), "brand": brand.duplicate(), "hq": hq.duplicate(),
		"offices": offices.duplicate(true), "club": club.duplicate(true)}


static func from_dict(src: Dictionary) -> Empire:
	var d := migrate(src.duplicate(true))
	var e := Empire.new()
	e.seed = int(d.get("seed", 1))
	e.rng.seed = hash([e.seed, "empire"])
	if d.has("rng_state"):
		e.rng.state = String(d["rng_state"]).to_int()
	e._hour_served = d.get("hour_served", {})
	e._carry_minutes = float(d.get("carry", 0.0))
	e.day = int(d.get("day", 1))
	e.minute = float(d.get("minute", 450.0))
	e.personal_cash = float(d.get("personal_cash", 0.0))
	e.company_cash = float(d.get("company_cash", 0.0))
	for bd in d.get("businesses", []):
		e.businesses.append(Business.from_dict(bd))
	for vd in d.get("vehicles", []):
		var v: Dictionary = vd.duplicate(true)
		v["cargo"] = Stock.from_dict(vd.get("cargo", {}))
		var m := EmpireData.vehicle_model(String(v.get("model", "hatch")))
		(v["cargo"] as Stock).case_capacity = int(m.get("cargo", 8))
		e.vehicles.append(v)
	e.properties = d.get("properties", [])
	e.loans = d.get("loans", [])
	e.carried = Stock.from_dict(d.get("carried", {"cap": 3}))
	e.carried.case_capacity = maxi(e.carried.case_capacity, 3)
	for w in d.get("pallets", {}):
		e.pallets[String(w)] = Stock.from_dict(d["pallets"][w])
	e.avg_cost = d.get("avg_cost", {})
	e.stats = d.get("stats", {})
	var fresh := Empire.new()
	fresh.new_game(1)
	for k in fresh.stats:
		if not e.stats.has(k):
			e.stats[k] = fresh.stats[k]
	e.goals_done = d.get("goals_done", [])
	e.candidates = d.get("candidates", [])
	e.ledger = d.get("ledger", [])
	e.log = d.get("log", [])
	e.day_reports = d.get("day_reports", [])
	e.flags = d.get("flags", {})
	e._id_n = int(d.get("id_n", 100))
	e.weather = String(d.get("weather", "cloudy"))
	e.forecast = String(d.get("forecast", "cloudy"))
	e.events = d.get("events", [])
	e.rivals = d.get("rivals", [])
	e.news = d.get("news", [])
	e.firms = d.get("firms", [])
	e.brand = d.get("brand", {})
	e.hq = d.get("hq", {})
	e.offices = d.get("offices", [])
	e.club = d.get("club", {})
	Club.ensure(e)
	if e.candidates.is_empty():
		e.candidates = Staff.candidates(e.day, e.seed)
	e.repair_duplicates()
	# A unit has one occupier: yours beats a stale independent / rival record.
	e.firms = e.firms.filter(func(f): return e.business_at(String(f.get("unit", ""))) == null)
	e.rivals = e.rivals.filter(func(r): return e.business_at(String(r.get("unit", ""))) == null)
	return e


## One business per commercial unit. A save that somehow holds two for the
## same unit (an old bug, a double tap mid-save) is merged, not dropped:
## the freehold / older record is kept and the other's stock, staff and
## takings move into it. Returns how many were merged.
func repair_duplicates() -> int:
	var by_unit := {}
	var merged := 0
	var keep: Array = []
	for b: Business in businesses:
		var uid := String(b.premises.get("id", ""))
		if uid == "" or not by_unit.has(uid):
			by_unit[uid] = b
			keep.append(b)
			continue
		var k: Business = by_unit[uid]
		if b.owned and not k.owned:
			# The freehold wins: swap which one is kept.
			keep[keep.find(k)] = b
			by_unit[uid] = b
			var t := k
			k = b
			b = t
		for pid in b.backroom.units.keys():
			k.backroom.create(pid, b.backroom.qty(pid))
		for pid in b.floor_pile.units.keys():
			k.backroom.create(pid, b.floor_pile.qty(pid))
		for sl: Dictionary in b.slots:
			if String(sl["product"]) != "" and int(sl["qty"]) > 0:
				k.backroom.create(String(sl["product"]), int(sl["qty"]))
		k.backroom.case_capacity = maxi(k.backroom.case_capacity, k.backroom.cases_used())
		var ids := k.staff.map(func(x): return x["id"])
		for x in b.staff:
			if not ids.has(x["id"]):
				x["business"] = k.id
				k.staff.append(x)
		for key in ["revenue", "cogs", "fees", "wages", "other"]:
			k.today[key] = float(k.today.get(key, 0.0)) + float(b.today.get(key, 0.0))
		k.orders.append_array(b.orders)
		merged += 1
	if merged > 0:
		businesses = keep
		flags["repaired_duplicates"] = int(flags.get("repaired_duplicates", 0)) + merged
	return merged


## Upgrades older saves step by step to VERSION.
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		# v1 kept a single "cash" (company and personal were merged).
		if d.has("cash") and not d.has("personal_cash"):
			d["personal_cash"] = float(d["cash"])
			d["company_cash"] = 0.0
			d.erase("cash")
		if not d.has("flags"):
			d["flags"] = {}
		v = 2
	if v < 3:
		# v3 added city life (weather, events, the rival chain). Older games
		# start with fair weather and no rivals (they arrive on schedule).
		for k in ["events", "rivals", "news"]:
			if not d.has(k):
				d[k] = []
		v = 3
	if v < 4:
		# v4 added the independent shops; they're seeded on the first day
		# the game has the city's units (CityLife.ensure_firms).
		if not d.has("firms"):
			d["firms"] = []
		v = 4
	if v < 5:
		# v5: office companies and the football club (seeded by Club.ensure).
		if not d.has("offices"):
			d["offices"] = []
		v = 5
	if v < 6:
		# v6: Skyport Island moved south of the strait (a quarter turn): its
		# vehicles, aircraft and boats move with it; the GPS target too.
		for vv in d.get("vehicles", []):
			var pos: Array = vv.get("pos", [])
			if pos.size() >= 3:
				var p := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
				if SkyportIsland.was_old_site(p):
					var q := SkyportIsland.migrate_point(p)
					vv["pos"] = [q.x, q.y, q.z]
					vv["yaw"] = SkyportIsland.wyaw(float(vv.get("yaw", 0.0)))
		var fl: Dictionary = d.get("flags", {})
		var g = fl.get("gps", null)
		if g is Array and (g as Array).size() == 3:
			var q2 := SkyportIsland.migrate_point(Vector3(float(g[0]), float(g[1]), float(g[2])))
			fl["gps"] = [q2.x, q2.y, q2.z]
		v = 6
	d["version"] = v
	return d
