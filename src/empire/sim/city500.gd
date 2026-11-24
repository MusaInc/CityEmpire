class_name City500
extends RefCounted
## City500: the 500 most valuable companies in the city, and you.
##
## The 500 are generated from one fixed seed (same names, sectors and
## founders in every game) and their valuations are a pure function of the
## day: value(c, day) = base × trend × sector cycle × own cycles × shocks.
## Nothing about them is saved – a save only keeps your own rank history
## (flags.c500) – so the table is persistent, deterministic and costs
## nothing per frame (computed once per game day, ~1 ms for 500 × 2 days).
##
## Your empire is valued on the same terms (empire_value): net assets at
## book value (cash in both accounts, stock at cost, owned premises,
## vehicles at trade, property, head office, ventures, the club, minus
## debt) plus an earnings value: average daily operating profit of the last
## 7 reported days × 365 × a sector multiple × reputation. Moving money
## between accounts, buying and selling the same asset or recycling cash
## never adds value: cash and assets are counted once, at what you'd get
## for them, and only trading profit is capitalised.

const N := 500
const SEED := 500_2026
const EARN_MULTIPLE := 3.2       # years of operating profit an investor pays for
const TOP_VALUE := 3.4e9         # #1 on day 1
const FLOOR_VALUE := 3.0e5       # ≈ #500 on day 1
const BROKERAGE_FEE := 0.015     # 1.5% sell fee prevents buy/sell flip exploits
const DAILY_DIVIDEND_RATE := 0.0018  # ~0.18% daily yield on equity stake value
const CONTROL_PCT := 51.0        # >=51% controlling acquisition (1.35x operating dividend)

## Sector: [label, colour, revenue multiple (value / annual revenue), margin,
## revenue per employee £, typical operations]
const SECTORS := {
	"retail": ["Retail", Color("#f2b544"), 0.9, 0.06, 140000.0, "stores across the city"],
	"food": ["Food & distribution", Color("#8bc34a"), 0.7, 0.05, 180000.0, "depots and supermarkets"],
	"hospitality": ["Hospitality", Color("#ff8a65"), 1.3, 0.09, 60000.0, "restaurants, bars and hotels"],
	"property": ["Property", Color("#4fc3f7"), 6.0, 0.32, 650000.0, "offices, flats and retail parks"],
	"automotive": ["Automotive", Color("#e57373"), 0.8, 0.07, 260000.0, "dealerships and workshops"],
	"logistics": ["Logistics", Color("#9575cd"), 1.0, 0.08, 150000.0, "warehouses and delivery fleets"],
	"manufacturing": ["Manufacturing", Color("#90a4ae"), 1.1, 0.10, 170000.0, "factories on the docks"],
	"technology": ["Technology", Color("#26c6da"), 4.5, 0.18, 320000.0, "offices in the Financial District"],
	"construction": ["Construction", Color("#ffb74d"), 0.6, 0.05, 190000.0, "sites across all three islands"],
	"entertainment": ["Entertainment", Color("#f06292"), 2.2, 0.12, 110000.0, "venues, studios and the stadium district"],
	"transport": ["Transport", Color("#64b5f6"), 1.4, 0.09, 140000.0, "buses, ferries and Skyport services"],
	"finance": ["Finance", Color("#81c784"), 3.5, 0.28, 420000.0, "banks and insurers"],
}
## How common each sector is in the 500 (weights).
const SECTOR_WEIGHT := {"retail": 14, "food": 9, "hospitality": 11, "property": 8, "automotive": 6, "logistics": 7,
	"manufacturing": 8, "technology": 9, "construction": 7, "entertainment": 6, "transport": 5, "finance": 6}

