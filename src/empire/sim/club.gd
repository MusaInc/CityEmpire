class_name Club
extends RefCounted
## Harbour City FC at The Heights Ground (config/empire/club.json).
## Empire.club holds the club whether you own it or not:
##   {owned, rating, ticket, upgrades, signings, table [{name, rating, p,
##    pts, w, d, l}], played, season, form [W/D/L…], last {…}, trophies,
##    boost_until, cap}
## Saturdays are matchdays (home every other week, kick-off 15:00, result
## at 17:00). A home game fills the streets round the ground: shops within
## footfall_radius get more shoppers 12:00–18:00, cafés and takeaways most.
## Own the club and the gate money, the squad's wages and the season's
## prize money are yours.

const STADIUM := Vector2(843, 219)   # SetPieces.STADIUM_AT


static func cfg() -> Dictionary:
	return EmpireData.file("club")


static func ensure(e: Empire) -> void:
	if not e.club.is_empty():
		return
	var c := cfg()
	var table: Array = [{"name": String(c.get("name", "Harbour City FC")), "rating": float(c.get("start_rating", 60)), "us": true}]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([e.seed, "club"])
	for nm in c.get("rivals", []):
		table.append({"name": String(nm), "rating": rng.randf_range(52.0, 74.0)})
	for t in table:
		t["p"] = 0
		t["pts"] = 0
		t["w"] = 0
		t["d"] = 0
		t["l"] = 0
	e.club = {"owned": false, "rating": float(c.get("start_rating", 60)), "ticket": 1, "upgrades": [], "signings": [],
		"table": table, "played": 0, "season": 1, "form": [], "last": {}, "trophies": 0, "boost_until": 0,
		"cap": int(c.get("capacity", 9000)), "today": {}, "lifetime": {"profit": 0.0}}


# ------------------------------------------------------------- calendar
static func is_matchday(e: Empire, day := -1) -> bool:
	var d := e.day if day < 0 else day
	return (d - 1) % 7 == 5   # Saturday


## Home games every other Saturday.
static func is_home(e: Empire, day := -1) -> bool:
	var d := e.day if day < 0 else day
	return is_matchday(e, d) and ((d - 1) / 7) % 2 == 0


static func next_match_day(e: Empire) -> int:
	var d := e.day
	if is_matchday(e, d) and e.hour() >= 17.0:
		d += 1
	while not is_matchday(e, d):
		d += 1
	return d


## The crowd is in town (home game, 12:00–18:00).
static func crowd_on(e: Empire) -> bool:
	return is_home(e) and e.hour() >= 12.0 and e.hour() < 18.0


static func opponent(e: Empire, day := -1) -> Dictionary:
	ensure(e)
	var d := e.day if day < 0 else day
	var t: Array = e.club["table"]
	var n := t.size() - 1
	return t[1 + ((d - 1) / 7 + int(e.club["season"]) * 3) % n]


# ------------------------------------------------------------- footfall
## Shoppers ×this for a shop (home-game crowds near the ground).
static func footfall_k(e: Empire, b: Business) -> float:
	if e.club.is_empty() or not crowd_on(e):
		return 1.0
	var p = b.premises.get("pos", null)
	if not p is Array or (p as Array).size() < 3:
		return 1.0
	var d := Vector2(float(p[0]), float(p[2])).distance_to(STADIUM)
	var r := float(cfg().get("footfall_radius", 650.0))
	if d > r:
		return 1.0
	var k := float(cfg().get("food_k", 2.1)) if b.type_id in ["cafe", "takeaway"] else float(cfg().get("footfall_k", 1.6))
	return lerpf(k, 1.0, clampf((d - r * 0.5) / (r * 0.5), 0.0, 1.0))


## A won league: every shop busier for a week.
static func trophy_k(e: Empire) -> float:
	if e.club.is_empty() or int(e.club.get("boost_until", 0)) < e.day:
		return 1.0
	return float(cfg().get("trophy_footfall", 1.12))


