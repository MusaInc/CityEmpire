extends SceneTree
## Dumps both cities' road fields and ground plan for tools/roads/paint_map.py:
##   <dir>/<island>_field.f32   field_h × field_w × 4 float32 (CityRoads._sample)
##   <dir>/<island>.json        rect, cell, coast, blocks (poly, holes, kind),
##                              roads (pts, w, kind, name), roundabouts
##   godot --headless -s res://tools/roads/dump_field.gd -- <dir>
func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	SkyportIsland.enabled = true
	var layout := CityLayout.new().generate()
	_dump(layout, dir + "/island")
	if layout.mainland != null:
		_dump(layout.mainland, dir + "/westbank")
	quit()


static func _poly(p: PackedVector2Array) -> Array:
	var o: Array = []
	for q in p:
		o.append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
	return o


func _dump(L: CityLayout, base: String) -> void:
	var R := L.roads
	var f := FileAccess.open(base + "_field.f32", FileAccess.WRITE)
	f.store_buffer(R.field.to_byte_array())
	var meta := {"rect": [R.field_rect.position.x, R.field_rect.position.y], "cell": R.field_cell,
		"w": R.field_w, "h": R.field_h, "coast": _poly(R.coast), "blocks": [], "roads": [], "roundabouts": []}
	for b in L.blocks:
		var holes: Array = []
		for h in b.get("holes", []):
			holes.append(_poly(h))
		meta["blocks"].append({"poly": _poly(b["poly"]), "holes": holes, "kind": b["kind"],
			"level": 0.0 if is_nan(float(b.get("level", NAN))) else float(b["level"])})
	for r in R.roads:
		meta["roads"].append({"pts": _poly(r["pts"]), "w": r["w"], "kind": r["kind"], "name": r.get("name", ""),
			"ring": r.get("ring", false), "loop": r.get("loop", false)})
	for rb in R.roundabouts:
		meta["roundabouts"].append({"c": [rb["c"].x, rb["c"].y], "r": rb["r"], "w": rb["w"]})
	var j := FileAccess.open(base + ".json", FileAccess.WRITE)
	j.store_string(JSON.stringify(meta))