const STEMS := ["Harbour", "Lantern", "Meridian", "Westbank", "Skyport", "Northgate", "Crown", "Anchor", "Beacon", "Granite",
	"Oakline", "Silverline", "Bridgewater", "Kestrel", "Halcyon", "Ironside", "Copperfield", "Bluewater", "Redcliffe", "Fairhaven",
	"Strand", "Monarch", "Corinth", "Sterling", "Larkspur", "Ashford", "Pinnacle", "Marlow", "Thornbury", "Whitlock", "Cobalt",
	"Vantage", "Summit", "Keystone", "Riverside", "Quayside", "Linden", "Albion", "Hawthorne", "Mercer", "Osprey", "Arden",
	"Calder", "Driftwood", "Elmstead", "Foxley", "Galleon", "Highcross", "Juniper", "Kingsway", "Lockhart", "Mayfield",
	"Northwind", "Orchard", "Portland", "Regent", "Saltmarsh", "Tidewell", "Union", "Victoria", "Wexford", "Yardley", "Zenith",
	"Atlas", "Brightwater", "Castle", "Dockside", "Emberly", "Fleet", "Goldcrest", "Heron", "Isle", "Jubilee", "Kingfisher",
	"Lighthouse", "Marina", "Nova", "Old Town", "Prospect", "Quarry", "Rook", "Seaview", "Tower", "Upland", "Vale", "Wharf"]
const SUFFIX := {
	"retail": ["Stores", "Retail Group", "& Co", "Market", "Outlets", "Trading", "Department Stores", "Home"],
	"food": ["Foods", "Fresh", "Grocers", "Distribution", "Provisions", "Dairies", "Bakeries", "Wholesale"],
	"hospitality": ["Hotels", "Dining", "Leisure", "Inns", "Kitchens", "Coffee", "Hospitality", "Taverns"],
	"property": ["Estates", "Properties", "Land", "Developments", "Holdings", "REIT", "Realty", "Living"],
	"automotive": ["Motors", "Auto Group", "Garages", "Car Sales", "Autocare", "Motor Works"],
	"logistics": ["Logistics", "Freight", "Haulage", "Couriers", "Shipping", "Express"],
	"manufacturing": ["Industries", "Works", "Engineering", "Fabrication", "Steel", "Plastics", "Textiles"],
	"technology": ["Labs", "Digital", "Systems", "Software", "Networks", "Data", "Robotics", "AI"],
	"construction": ["Construction", "Builders", "Contractors", "Civil", "Building Group"],
	"entertainment": ["Entertainment", "Studios", "Media", "Arenas", "Live", "Games"],
	"transport": ["Transit", "Ferries", "Buses", "Air", "Rail", "Cabs"],
	"finance": ["Bank", "Capital", "Insurance", "Investments", "Building Society", "Partners"],
}
const OWNERS := ["Listed on the City Exchange", "Family owned", "Founder owned", "Private equity", "Employee owned",
	"Listed on the City Exchange", "Partnership", "Family owned"]

static var _list: Array = []           # the 500 company records (fixed)
static var _cache_day := -1
static var _cache: Array = []          # [[value, idx], …] sorted, for _cache_day
static var _cache_prev: Array = []     # same for _cache_day - 7 (rank movement)


## The 500 companies (generated once).
static func companies() -> Array:
	if not _list.is_empty():
		return _list
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var names := {}
	var sectors: Array = SECTOR_WEIGHT.keys()
	var wsum := 0.0
	for s in sectors:
		wsum += float(SECTOR_WEIGHT[s])
	var sd := EmpireData.file("staff")
	var first: Array = sd.get("first_names", ["Sam", "Alex"])
	var last: Array = sd.get("last_names", ["Smith", "Jones"])
	for i in N:
		# Sector (weighted).
		var pick := rng.randf() * wsum
		var sec := String(sectors[0])
		for s in sectors:
			pick -= float(SECTOR_WEIGHT[s])
			if pick <= 0.0:
				sec = s
				break
		# A unique name: stem + sector suffix, a founder's surname, or initials.
		var nm := ""
		for _try in 20:
			var r := rng.randf()
			var suf: Array = SUFFIX[sec]
			if r < 0.62:
				nm = "%s %s" % [STEMS[rng.randi() % STEMS.size()], suf[rng.randi() % suf.size()]]
			elif r < 0.86:
				nm = "%s %s" % [last[rng.randi() % last.size()], suf[rng.randi() % suf.size()]]
			else:
				nm = "%s%s %s" % [STEMS[rng.randi() % STEMS.size()].substr(0, 1), String(last[rng.randi() % last.size()]).substr(0, 1),
					suf[rng.randi() % suf.size()]]
			if not names.has(nm):
				break
		names[nm] = true
		# Size: a power law by position, jittered (so the start order isn't
		# the generation order).
		var pos := (float(i) + rng.randf_range(-0.45, 2.5)) / float(N)
		var base := TOP_VALUE * pow(FLOOR_VALUE / TOP_VALUE, clampf(pos, 0.0, 1.0))
		var big := base > 2.0e8
		var own := String(OWNERS[rng.randi() % OWNERS.size()])
		if big and rng.randf() < 0.6:
			own = "Listed on the City Exchange"
		_list.append({
			"i": i, "name": nm, "sector": sec, "base": base,
			"growth": rng.randfn(0.06, 0.09) + (0.05 if sec == "technology" else 0.0),   # a year
			"vol": rng.randf_range(0.04, 0.16) * (1.6 if sec == "technology" else 1.0),
			"ph": [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU],
			"per": [rng.randf_range(90.0, 220.0), rng.randf_range(25.0, 60.0), rng.randf_range(7.0, 16.0)],
			"margin_k": rng.randf_range(0.6, 1.5),
			"debt_k": rng.randf_range(0.05, 0.6),
			"rep": int(clampf(rng.randfn(62.0 + (10.0 if big else 0.0), 12.0), 20.0, 98.0)),
			"founded": 2026 - int(clampf(rng.randfn(28.0 if big else 12.0, 14.0), 1.0, 140.0)),
			"owner": own,
			"ceo": "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]],
			"shock_seed": rng.randi(),
		})
	return _list