# --------------------------------------------------------------- money
static func wages_per_day(e: Empire) -> float:
	var c := cfg()
	var w := float(c.get("wage_base", 900)) + float(c.get("wage_per_rating", 28)) * float(e.club["rating"])
	for s in e.club.get("signings", []):
		w += float(s.get("wage", 0))
	return roundf(w)


static func capacity(e: Empire) -> int:
	return int(e.club.get("cap", cfg().get("capacity", 9000)))


static func has_upgrade(e: Empire, id: String) -> bool:
	return (e.club.get("upgrades", []) as Array).has(id)


static func ticket_def(e: Empire) -> Dictionary:
	var ts: Array = cfg().get("tickets", [])
	return ts[clampi(int(e.club.get("ticket", 1)), 0, ts.size() - 1)]


## The crowd for a home game: capacity × how good, how in form, how dear.
static func attendance(e: Empire) -> int:
	var cl := e.club
	var form_pts := 0.0
	for r in cl.get("form", []).slice(-5):
		form_pts += {"W": 1.0, "D": 0.4, "L": 0.0}.get(r, 0.0)
	var frac := 0.32 + (float(cl["rating"]) - 50.0) / 60.0 + form_pts * 0.04
	frac *= float(ticket_def(e).get("pull", 1.0))
	return int(clampf(frac, 0.2, 1.0) * capacity(e))


static func gate(e: Empire, att: int) -> float:
	var g := att * float(ticket_def(e).get("price", 14))
	for u in cfg().get("upgrades", []):
		if has_upgrade(e, String(u["id"])):
			g += float(u.get("per_match", 0.0)) + att * float(u.get("per_fan", 0.0))
	return roundf(g)


# --------------------------------------------------------------- tick
## Every game minute (Empire._minute_tick): the result at 17:00 on matchday.
static func minute(e: Empire) -> void:
	if e.club.is_empty() or not is_matchday(e) or int(e.minute) != 17 * 60:
		return
	_play(e)


static func _play(e: Empire) -> void:
	var cl := e.club
	var us: Dictionary = cl["table"][0]
	us["rating"] = float(cl["rating"])
	var opp := opponent(e)
	var home := is_home(e)
	var res := _result(e, float(cl["rating"]) + (4.0 if home else 0.0), float(opp["rating"]))
	_record(us, res[0], res[1])
	_record(opp, res[1], res[0])
	# The rest of the league plays too.
	var others: Array = (cl["table"] as Array).filter(func(t): return t != us and t != opp)
	others.shuffle()
	for i in range(0, others.size() - 1, 2):
		var a: Dictionary = others[i]
		var b: Dictionary = others[i + 1]
		var r2 := _result(e, float(a["rating"]), float(b["rating"]))
		_record(a, r2[0], r2[1])
		_record(b, r2[1], r2[0])
	var wdl := "W" if res[0] > res[1] else ("D" if res[0] == res[1] else "L")
	(cl["form"] as Array).append(wdl)
	if (cl["form"] as Array).size() > 10:
		cl["form"] = (cl["form"] as Array).slice(-10)
	cl["played"] = int(cl["played"]) + 1
	var last := {"day": e.day, "home": home, "opp": opp["name"], "gf": res[0], "ga": res[1], "att": 0, "gate": 0.0}
	if home:
		var att := attendance(e)
		last["att"] = att
		if cl["owned"]:
			var g := gate(e, att)
			last["gate"] = g
			e.company_cash += g
			cl["today"]["gate"] = float(cl["today"].get("gate", 0.0)) + g
			e._book("company", g, "club", "Gate: %s %d–%d %s" % ["Harbour City", res[0], res[1], opp["name"]])
	cl["last"] = last
	var verb := "beat" if wdl == "W" else ("drew with" if wdl == "D" else "lost to")
	e._note("Harbour City %s %s %d–%d%s" % [verb, opp["name"], res[0], res[1],
		(" in front of %s" % _thousands(int(last["att"]))) if home else " away"], "good" if wdl == "W" else "info",
		{"kind": "club"})
	if int(cl["played"]) >= int(cfg().get("season_matches", 18)):
		_end_season(e)


