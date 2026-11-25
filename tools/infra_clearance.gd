extends SceneTree
## Elevated-infrastructure clearance audit (2026-11-25 overhaul): every
## traffic lane on Commercial Island and Westbank (junction connectors and
## turning lanes included) against every solid the city's structures and
## kits put up – bridge and viaduct piers, rail columns, crossheads, towers.
## A lane's driving envelope is 2.4 m wide and 4.6 m tall (buses, box vans);
## anything inside it is reported:
##   column     a solid reaching down below 2.8 m over the lane (a pier in
##              the carriageway: cars hit it)
##   headroom   a solid between 2.8 and 4.6 m (a low girder or crosshead)
## Each obstacle is reported once (nearest lane point).
##
##   godot --headless -s res://tools/infra_clearance.gd -- [out.json]

const HALF_W := 1.2
const TALL := 4.6
const LOW := 2.8


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	SkyportIsland.enabled = true
	var layout := CityLayout.new().generate()
	var net := RoadNet.new().build(layout)
	var obs: Array = []   # [Transform3D, half extents Vector3, what]
	for L: CityLayout in [layout, layout.mainland]:
		if L == null:
			continue
		for b: Dictionary in L.buildings:
			if b.get("kind", "") != "structure":
				continue
			for t: Array in b["tiers"]:
				var c := Vector3((t[0] + t[2]) * 0.5, (t[4] + t[5]) * 0.5, (t[1] + t[3]) * 0.5)
				var h := Vector3((t[2] - t[0]) * 0.5, (t[5] - t[4]) * 0.5, (t[3] - t[1]) * 0.5)
				obs.append([Transform3D(Basis.IDENTITY, c), h, "box"])
		for list: Array in [L.kit_obbs, L.kit_obbs_solid]:
			for ob: Array in list:
				var xf: Transform3D = ob[0]
				var sz: Vector3 = ob[1]
				# beam_basis scales? keep unit axes + half extents.
				obs.append([Transform3D(xf.basis.orthonormalized(), xf.origin), sz * 0.5, "kit"])
	print("INFRA obstacles %d, lanes %d" % [obs.size(), net.lanes.size()])
	# Spatial hash of obstacles by 8 m cells (their xz AABB).
	var grid := {}
	for i in obs.size():
		var xf: Transform3D = obs[i][0]
		var h: Vector3 = obs[i][1]
		var ext := absf(xf.basis.x.x) * h.x + absf(xf.basis.y.x) * h.y + absf(xf.basis.z.x) * h.z
		var ezt := absf(xf.basis.x.z) * h.x + absf(xf.basis.y.z) * h.y + absf(xf.basis.z.z) * h.z
		for cx in range(floori((xf.origin.x - ext) / 8.0), floori((xf.origin.x + ext) / 8.0) + 1):
			for cz in range(floori((xf.origin.z - ezt) / 8.0), floori((xf.origin.z + ezt) / 8.0) + 1):
				var k := Vector2i(cx, cz)
				if not grid.has(k):
					grid[k] = []
				(grid[k] as Array).append(i)
	var hits := {}   # obstacle index -> {kind, at, lane, conn}
	for li in net.lanes.size():
		var lp: PackedVector3Array = net.lanes[li]
		for i in lp.size():
			var p := lp[i]
			var cand: Array = grid.get(Vector2i(floori(p.x / 8.0), floori(p.z / 8.0)), [])
			if cand.is_empty():
				continue
			var d := net.lane_dir(li, i * RoadNet.STEP)
			var side := Vector3(-d.z, 0.0, d.x)
			for oi: int in cand:
				if hits.has(oi):
					continue
				var xf: Transform3D = obs[oi][0]
				var h: Vector3 = obs[oi][1]
				var low := INF
				for sx: float in [-HALF_W, 0.0, HALF_W]:
					for along: float in [-1.5, 0.0, 1.5]:
						for hy: float in [0.5, 1.4, 2.2, 3.0, 3.8, 4.5]:
							var q := p + side * sx + d * along + Vector3.UP * hy
							var l := xf.affine_inverse() * q
							if absf(l.x) <= h.x and absf(l.y) <= h.y and absf(l.z) <= h.z:
								low = minf(low, hy)
				if low < INF:
					hits[oi] = {"kind": "column" if low < LOW else "headroom", "at": [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)],
						"lane": li, "conn": net.lane_conn[li] == 1, "what": obs[oi][2],
						"obs": [snappedf(xf.origin.x, 0.1), snappedf(xf.origin.y, 0.1), snappedf(xf.origin.z, 0.1)], "half": [h.x, h.y, h.z]}
	var counts := {}
	for k in hits:
		var e: Dictionary = hits[k]
		var key := "%s%s" % [e["kind"], "/junction" if e["conn"] else ""]
		counts[key] = int(counts.get(key, 0)) + 1
		print("  %s %s lane %d at %s obstacle %s half %s" % [key, e["what"], e["lane"], e["at"], e["obs"], e["half"]])
	print("INFRA_CLEARANCE ", JSON.stringify(counts), " total ", hits.size())
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(hits.values(), " "))
	quit()