static func sector_name(sec: String) -> String:
	return String(SECTORS.get(sec, ["Business"])[0])


static func sector_colour(sec: String) -> Color:
	return SECTORS.get(sec, ["", Color.WHITE])[1]


## Sector-wide conditions on a day (slow cycles, shared by the sector).
static func _sector_k(sec: String, day: int) -> float:
	var h := float(hash(sec) % 1000) / 1000.0 * TAU
	return exp(0.07 * sin(float(day) / 160.0 + h) + 0.03 * sin(float(day) / 41.0 + h * 2.0))


## A company's shocks up to a day: each fortnight it may win a contract,
## open/close sites or have a bad quarter; the effect fades over ~60 days.
static func _shocks(c: Dictionary, day: int) -> float:
	var s := 0.0
	var w0 := maxi(0, day / 14 - 6)
	for w in range(w0, day / 14 + 1):
		var h := hash([c["shock_seed"], w])
		if h % 7 != 0:
			continue
		var amp := (float((h >> 4) % 1000) / 1000.0 - 0.45) * 0.5
		var age := float(day - w * 14)
		if age < 0.0:
			continue
		s += amp * exp(-age / 60.0) * minf(1.0, age / 5.0)
	return s


static func value(c: Dictionary, day: int) -> float:
	var t := float(day)
	var ph: Array = c["ph"]
	var per: Array = c["per"]
	var vol := float(c["vol"])
	var l := float(c["growth"]) * t / 365.0 \
		+ vol * (sin(t / float(per[0]) + float(ph[0])) + 0.5 * sin(t / float(per[1]) + float(ph[1])) + 0.2 * sin(t / float(per[2]) + float(ph[2]))) \
		+ _shocks(c, day)
	return float(c["base"]) * exp(l) * _sector_k(String(c["sector"]), day)


## Financial profile derived from value and sector (consistent: value ≈
## profit × multiple + net assets).
static func profile(c: Dictionary, day: int) -> Dictionary:
	var v := value(c, day)
	var S0: Array = SECTORS[c["sector"]]
	var revenue := v / float(S0[2])
	var margin := float(S0[3]) * float(c["margin_k"])
	var profit := revenue * margin
	var assets := v * (0.45 + float(c["debt_k"]) * 0.7)
	var debt := assets * float(c["debt_k"])
	var staff := maxi(3, int(revenue / float(S0[4])))
	var sites := maxi(1, int(pow(v / 4.0e5, 0.5)))
	return {"value": v, "revenue": revenue, "profit": profit, "margin": margin, "assets": assets, "debt": debt,
		"staff": staff, "sites": sites, "ops": String(S0[5])}