static func _result(e: Empire, ra: float, rb: float) -> Array:
	# Goals: Poisson-ish around 1.3, tilted by the rating gap.
	var gap := (ra - rb) / 12.0
	return [_goals(e, 1.3 + gap * 0.6), _goals(e, 1.3 - gap * 0.6)]


static func _goals(e: Empire, mean: float) -> int:
	var l := exp(-clampf(mean, 0.2, 4.0))
	var k := 0
	var p := 1.0
	while true:
		p *= e.rng.randf()
		if p <= l or k > 7:
			break
		k += 1
	return k


static func _record(t: Dictionary, gf: int, ga: int) -> void:
	t["p"] = int(t["p"]) + 1
	if gf > ga:
		t["w"] = int(t["w"]) + 1
		t["pts"] = int(t["pts"]) + 3
	elif gf == ga:
		t["d"] = int(t["d"]) + 1
		t["pts"] = int(t["pts"]) + 1
	else:
		t["l"] = int(t["l"]) + 1


static func standings(e: Empire) -> Array:
	ensure(e)
	var t: Array = (e.club["table"] as Array).duplicate()
	t.sort_custom(func(a, b): return int(a["pts"]) > int(b["pts"]) or (int(a["pts"]) == int(b["pts"]) and int(a["w"]) > int(b["w"])))
	return t


static func position(e: Empire) -> int:
	var s := standings(e)
	for i in s.size():
		if s[i].get("us", false):
			return i + 1
	return s.size()


static func _end_season(e: Empire) -> void:
	var cl := e.club
	var pos := position(e)
	var c := cfg()
	if cl["owned"]:
		var prize := maxf(float(c.get("prize_top", 120000)) - float(c.get("prize_step", 12000)) * (pos - 1), 0.0)
		e.company_cash += prize
		e._book("company", prize, "club", "Prize money: finished %s" % _ordinal(pos))
	if pos == 1:
		cl["trophies"] = int(cl["trophies"]) + 1
		cl["boost_until"] = e.day + int(c.get("trophy_days", 7))
		e._note("CHAMPIONS! Harbour City win the league – the whole city's out shopping this week.", "good", {"kind": "club"})
	else:
		e._note("Season %d over: Harbour City finish %s." % [int(cl["season"]), _ordinal(pos)], "info", {"kind": "club"})
	cl["season"] = int(cl["season"]) + 1
	cl["played"] = 0
	for t in cl["table"]:
		for k in ["p", "pts", "w", "d", "l"]:
			t[k] = 0
		if not t.get("us", false):
			t["rating"] = clampf(float(t["rating"]) + e.rng.randf_range(-3.0, 3.0), 50.0, 80.0)


## Midnight: wages, upkeep and the academy (owned); returns the day's profit.
static func settle(e: Empire) -> float:
	if e.club.is_empty():
		return 0.0
	var cl := e.club
	var profit := float(cl["today"].get("gate", 0.0))
	if cl["owned"]:
		var w := wages_per_day(e)
		var up := float(cfg().get("upkeep", 300))
		e.company_cash -= w + up
		e._book("company", -w, "wages", "Squad wages")
		e._book("company", -up, "club", "Ground upkeep")
		profit -= w + up
		if has_upgrade(e, "academy") and (e.day - 1) % 7 == 6:
			cl["rating"] = minf(float(cl["rating"]) + float(_upgrade("academy").get("weekly_rating", 0.4)), 92.0)
		cl["lifetime"]["profit"] = float(cl["lifetime"].get("profit", 0.0)) + profit
	cl["today"] = {}
	return profit if cl["owned"] else 0.0


static func _upgrade(id: String) -> Dictionary:
	for u in cfg().get("upgrades", []):
		if u["id"] == id:
			return u
	return {}


