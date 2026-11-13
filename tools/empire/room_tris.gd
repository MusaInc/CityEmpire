extends SceneTree
## Debug: triangles of a shop's building mesh (detailed) that fall inside the room.
func _initialize() -> void:
	var L := CityLayout.new().generate()
	var u: Dictionary = {}
	for x in L.mainland.premises.units:
		if x["id"] == "shop_-519_15":
			u = x
	var b: Dictionary = u["b"]
	var m := BuildingMesher.new()
	m._begin(b)
	m.add_building(b, true)
	m._end()
	var a := m.arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var inv := Premises.room_xf(u).affine_inverse()
	var sz := Premises.room_size(u)
	var count := 0
	for i in range(0, v.size(), 3):
		var c := (v[i] + v[i + 1] + v[i + 2]) / 3.0
		var q := inv * c
		if q.x > 0.2 and q.x < sz.x - 0.2 and q.z < -0.4 and q.z > -sz.z + 0.2 and q.y > -0.5 and q.y < sz.y - 0.1:
			count += 1
			if count < 25:
				print("tri local=", q, " n=", n[i], " v0=", v[i])
	print("inside tris: ", count, " / ", v.size() / 3, "  base=", BuildingMesher.base_of(b), " tiers=", b["tiers"], " rot=", b.get("rot", 0.0))
	quit()