# ------------------------------------------------------------ you
## Your empire's value and the parts it's made of.
static func empire_value(e: Empire) -> Dictionary:
	var debt := 0.0
	for l in e.loans:
		debt += float(l["principal"])
	var od := maxf(-e.company_cash, 0.0)
	var cash := maxf(e.company_cash, 0.0) + e.personal_cash
	var pv := portfolio_value(e)
	var assets := cash + e.stock_value() + e.premises_value() + e.vehicles_value() + float(e.hq.get("paid", 0.0)) \
		+ Club.value(e) + Ventures.assets_value(e) + pv
	for q in e.properties:
		assets += float(q.get("price", 0.0))
	var liab := debt + od
	# Operating profit: the last 7 reported days (losses count in full,
	# so a bad week lowers the earnings value to nothing, not below it).
	# Early saves ramp smoothly over the first 7 trading days toward the
	# 7-day rolling average so 1-3 strong days cannot cause a 1,168x spike.
	var rs: Array = e.day_reports.slice(maxi(e.day_reports.size() - 7, 0))
	var prof := 0.0
	var rev := 0.0
	for r in rs:
		prof += float(r.get("profit", 0.0)) - float(r.get("dividends", 0.0))
		rev += float(r.get("revenue", 0.0))
	var n := maxf(1.0, float(rs.size()))
	var daily := prof / n
	var track_k := clampf(float(rs.size()) / 7.0, 0.0, 1.0)
	var rolling_daily := daily * track_k
	var rep := 50.0
	if not e.businesses.is_empty():
		rep = 0.0
		for b: Business in e.businesses:
			rep += b.reputation
		rep /= float(e.businesses.size())
	var rep_k := lerpf(0.8, 1.2, clampf(rep / 100.0, 0.0, 1.0))
	var earn := maxf(0.0, rolling_daily) * 365.0 * EARN_MULTIPLE * rep_k
	var val := maxf(0.0, assets - liab + earn)
	return {"value": val, "assets": assets, "portfolio": pv, "debt": liab, "earnings_value": earn, "profit_day": daily,
		"revenue_year": rev / n * 365.0, "profit_year": rolling_daily * 365.0, "reputation": rep,
		"staff": int(e.stat("staff")), "sites": e.businesses.size() + e.offices.size()}


## Scalar empire valuation helper (matches empire_value(e)["value"]).
static func player_value(empire: Empire) -> float:
	return float(empire_value(empire)["value"])


# ------------------------------------------------------- equity & M&A
static func company(idx: int) -> Dictionary:
	var cs := companies()
	if idx < 0 or idx >= cs.size():
		return {}
	return cs[idx]


static func _stakes(empire: Empire) -> Dictionary:
	var s = empire.flags.get("c500_stakes", null)
	return s if s is Dictionary else {}


## Summary of the player's equity stake in company `idx`.
static func stake_of(empire: Empire, idx: int) -> Dictionary:
	var c := company(idx)
	var key := str(idx)
	var rec: Dictionary = _stakes(empire).get(key, {})
	var pct := clampf(float(rec.get("pct", 0.0)), 0.0, 100.0)
	var cost := float(rec.get("cost", 0.0))
	if c.is_empty() or pct <= 0.0001:
		return {"idx": idx, "pct": 0.0, "cost": 0.0, "value": 0.0, "gain": 0.0, "control": false, "buyout": false}
	var val := value(c, empire.day) * (pct / 100.0)
	return {"idx": idx, "pct": pct, "cost": cost, "value": val, "gain": val - cost,
		"control": pct >= CONTROL_PCT - 0.001, "buyout": pct >= 99.999}


