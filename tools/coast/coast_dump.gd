extends SceneTree
## Every coastline in WORLD metres, for the coast audit (views, top-down map):
##   godot --headless -s res://tools/coast/coast_dump.gd -- <out.json>
## {commercial: [[x,z]...], westbank: [...], skyport: [[x,z,kind]...],
##  landforms: [{name, poly: [[x,z,kind]...]}]}

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "coasts.json"
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var layout := CityLayout.new().generate()
	var pts := func(poly: PackedVector2Array) -> Array:
		var a: Array = []
		for v in poly:
			a.append([snappedf(v.x, 0.1), snappedf(v.y, 0.1)])
		return a
	var sky: Array = []
	var o := SkyportIsland.outline()
	for i in o.size():
		var q := SkyportIsland.w2(o[i])
		sky.append([snappedf(q.x, 0.1), snappedf(q.y, 0.1), SkyportIsland.shore_kind(i)])
	var lf: Array = []
	for f: Dictionary in Landforms.forms(layout):
		var p: Array = []
		var poly: PackedVector2Array = f["poly"]
		var kinds: PackedByteArray = f["kinds"]
		for i in poly.size():
			p.append([snappedf(poly[i].x, 0.1), snappedf(poly[i].y, 0.1), kinds[i]])
		lf.append({"name": f["name"], "poly": p, "side": f["side"]})
	var heights: Array = []
	for L: CityLayout in [layout, layout.mainland]:
		var hs: Array = []
		for v in L.coast:
			hs.append(snappedf(L.terrain.road_y(v.x, v.y), 0.01))
		heights.append(hs)
	var d := {"commercial": pts.call(layout.coast), "westbank": pts.call(layout.mainland.coast),
		"commercial_h": heights[0], "westbank_h": heights[1], "skyport": sky, "landforms": lf,
		"river_edge": CityLayout.RIVER_EDGE, "far_shore": CityLayout.FAR_SHORE}
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_string(JSON.stringify(d))
	fa.close()
	print("COAST_DUMP ", out, " commercial ", layout.coast.size(), " westbank ", layout.mainland.coast.size(), " skyport ", sky.size(), " landforms ", lf.size())
	quit()
