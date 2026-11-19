extends SceneTree
## Landform seam audit: where does a headland park (Landforms) run alongside
## its island with a strip of sea between them? From every outline point of
## every landform, look straight out (away from the landform) up to REACH m:
## city land within that distance across water is a channel – the grass ends
## in a shore, then sea, then the city's promenade. Prints each stretch with
## its narrowest gap.
##   godot --headless -s res://tools/landform_gap_audit.gd

const REACH := 30.0


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var layout := CityLayout.new().generate()
	var forms: Array = Landforms.forms(layout)
	var total := 0
	for f: Dictionary in forms:
		var L: CityLayout = f["L"]
		var poly: PackedVector2Array = f["poly"]
		var kinds: PackedByteArray = f["kinds"]
		var n := poly.size()
		var run: Array = []
		var runs: Array = []
		for i in n:
			var a := poly[(i - 1 + n) % n]
			var b := poly[(i + 1) % n]
			var tg := (b - a).normalized()
			var nv := Vector2(tg.y, -tg.x)
			# Outward = the side that isn't in the landform.
			if Geometry2D.is_point_in_polygon(poly[i] + nv * 0.6, poly):
				nv = -nv
			var gap := -1.0
			var seen_water := false
			var d := 0.5
			while d <= REACH:
				var q := poly[i] + nv * d
				if Geometry2D.is_point_in_polygon(q, poly):
					break   # (the outline folds back: a bay of its own)
				Landforms.enabled = false
				var water := L.is_water(Vector3(q.x, 0.0, q.y)) if L != null else true
				Landforms.enabled = true
				if water:
					seen_water = true
				elif seen_water:
					gap = d
					break
				else:
					break   # city land right at the edge: joined, fine
				d += 0.5
			if gap > 0.0:
				run.append([i, gap, kinds[i], poly[i]])
			elif not run.is_empty():
				runs.append(run)
				run = []
		if not run.is_empty():
			runs.append(run)
		for r: Array in runs:
			if r.size() < 2:
				continue
			var narrow: Array = r[0]
			for e: Array in r:
				if e[1] < narrow[1]:
					narrow = e
			var p0: Vector2 = r[0][3]
			var p1: Vector2 = r[-1][3]
			total += 1
			print("GAP %s: %d outline points from (%.0f, %.0f) to (%.0f, %.0f), narrowest %.1f m of water at (%.0f, %.0f), kind %d" % [
				f["name"], r.size(), p0.x, p0.y, p1.x, p1.y, narrow[1], narrow[3].x, narrow[3].y, narrow[2]])
	print("LANDFORM_GAPS %d channels between landforms and their islands" % total)
	quit()