## Buys up to `pct`% (default 5%) of company `idx`, capped at 100% full buyout.
static func buy_stake(empire: Empire, idx: int, pct: float = 5.0) -> Dictionary:
	var c := company(idx)
	if c.is_empty() or not is_finite(pct) or pct <= 0.0:
		return {"ok": false, "error": "Invalid company or stake size"}
	var stakes: Dictionary = _stakes(empire).duplicate(true)
	var key := str(idx)
	var rec: Dictionary = stakes.get(key, {"pct": 0.0, "cost": 0.0})
	var old_pct := clampf(float(rec.get("pct", 0.0)), 0.0, 100.0)
	var buy_pct := minf(pct, 100.0 - old_pct)
	if buy_pct <= 0.001:
		return {"ok": false, "error": "You already own 100%% of %s" % c["name"]}
	var price := value(c, empire.day) * (buy_pct / 100.0)
	if not empire.pay(price, "investment", "Bought %.1f%% of %s" % [buy_pct, c["name"]]):
		return {"ok": false, "error": "Not enough money (%s)" % money(price)}
	var new_pct := clampf(old_pct + buy_pct, 0.0, 100.0)
	if new_pct >= 99.999:
		new_pct = 100.0
	stakes[key] = {"pct": new_pct, "cost": float(rec.get("cost", 0.0)) + price}
	empire.flags["c500_stakes"] = stakes
	var is_buyout := new_pct >= 99.999
	var is_control := new_pct >= CONTROL_PCT - 0.001
	if is_buyout and old_pct < 99.999:
		empire._note("Full acquisition: %s is now 100%% yours!" % c["name"], "good")
	elif is_control and old_pct < CONTROL_PCT - 0.001:
		empire._note("Controlling stake in %s (%.0f%%) — operating dividends boosted!" % [c["name"], new_pct], "good")
	else:
		empire._note("Acquired %.1f%% of %s for %s" % [buy_pct, c["name"], money(price)], "good")
	empire._check_goals()
	empire.changed.emit()
	return {"ok": true, "idx": idx, "bought_pct": buy_pct, "pct": new_pct, "cost": price,
		"control": is_control, "buyout": is_buyout, "error": ""}


## Sells up to `pct`% (default 5%) of company `idx` at market value minus 1.5% brokerage fee.
static func sell_stake(empire: Empire, idx: int, pct: float = 5.0) -> Dictionary:
	var c := company(idx)
	if c.is_empty() or not is_finite(pct) or pct <= 0.0:
		return {"ok": false, "error": "Invalid company or stake size"}
	var stakes: Dictionary = _stakes(empire).duplicate(true)
	var key := str(idx)
	if not stakes.has(key):
		return {"ok": false, "error": "You hold no stake in %s" % c["name"]}
	var rec: Dictionary = stakes[key]
	var old_pct := clampf(float(rec.get("pct", 0.0)), 0.0, 100.0)
	var old_cost := float(rec.get("cost", 0.0))
	var sell_pct := minf(pct, old_pct)
	if sell_pct <= 0.001:
		return {"ok": false, "error": "No shares to sell"}
	var gross := value(c, empire.day) * (sell_pct / 100.0)
	var fee := gross * BROKERAGE_FEE
	var proceeds := gross - fee
	var cost_removed := old_cost * (sell_pct / maxf(old_pct, 0.0001))
	var rem_pct := old_pct - sell_pct
	if rem_pct <= 0.001:
		stakes.erase(key)
		rem_pct = 0.0
	else:
		stakes[key] = {"pct": rem_pct, "cost": maxf(0.0, old_cost - cost_removed)}
	empire.flags["c500_stakes"] = stakes
	empire.company_cash += proceeds
	empire._book("company", proceeds, "investment", "Sold %.1f%% of %s" % [sell_pct, c["name"]])
	empire.changed.emit()
	return {"ok": true, "idx": idx, "sold_pct": sell_pct, "pct": rem_pct, "gross": gross, "fee": fee,
		"proceeds": proceeds, "realised_gain": proceeds - cost_removed, "error": ""}


## Current market value of all held City500 equity stakes (at net asset value).
static func portfolio_value(empire: Empire) -> float:
	var stakes := _stakes(empire)
	if stakes.is_empty():
		return 0.0
	var cs := companies()
	var total := 0.0
	for key in stakes:
		var idx := String(key).to_int()
		if idx < 0 or idx >= cs.size():
			continue
		var pct := clampf(float((stakes[key] as Dictionary).get("pct", 0.0)), 0.0, 100.0)
		if pct > 0.0001:
			total += value(cs[idx], empire.day) * (pct / 100.0)
	return total


static func stake_dividend(c: Dictionary, day: int, pct: float) -> float:
	var val := value(c, day) * (pct / 100.0)
	var momentum := clampf(_sector_k(String(c["sector"]), day), 0.85, 1.2)
	var ctrl := 1.35 if pct >= CONTROL_PCT - 0.001 else 1.0
	return val * DAILY_DIVIDEND_RATE * momentum * ctrl


