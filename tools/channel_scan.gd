extends SceneTree
## Narrow-water scan over the BUILT world (all three islands + landforms;
## collision = what's drawn): sea samples on a grid with land a few metres
## away on BOTH sides along one axis are slivers of water between two pieces
## of land – the gap between a promenade and a park that should meet.
## Writes a land/sea raster; tools/channel_find.py finds and clusters them.
##   godot --headless -s res://tools/channel_scan.gd -- --step=2 <out.bin>
##   python3 tools/channel_find.py <out.bin>

const SEA := -1.6


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var step := 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.get_slice("=", 1))
	CityWorld.walker_crowd_radius = 0.0
	SkyportIsland.enabled = true
	Landforms.enabled = true
	var world = load("res://src/world/city_world.gd").new()
	root.add_child(world)
	Venues.register()
	var sky := SkyportIsland.new()
	root.add_child(sky)
	sky.build(world.layout, world)
	var lf := Landforms.new()
	root.add_child(lf)
	lf.build(world.layout)
	for i in 4:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var hit_at := func(x: float, z: float) -> Dictionary:
		var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -40.0, z))
		return space.intersect_ray(rq)
	# Rasterise: 0 sea, 1 land (top > 0.3 m), 2 in between (shore slopes).
	var x0 := -1500.0
	var z0 := -900.0
	var nx := int(4100.0 / step)
	var nz := int(2800.0 / step)
	var grid := PackedByteArray()
	grid.resize(nx * nz)
	for j in nz:
		for i in nx:
			var h: Dictionary = hit_at.call(x0 + i * step, z0 + j * step)
			var y := float((h["position"] as Vector3).y) if not h.is_empty() else -99.0
			grid[j * nx + i] = 0 if y < SEA + 0.25 else (1 if y > 0.3 else 2)
	var out := OS.get_cmdline_user_args()[-1] if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[-1].ends_with(".bin") else "user://channels.bin"
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_32(nx)
	fa.store_32(nz)
	fa.store_float(x0)
	fa.store_float(z0)
	fa.store_float(step)
	fa.store_buffer(grid)
	fa.close()
	print("CHANNEL_GRID %dx%d at %.1f m -> %s" % [nx, nz, step, out])
	quit()
