class_name Staff
extends RefCounted
## Employees: generated candidates (name, role, skill 1-5, traits, hourly
## wage), and what an employee gets done in a span of shift time. Effects
## are applied by Empire's minute tick both for the shop you're in and the
## shops you're not (the 3-D staff in ShopFloor are where those effects are
## seen happening).


## How many people are looking for work on a given day (config staff.json
## "daily_seekers"): plenty, so every role has a choice.
static func daily_count() -> int:
	return int(EmpireData.file("staff").get("daily_seekers", 18))


## The day's job seekers: at least `per_role` of every role (the cheap, the
## keen and the experienced), then a random mix; best first within a role.
static func candidates(day: int, seed: int, count := -1) -> Array:
	if count < 0:
		count = daily_count()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, day, "staff"])
	var roles := EmpireData.roles().keys()
	var per_role := mini(int(EmpireData.file("staff").get("per_role", 3)), maxi(count / maxi(roles.size(), 1), 1))
	var out: Array = []
	for i in count:
		# Every day's list covers each role a few times over.
		var role: String = roles[i % roles.size()] if i < roles.size() * per_role else roles[rng.randi() % roles.size()]
		out.append(make(rng, role, day, i))
	return out


static func make(rng: RandomNumberGenerator, role: String, day: int, n: int) -> Dictionary:
	var sd := EmpireData.file("staff")
	var first: Array = sd.get("first_names", ["Sam"])
	var last: Array = sd.get("last_names", ["Smith"])
	var skill := clampi(int(round(rng.randfn(2.8, 1.0))), 1, 5)
	var trait_ids: Array = (sd.get("traits", {}) as Dictionary).keys()
	var traits: Array = []
	if rng.randf() < 0.75:
		traits.append(trait_ids[rng.randi() % trait_ids.size()])
	var e := {"id": "e%d_%d_%d" % [day, n, rng.randi() % 100000], "name": "%s %s" % [first[rng.randi() % first.size()],
		last[rng.randi() % last.size()]], "role": role, "skill": skill, "traits": traits, "xp": 0.0,
		"hired_day": 0, "business": "", "look": rng.randi()}
	e["wage"] = wage_for(e)
	return e


static func wage_for(e: Dictionary) -> float:
	var base := float(EmpireData.role(e["role"]).get("wage", 10.0))
	var k := lerpf(0.8, 1.25, (float(e["skill"]) - 1.0) / 4.0)
	for t in e.get("traits", []):
		k += float(EmpireData.trait_info(t).get("wage", 0.0))
	return snappedf(base * k, 0.05)


static func has_trait(e: Dictionary, trait_id: String) -> bool:
	return (e.get("traits", []) as Array).has(trait_id)


## Work rate multiplier: skill 3 = 1.0, with traits.
## "punctual" boosts shift throughput +5% (never loses early-morning minutes).
static func speed(e: Dictionary) -> float:
	var k := lerpf(0.7, 1.35, (float(e["skill"]) - 1.0) / 4.0)
	for t in e.get("traits", []):
		k += float(EmpireData.trait_info(t).get("speed", 0.0))
	if has_trait(e, "punctual"):
		k += 0.05
	return maxf(k, 0.3)


## Grants a modest raise to an employee and returns the new hourly wage.
static func give_raise(e: Dictionary, pct := 0.08) -> float:
	var next := snappedf(float(e.get("wage", wage_for(e))) * (1.0 + pct), 0.05)
	e["wage"] = maxf(next, wage_for(e))
	e["raised_at"] = int(e.get("skill", 1))
	return float(e["wage"])


## True when an ambitious employee at skill 4+ is well-paid (at or above market wage).
static func is_ambitious_star(e: Dictionary) -> bool:
	return has_trait(e, "ambitious") and int(e.get("skill", 1)) >= 4 and float(e.get("wage", 0.0)) >= wage_for(e) - 0.01


## Shoppers a cashier can serve per hour.
static func serve_rate(e: Dictionary) -> float:
	return float(EmpireData.role("cashier").get("rate", 40)) * speed(e)


static func trait_names(e: Dictionary) -> String:
	var n: Array = []
	for t in e.get("traits", []):
		n.append(String(EmpireData.trait_info(t).get("name", t)))
	return ", ".join(n)


## Skill grows with hours worked (ambitious staff twice as fast), up to 5.
static func gain_xp(e: Dictionary, hours: float) -> bool:
	var g := 1.0
	for t in e.get("traits", []):
		g += float(EmpireData.trait_info(t).get("growth", 0.0))
	e["xp"] = float(e.get("xp", 0.0)) + hours * g
	if int(e["skill"]) < 5 and float(e["xp"]) >= 60.0 * float(e["skill"]):
		e["xp"] = 0.0
		e["skill"] = int(e["skill"]) + 1
		return true
	return false