## Daily dividend income across all held City500 stakes (~0.18%/day, 1.35x for >=51% control).
static func daily_dividend(empire: Empire) -> float:
	var stakes := _stakes(empire)
	if stakes.is_empty():
		return 0.0
	var cs := companies()
	var total := 0.0
	for key in stakes:
		var idx := String(key).to_int()
		if idx < 0 or idx >= cs.size():
			continue
		var pct := clampf(float((stakes[key] as Dictionary).get("pct", 0.0)), 0.0, 100.0)
		if pct > 0.0001:
			total += stake_dividend(cs[idx], empire.day, pct)
	return total


## All held equity stakes, sorted by current market value descending.
static func all_stakes(empire: Empire) -> Array:
	var stakes := _stakes(empire)
	if stakes.is_empty():
		return []
	var cs := companies()
	var out: Array = []
	for key in stakes:
		var idx := String(key).to_int()
		if idx < 0 or idx >= cs.size():
			continue
		var rec: Dictionary = stakes[key]
		var pct := clampf(float(rec.get("pct", 0.0)), 0.0, 100.0)
		if pct <= 0.0001:
			continue
		var c: Dictionary = cs[idx]
		var cost := float(rec.get("cost", 0.0))
		var val := value(c, empire.day) * (pct / 100.0)
		out.append({
			"idx": idx, "c": c, "name": c["name"], "sector": c["sector"],
			"pct": pct, "cost": cost, "value": val, "gain": val - cost,
			"control": pct >= CONTROL_PCT - 0.001, "buyout": pct >= 99.999,
			"daily_div": stake_dividend(c, empire.day, pct),
		})
	out.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	return out


## Table for a day: [[value, index]] sorted by value, highest first.
static func _table(day: int) -> Array:
	var out: Array = []
	for c in companies():
		out.append([value(c, day), int(c["i"])])
	out.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	return out


static func _ensure(day: int) -> void:
	if _cache_day == day:
		return
	_cache_day = day
	_cache = _table(day)
	_cache_prev = _table(maxi(day - 7, 0))


## Ranked list for a day: [{c, rank, value, move (+ = up since a week ago)}],
## with your empire placed in it ("you": true) when it ranks.
static func ranking(e: Empire) -> Array:
	_ensure(e.day)
	var prev_rank := {}
	for i in _cache_prev.size():
		prev_rank[int(_cache_prev[i][1])] = i + 1
	var mine := float(empire_value(e)["value"])
	var out: Array = []
	var placed := false
	var rank := 1
	for i in _cache.size():
		var v := float(_cache[i][0])
		if not placed and mine > v:
			out.append({"you": true, "rank": rank, "value": mine, "move": you_move(e)})
			placed = true
			rank += 1
		if rank > N:
			break
		var idx := int(_cache[i][1])
		out.append({"c": companies()[idx], "rank": rank, "value": v, "move": int(prev_rank.get(idx, i + 1)) - (i + 1)})
		rank += 1
	return out


## Your rank (1-500) or 0 = outside; and the value of #500.
static func your_rank(e: Empire) -> Dictionary:
	_ensure(e.day)
	var mine := float(empire_value(e)["value"])
	var above := 0
	for row in _cache:
		if float(row[0]) > mine:
			above += 1
		else:
			break
	var r := above + 1
	var floor_v := float(_cache[N - 1][0])
	# The company just ahead (who you chase next).
	var ahead := {}
	if above > 0:
		var a: Array = _cache[above - 1]
		ahead = {"c": companies()[int(a[1])], "value": float(a[0]), "rank": above}
	return {"rank": r if r <= N else 0, "value": mine, "floor": floor_v, "gap_500": maxf(0.0, floor_v - mine), "ahead": ahead,
		"position": r}


## Places up (+) or down since the oldest of the last 7 recorded days.
static func you_move(e: Empire) -> int:
	var h: Array = e.flags.get("c500", [])
	if h.size() < 2:
		return 0
	var old: Array = h[maxi(0, h.size() - 8)]
	var now: Array = h[-1]
	return int(old[1]) - int(now[1])


