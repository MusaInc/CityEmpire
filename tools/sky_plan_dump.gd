extends SceneTree
## Skyport plan as JSON (LOCAL coordinates) for layout work and review:
## outline, roads, buildings (footprints), areas, strips, sites, stands,
## helipads, link path, rail.  godot --headless -s res://tools/sky_plan_dump.gd -- out.json
func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	var args := OS.get_cmdline_user_args()
	SkyportIsland.enabled = true
	var layout := CityLayout.new().generate()
	var P := SkyportIsland.plan(layout)
	var v2 := func(v) -> Array: return [snappedf(v.x, 0.1), snappedf(v.z if v is Vector3 else v.y, 0.1)]
	var out := {"outline": [], "roads": [], "buildings": [], "areas": [], "strips": [], "sites": {}, "stands": [], "helipads": [], "link": [], "rail": []}
	for p in SkyportIsland.outline():
		out["outline"].append(v2.call(p))
	for r in P["roads"]:
		var pts: Array = []
		for p in (r[1] as PackedVector3Array):
			pts.append(v2.call(p))
		out["roads"].append({"name": r[0], "pts": pts, "w": r[2]})
	for b in P["buildings"]:
		var t: Array = b["tiers"][0]
		out["buildings"].append({"r": [t[0], t[1], t[2], t[3]], "h": float(b["tiers"][-1][5]) - SkyportIsland.LAND_Y, "kind": b.get("kind", ""), "district": b.get("district", "")})
	for a in P["areas"]:
		var pts: Array = []
		for p in (a[1] as PackedVector2Array):
			pts.append(v2.call(p))
		out["areas"].append({"kind": a[0], "pts": pts})
	for s in P["strips"]:
		out["strips"].append({"kind": s[0], "a": v2.call(s[1]), "b": v2.call(s[2]), "hw": s[3]})
	for k in P["sites"]:
		out["sites"][k] = {"door": v2.call(P["sites"][k]["door"]), "name": P["sites"][k]["name"]}
	for s in P["stands"]:
		out["stands"].append(v2.call(s[0]))
	for h in P["helipads"]:
		out["helipads"].append(v2.call(h))
	for p in SkyportAirport.link_path():
		out["link"].append(v2.call(p))
	for ln in P.get("rail", []):
		var pts: Array = []
		for p in (ln["pts"] as PackedVector3Array):
			pts.append(v2.call(SkyportIsland.l(p)))
		out["rail"].append({"name": ln["name"], "pts": pts})
	# World-space context: both cities' coasts and the City Loop.
	out["w_coast_island"] = []
	for p in layout.coast:
		out["w_coast_island"].append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	out["w_coast_mainland"] = []
	if layout.mainland:
		for p in layout.mainland.coast:
			out["w_coast_mainland"].append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	out["w_city_loop"] = []
	for ln in layout.rail.lines:
		var pts: PackedVector3Array = ln["pts"]
		for i in range(0, pts.size(), 10):
			out["w_city_loop"].append([snappedf(pts[i].x, 0.1), snappedf(pts[i].z, 0.1), snappedf(pts[i].y, 0.1)])
		out["w_city_stations"] = []
		for st in ln["stations"]:
			var q := pts[int(float(st) / RailNetwork.STEP) % pts.size()]
			out["w_city_stations"].append([snappedf(q.x, 0.1), snappedf(q.z, 0.1)])
	out["w_outline"] = []
	for p in SkyportIsland.world_outline():
		out["w_outline"].append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	out["w_bridges"] = []
	for B in P["bridges"]:
		var pts: Array = []
		for q in (B["pts"] as PackedVector3Array):
			pts.append([snappedf(q.x, 0.1), snappedf(q.z, 0.1)])
		out["w_bridges"].append(pts)
	var f := FileAccess.open(args[0] if args.size() > 0 else "sky.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit()
