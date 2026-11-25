extends SceneTree
## Heights across a landform's join with the city (x sweep at a given z):
##   godot --headless -s res://tools/world/seam_probe.gd -- <z> [x0 x1]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var z := float(a[0]) if a.size() > 0 else 500.0
	var x0 := float(a[1]) if a.size() > 1 else 20.0
	var x1 := float(a[2]) if a.size() > 2 else 40.0
	Landforms.enabled = true
	SkyportIsland.enabled = true
	var L := CityLayout.new().generate()
	Landforms.forms(L)
	var x := x0
	while x <= x1:
		var lf := Landforms.ground_y(x, z)
		var gy := L.ground_y(x, z)
		var ry := L.terrain.road_y(x, z) if L.terrain else NAN
		print("SEAM x %.1f  layout.ground_y %.3f  road_y %.3f  landform %.3f  water %s  in_coast %s" % [x, gy, ry, lf,
			L.is_water(Vector3(x, 0, z)), Geometry2D.is_point_in_polygon(Vector2(x, z), L.coast)])
		x += 0.5
	for g in Landforms.rail_gaps():
		print("SEAM gap ", g)
	quit()