## End of a game day: record your position, and say so when it matters.
## Returns notices [[text, kind]].
static func day_ended(e: Empire) -> Array:
	var notes: Array = []
	var yr := your_rank(e)
	var h: Array = e.flags.get("c500", [])
	var pos := int(yr["position"])
	var last_pos := int(h[-1][1]) if not h.is_empty() else 99999
	h.append([e.day, pos, roundf(float(yr["value"]))])
	while h.size() > 40:
		h.pop_front()
	e.flags["c500"] = h
	if pos <= N and last_pos > N:
		notes.append(["You've entered the City500 at #%d!" % pos, "good"])
	elif pos <= N and pos < last_pos:
		var best := int(e.flags.get("c500_best", 99999))
		if pos < best:
			for milestone in [400, 300, 250, 200, 150, 100, 50, 25, 10, 5, 1]:
				if pos <= milestone and best > milestone:
					notes.append(["City500: you're in the top %d (#%d)" % [milestone, pos], "good"])
					break
		if notes.is_empty():
			notes.append(["City500: up %d place%s to #%d" % [last_pos - pos, "" if last_pos - pos == 1 else "s", pos], "good"])
	elif pos > N and last_pos <= N:
		notes.append(["You've dropped out of the City500", "bad"])
	elif pos <= N and pos > last_pos + 4:
		notes.append(["City500: down %d places to #%d" % [pos - last_pos, pos], "warn"])
	if pos <= N:
		e.flags["c500_best"] = mini(int(e.flags.get("c500_best", 99999)), pos)
	return notes


## Today's biggest movers among the 500 (value change since yesterday).
static func movers(day: int, n := 3) -> Dictionary:
	var ch: Array = []
	for c in companies():
		var a := value(c, maxi(day - 1, 0))
		var b := value(c, day)
		ch.append([b / a - 1.0, c])
	ch.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	return {"up": ch.slice(0, n), "down": ch.slice(ch.size() - n).duplicate()}


## Market headlines for a day (deterministic): biggest mover, an overtake
## in the top 50, a sector's week.
static func headlines(day: int) -> Array:
	var out: Array = []
	var m := movers(day, 1)
	if not m["up"].is_empty():
		var u: Array = m["up"][0]
		out.append(["%s up %.1f%% – %s" % [u[1]["name"], float(u[0]) * 100.0, ["a big new contract", "record trading", "new sites opening", "a takeover bid"][hash([day, 1]) % 4]], "good"])
	if not m["down"].is_empty():
		var d: Array = m["down"][-1]
		out.append(["%s down %.1f%% – %s" % [d[1]["name"], absf(float(d[0])) * 100.0, ["a profit warning", "a lost contract", "store closures", "a weak quarter"][hash([day, 2]) % 4]], "bad"])
	_ensure(day)
	var t0 := _table(maxi(day - 1, 0))
	for i in mini(50, _cache.size()):
		if int(_cache[i][1]) != int(t0[i][1]):
			var a: Dictionary = companies()[int(_cache[i][1])]
			out.append(["%s climbs to #%d" % [a["name"], i + 1], "info"])
			break
	var best := ""
	var bk := 0.0
	for s in SECTORS:
		var k := _sector_k(s, day) / _sector_k(s, maxi(day - 7, 0))
		if absf(k - 1.0) > absf(bk - 1.0):
			bk = k
			best = s
	if best != "":
		out.append(["%s %s %.1f%% this week" % [sector_name(best), "up" if bk >= 1.0 else "down", absf(bk - 1.0) * 100.0], "good" if bk >= 1.0 else "warn"])
	return out


## Value history for a sparkline (last n days).
static func history(c: Dictionary, day: int, n := 30) -> Array:
	var out: Array = []
	for d in range(maxi(0, day - n + 1), day + 1):
		out.append(value(c, d))
	return out


## The companies whose sector and size make them your direct competitors
## (shops: retail/food/hospitality, valued within 10x of you).
static func rivals(e: Empire, n := 5) -> Array:
	var mine := maxf(float(empire_value(e)["value"]), 1.0)
	var out: Array = []
	for row in ranking(e):
		if row.get("you", false):
			continue
		var c: Dictionary = row["c"]
		if String(c["sector"]) in ["retail", "food", "hospitality"] and float(row["value"]) < mine * 12.0:
			out.append(row)
			if out.size() >= n:
				break
	return out


## The next achievable step on the way into (and up) the City500, for a
## player who starts with a few hundred pounds next to billion-pound leaders
## (WS-05): a near milestone, how far, roughly how long at today's profit, what
## an extra £10 a day of profit is worth, and the one lever that moves it most.
const MILESTONES := [2500.0, 5000.0, 10000.0, 25000.0, 50000.0, 100000.0, 200000.0]


