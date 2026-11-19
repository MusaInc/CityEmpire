extends SceneTree
## Landform seams on the BUILT world (collision = what's drawn): from every
## outline point of every landform, ray down at points stepping straight out
## from it. Sea right at the landform's edge and then the city's land again
## within REACH m is a channel of water between a headland park and the
## promenade (landform_gap_audit.gd checks the plan; this checks the meshes).
##   godot --headless -s res://tools/landform_seam_probe.gd

const REACH := 30.0
const SEA := -1.6


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	CityWorld.walker_crowd_radius = 0.0
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var world = load("res://src/world/city_world.gd").new()
	root.add_child(world)
	var lf := Landforms.new()
	root.add_child(lf)
	lf.build(world.layout)
	for i in 4:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	# (The landforms' own bodies – their shore slopes reach past the outline
	# – are left out: only the city's land counts as "land again".)
	var mine: Array[RID] = []
	for c in lf.find_children("*", "CollisionObject3D", true, false):
		mine.append((c as CollisionObject3D).get_rid())
	var top := func(q: Vector2) -> float:
		var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 300.0, q.y), Vector3(q.x, -40.0, q.y))
		rq.exclude = mine
		var hit := space.intersect_ray(rq)
		return float((hit["position"] as Vector3).y) if not hit.is_empty() else -INF
	var total := 0
	for f: Dictionary in Landforms.forms():
		var poly: PackedVector2Array = f["poly"]
		var n := poly.size()
		var run: Array = []
		var runs: Array = []
		for i in n:
			var a := poly[(i - 1 + n) % n]
			var b := poly[(i + 1) % n]
			var tg := (b - a).normalized()
			var nv := Vector2(tg.y, -tg.x)
			if Geometry2D.is_point_in_polygon(poly[i] + nv * 0.6, poly):
				nv = -nv
			var water := 0.0
			var gap := -1.0
			var d := 0.5
			while d <= REACH:
				var y: float = top.call(poly[i] + nv * d)
				if y < SEA + 0.25:
					water += 0.5
				elif water >= 1.0 and y > 0.3:
					gap = water
					break
				elif water < 1.0 and d > 2.0:
					break   # the city's land right at the edge: joined
				d += 0.5
			if gap > 0.0:
				run.append([i, gap, poly[i], d])
			elif not run.is_empty():
				runs.append(run)
				run = []
		if not run.is_empty():
			runs.append(run)
		for r: Array in runs:
			var wide: Array = r[0]
			for e: Array in r:
				if e[1] > wide[1]:
					wide = e
			total += 1
			print("SEAM %s: %d points (%.0f, %.0f) .. (%.0f, %.0f): up to %.1f m of water before land, at (%.0f, %.0f)" % [
				f["name"], r.size(), r[0][2].x, r[0][2].y, r[-1][2].x, r[-1][2].y, wide[1], wide[2].x, wide[2].y])
	print("LANDFORM_SEAMS %d" % total)
	quit()
