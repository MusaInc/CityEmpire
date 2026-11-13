class_name Stock
extends RefCounted
## A container of goods: product id -> units. Every place goods can be is a
## Stock (a wholesaler's collection pallet, a vehicle's load space, the shop's
## back room, the case in your hands), and goods only ever move between
## them through transfer(), so units can't be duplicated or lost: the sum
## over every container plus what was sold or stolen always equals what was
## bought (tests/test_economy.gd checks it).
##
## Capacity is counted in cases, the way you'd load a van: each product
## takes ceil(units / case size) cases of room.

var units := {}
## Max cases this container holds (<= 0: unlimited).
var case_capacity := 0
var label := ""


func _init(p_capacity := 0, p_label := "") -> void:
	case_capacity = p_capacity
	label = p_label


func qty(id: String) -> int:
	return int(units.get(id, 0))


func total_units() -> int:
	var n := 0
	for id in units:
		n += int(units[id])
	return n


func is_empty() -> bool:
	return total_units() == 0


## Cases of room the contents take.
func cases_used() -> int:
	var n := 0
	for id in units:
		n += cases_for(id, int(units[id]))
	return n


static func cases_for(id: String, n: int) -> int:
	if n <= 0:
		return 0
	var c := EmpireData.case_qty(id)
	return int(ceil(float(n) / float(maxi(c, 1))))


## How many units of `id` still fit (fills the open case first).
func room_for(id: String) -> int:
	if case_capacity <= 0:
		return 1 << 30
	var c := maxi(EmpireData.case_qty(id), 1)
	var have := qty(id)
	var free_cases := case_capacity - cases_used()
	var open_room := (cases_for(id, have) * c - have) if have > 0 else 0
	return maxi(open_room + maxi(free_cases, 0) * c, 0)


## Moves up to `n` units of `id` from `src` into `dst`; returns how many moved
## (limited by what src has and what dst can hold).
static func transfer(src: Stock, dst: Stock, id: String, n: int) -> int:
	if n <= 0 or src == null or dst == null or src == dst:
		return 0
	var moved := mini(mini(n, src.qty(id)), dst.room_for(id))
	if moved <= 0:
		return 0
	src._add(id, -moved)
	dst._add(id, moved)
	return moved


## Moves everything that fits; returns {id: units moved}.
static func transfer_all(src: Stock, dst: Stock) -> Dictionary:
	var out := {}
	for id in src.units.keys():
		var m := transfer(src, dst, id, src.qty(id))
		if m > 0:
			out[id] = m
	return out


## Goods entering the economy (bought from a wholesaler) or leaving it (sold,
## stolen, spoiled). Only the Empire's bookkeeping calls these, so the
## conservation counters stay complete.
func create(id: String, n: int) -> void:
	if n > 0:
		_add(id, n)


func destroy(id: String, n: int) -> int:
	var d := mini(n, qty(id))
	if d > 0:
		_add(id, -d)
	return d


func _add(id: String, n: int) -> void:
	var v := qty(id) + n
	if v <= 0:
		units.erase(id)
	else:
		units[id] = v


func to_dict() -> Dictionary:
	return {"units": units.duplicate(), "cap": case_capacity, "label": label}


static func from_dict(d: Dictionary) -> Stock:
	var s := Stock.new(int(d.get("cap", 0)), String(d.get("label", "")))
	var u: Dictionary = d.get("units", {})
	for id in u:
		if int(u[id]) > 0 and EmpireData.products().has(id):
			s.units[String(id)] = int(u[id])
	return s