static func next_step(e: Empire) -> Dictionary:
	var ev := empire_value(e)
	var yr := your_rank(e)
	var mine := float(ev["value"])
	var target := 0.0
	var label := ""
	if int(yr["rank"]) > 0:
		var ah: Dictionary = yr["ahead"]
		if not ah.is_empty():
			target = float(ah["value"])
			label = "Pass %s (#%d)" % [ah["c"]["name"], int(ah["rank"])]
	else:
		for m in MILESTONES:
			if m > mine and m < float(yr["floor"]):
				target = m
				label = "Reach a %s business" % money(m)
				break
		if target == 0.0:
			target = float(yr["floor"])
			label = "Enter the City500 (#500)"
	var start := 0.0
	for m in MILESTONES:
		if m <= mine:
			start = m
	var rep_k := lerpf(0.8, 1.2, clampf(float(ev["reputation"]) / 100.0, 0.0, 1.0))
	var per10 := 10.0 * 365.0 * EARN_MULTIPLE * rep_k
	var daily := float(ev["profit_day"])
	var days := -1
	if daily > 0.0 and target > mine:
		# Profit banks as cash every day (assets), the earnings value holds.
		days = int(ceil((target - mine) / daily))
	var tip := ""
	if e.businesses.is_empty():
		tip = "Rent your first shop: a business that makes money is worth years of its profit."
	elif daily <= 0.0:
		tip = "Get a shop into profit: stocked shelves and a cashier, then check its prices."
	elif e.businesses.size() == 1:
		tip = "A second shop roughly doubles the profit investors value you on."
	elif float(ev["reputation"]) < 60.0:
		tip = "Better reputation (clean, stocked, staffed shops) raises what your profit is worth (×%.2f now)." % rep_k
	else:
		tip = "More profitable sites, or property that pays rent, move you up fastest."
	# The companies just above you (or the bottom of the table) – not the leaders.
	var near: Array = []
	var rk := ranking(e)
	var you_i := -1
	for i in rk.size():
		if rk[i].get("you", false):
			you_i = i
			break
	var top := you_i if you_i >= 0 else rk.size()
	for i in range(maxi(0, top - 3), top):
		if not rk[i].get("you", false):
			near.append(rk[i])
	return {"label": label, "target": target, "value": mine, "from": start, "gap": maxf(0.0, target - mine),
		"days": days, "per10": per10, "profit_day": daily, "tip": tip, "near": near, "ranked": int(yr["rank"]) > 0}


## Why a company is ahead of you, in one sentence.
static func why_ahead(e: Empire, c: Dictionary) -> String:
	var p := profile(c, e.day)
	var me := empire_value(e)
	var parts: Array = []
	if float(p["revenue"]) > float(me["revenue_year"]) * 1.5:
		parts.append("%sx your revenue" % _x(float(p["revenue"]), maxf(float(me["revenue_year"]), 1.0)))
	if float(p["assets"]) > float(me["assets"]) * 1.5:
		parts.append("%sx your assets" % _x(float(p["assets"]), maxf(float(me["assets"]), 1.0)))
	if int(p["sites"]) > int(me["sites"]) + 1:
		parts.append("%d sites to your %d" % [int(p["sites"]), int(me["sites"])])
	if int(c["rep"]) > int(me["reputation"]) + 8:
		parts.append("a better reputation (%d vs %d)" % [int(c["rep"]), int(me["reputation"])])
	if parts.is_empty():
		return "Close: a few good trading days would take you past it."
	return "It has " + ", ".join(parts.slice(0, 3)) + "."


## Big money, compact: £3.36bn, £412m, £239k.
static func money(x: float) -> String:
	var a := absf(x)
	var sg := "-" if x < 0.0 else ""
	if a >= 1.0e9:
		return "%s£%.2fbn" % [sg, a / 1.0e9]
	if a >= 1.0e6:
		return "%s£%.1fm" % [sg, a / 1.0e6]
	if a >= 1.0e4:
		return "%s£%dk" % [sg, int(a / 1000.0)]
	return EmpireData.money(x)


static func _x(a: float, b: float) -> String:
	var r := a / b
	if r >= 1000.0:
		return "%dk" % int(r / 1000.0)
	if r >= 10.0:
		return "%d" % int(r)
	return "%.1f" % r