# ------------------------------------------------------------- actions
static func buy_block(e: Empire) -> String:
	ensure(e)
	if e.club["owned"]:
		return "It's yours"
	var need := int(cfg().get("requires_shops", 4))
	if e.businesses.size() < need:
		return "The board only sells to someone with %d shops (you have %d)" % [need, e.businesses.size()]
	if not e.can_afford(float(cfg().get("price", 240000))):
		return "Costs %s" % EmpireData.money(float(cfg().get("price", 240000)))
	return ""


static func buy(e: Empire) -> String:
	var why := buy_block(e)
	if why != "":
		return why
	var price := float(cfg().get("price", 240000))
	if not e.pay(price, "property", "Bought Harbour City FC"):
		return "Not enough money"
	e.club["owned"] = true
	e.club["bought_day"] = e.day
	e._note("You own Harbour City FC! Home games every other Saturday.", "good", {"kind": "club"})
	e._check_goals()
	e.changed.emit()
	return ""


static func set_ticket(e: Empire, i: int) -> void:
	e.club["ticket"] = clampi(i, 0, (cfg().get("tickets", []) as Array).size() - 1)
	e.changed.emit()


static func sign(e: Empire, id: String) -> String:
	var s := {}
	for x in cfg().get("signings", []):
		if x["id"] == id:
			s = x
	if s.is_empty() or not e.club.get("owned", false):
		return "Not available"
	if float(e.club["rating"]) + float(s["rating"]) > 95.0:
		return "The squad can't get any better"
	if not e.pay(float(s["fee"]), "club", "Signed %s" % s["name"]):
		return "Not enough money (%s)" % EmpireData.money(float(s["fee"]))
	e.club["rating"] = float(e.club["rating"]) + float(s["rating"])
	(e.club["signings"] as Array).append({"id": id, "name": s["name"], "rating": s["rating"], "fee": s["fee"], "wage": s["wage"], "day": e.day})
	e._note("Harbour City sign %s: squad rating %d." % [String(s["name"]).to_lower(), int(e.club["rating"])], "good", {"kind": "club"})
	e.changed.emit()
	return ""


## Sells the latest signing back (a share of the fee).
static func sell_last(e: Empire) -> String:
	var ss: Array = e.club.get("signings", [])
	if ss.is_empty():
		return "No signings to sell"
	var s: Dictionary = ss.pop_back()
	var back := roundf(float(s["fee"]) * float(cfg().get("sell_back", 0.55)))
	e.company_cash += back
	e._book("company", back, "club", "Sold %s" % s["name"])
	e.club["rating"] = float(e.club["rating"]) - float(s["rating"])
	e.changed.emit()
	return ""


static func buy_upgrade(e: Empire, id: String) -> String:
	var u := _upgrade(id)
	if u.is_empty() or has_upgrade(e, id) or not e.club.get("owned", false):
		return "Not available"
	if not e.pay(float(u["cost"]), "club", "%s at the ground" % u["name"]):
		return "Not enough money (%s)" % EmpireData.money(float(u["cost"]))
	(e.club["upgrades"] as Array).append(id)
	if u.has("capacity"):
		e.club["cap"] = capacity(e) + int(u["capacity"])
	e._note("%s at The Heights Ground." % u["name"], "good", {"kind": "club"})
	e.changed.emit()
	return ""


static func value(e: Empire) -> float:
	if e.club.is_empty() or not e.club.get("owned", false):
		return 0.0
	var v := float(cfg().get("price", 240000))
	for s in e.club.get("signings", []):
		v += float(s["fee"]) * float(cfg().get("sell_back", 0.55))
	for id in e.club.get("upgrades", []):
		v += float(_upgrade(String(id)).get("cost", 0.0)) * 0.5
	return v


static func _ordinal(n: int) -> String:
	var s := "th"
	if n % 100 < 11 or n % 100 > 13:
		s = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, s]


static func _thousands(n: int) -> String:
	var s := str(n)
	return s if n < 1000 else "%s,%s" % [s.substr(0, s.length() - 3), s.substr(s.length() - 3)]
