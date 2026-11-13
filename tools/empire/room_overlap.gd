extends SceneTree
## Debug: other buildings / kit / props whose boxes reach into each shop room.
func _initialize() -> void:
	var L := CityLayout.new().generate()
	for P: Premises in [L.mainland.premises, L.premises]:
		var lay: CityLayout = L.mainland if P == L.mainland.premises else L
		for u in P.units:
			var xf := Premises.room_xf(u)
			var sz := Premises.room_size(u)
			var inv := xf.affine_inverse()
			var n := 0
			var kinds := {}
			for b in lay.buildings:
				if b == u["b"]:
					continue
				for t in b["tiers"]:
					var box := CityLayout.tier_aabb(b, t)
					# sample the box against the room (corners + centre in room space)
					var hit := false
					for fx in 5:
						for fz in 5:
							for fy in 3:
								var p := box.position + box.size * Vector3((fx + 0.5) / 5.0, (fy + 0.5) / 3.0, (fz + 0.5) / 5.0)
								var q := inv * p
								if q.x > 0.1 and q.x < sz.x - 0.1 and q.z < -0.1 and q.z > -sz.z + 0.1 and q.y > 0.0 and q.y < sz.y:
									hit = true
					# and the room's points inside the box
					for fx in 6:
						for fz in 6:
							var r := xf * Vector3(sz.x * (fx + 0.5) / 6.0, 1.0, -sz.z * (fz + 0.5) / 6.0)
							if CityLayout.inside(b, r):
								hit = true
					if hit:
						n += 1
						kinds[b["kind"]] = true
						break
			print("%-22s overlapping buildings: %d %s" % [u["id"], n, kinds.keys()])
	quit()
