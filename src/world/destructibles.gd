class_name Destructibles
extends Node3D
## Street furniture cars knock flying (NEVER STOP's system, 2026-11-21):
## street lights, traffic lights, sign posts, bins, benches, hydrants,
## bollards, utility boxes, crates and trees. A tree costs the most speed and
## topples over the bonnet. Bus shelters, planters and parked cars are solid
## (CityWorld.SOLID_LAYER): you crash into those (parked cars become wrecks).
##  * A spatial hash of every breakable item, built from the lists the city
##    draws (CityWorld.chunk_props / chunk_furniture).
##  * Each physics frame every moving car from `cars_fn` checks the items in
##    its cells against its footprint; a hit removes the item from drawing and
##    collision (CityWorld.break_item + a throttled chunk refresh) and throws a
##    physical copy with the car's momentum. The car loses a little speed.
##    A street light takes its district banner with it.
##  * Thrown pieces are pooled by budget and cleaned up after a while.
## Session only: the city is put right overnight (nothing is saved).

signal broke(kind: String, at: Vector3, by: Car)

const BREAKABLE := ["streetlight", "traffic_light", "sign_post", "bench", "bin", "hydrant", "bollard", "tree", "tree_tall",
	"utility_box", "crates"]
const TALL := ["streetlight", "traffic_light", "sign_post"]   # topple over the car's nose
const CELL := 8.0
const SLOW := {"streetlight": 0.92, "traffic_light": 0.9, "sign_post": 0.97, "bench": 0.95, "bin": 0.98,
	"hydrant": 0.95, "bollard": 0.93, "utility_box": 0.9, "crates": 0.97}

var cars_fn := Callable()     # () -> Array[Car]: the cars that can break things
var budget := 24
var _grid := {}        # Vector2i -> Array of [kind, Transform3D, chunk key, CityWorld]
var _banners := {}     # Vector2i (lamp xz * 2) -> [[Transform3D, chunk key, CityWorld]]
var _pieces: Array = []  # [RigidBody3D, age]
var _dirty := {}       # [CityWorld, chunk key] -> seconds until refresh
var _meshes := {}
var _rng := RandomNumberGenerator.new()


func setup(world: CityWorld) -> void:
	var st := get_node_or_null("/root/Settings")
	if st and st.has_method("preset"):
		budget = int(st.preset().get("debris", 48) / 2)
	_index(world)
	if world.mainland:
		_index(world.mainland)


func _index(w: CityWorld) -> void:
	for key in w._all_keys:
		for it in w.chunk_props(key) + w.chunk_furniture(key):
			var kind: String = it[0]
			var xf: Transform3D = it[1]
			if kind.begins_with("banner_"):
				var bk := Vector2i(roundi(xf.origin.x * 2.0), roundi(xf.origin.z * 2.0))
				if not _banners.has(bk):
					_banners[bk] = []
				(_banners[bk] as Array).append([xf, key, w])
				continue
			if not (kind in BREAKABLE or kind.begins_with("tree_")):
				continue
			var c := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
			if not _grid.has(c):
				_grid[c] = []
			(_grid[c] as Array).append([kind, xf, key, w])


func count() -> int:
	var n := 0
	for c in _grid:
		n += (_grid[c] as Array).size()
	return n


func _physics_process(dt: float) -> void:
	if cars_fn.is_valid():
		for o in cars_fn.call():
			var c := o as Car
			# Low threshold: nothing breakable is solid to cars, so one creeping
			# into a lamp post still knocks it (it would pass through otherwise).
			if c == null or not is_instance_valid(c) or c.freeze or not c.visible or c.speed < 1.0:
				continue
			_check(c)
	for k in _dirty.keys():
		_dirty[k] -= dt
		if _dirty[k] <= 0.0:
			var w: CityWorld = k[0]
			if is_instance_valid(w):
				w.refresh_props(k[1])
			_dirty.erase(k)
	var keep: Array = []
	for p in _pieces:
		p[1] += dt
		if p[1] > 12.0:
			(p[0] as Node).queue_free()
		else:
			keep.append(p)
	_pieces = keep


func _check(car: Car) -> void:
	var p := car.global_position
	var size: Vector3 = car.spec["size"]
	var hw := size.x * 0.5 + 0.25
	var hl := size.z * 0.5 + 0.25
	var inv := car.global_transform.affine_inverse()
	var c0 := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var cell: Array = _grid.get(c0 + Vector2i(dx, dz), [])
			if cell.is_empty():
				continue
			for i in range(cell.size() - 1, -1, -1):
				var it: Array = cell[i]
				var xf: Transform3D = it[1]
				var l := inv * xf.origin
				# Height in world terms: a car pitched up a kerb would otherwise
				# lift the item's base out of its own (tilted) frame.
				var dy := xf.origin.y - p.y
				if absf(l.x) < hw and absf(l.z) < hl and dy > -1.5 and dy < 2.0:
					cell.remove_at(i)
					_break(it, car)


func _break(it: Array, car: Car) -> void:
	var kind: String = it[0]
	var xf: Transform3D = it[1]
	var w: CityWorld = it[3]
	w.break_item(xf.origin)
	_dirty[[w, it[2]]] = 0.15
	if kind == "streetlight":
		var bk := Vector2i(roundi(xf.origin.x * 2.0), roundi(xf.origin.z * 2.0))
		for b in _banners.get(bk, []):
			w.break_item((b[0] as Transform3D).origin)
			_dirty[[b[2], b[1]]] = 0.15
		_banners.erase(bk)
	car.linear_velocity *= SLOW.get(kind, 0.86 if kind.begins_with("tree") else 0.95)
	_throw(kind, xf, car, w)
	broke.emit(kind, xf.origin, car)


func _mesh_for(kind: String, w: CityWorld) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh = null
	if kind.begins_with("tree_"):
		m = TreeKit.mesh(kind.trim_prefix("tree_"))
	else:
		m = w.prop_meshes.get(kind)
	if m == null:
		var src: Array = w._furn_src.get(kind, [])
		if not src.is_empty():
			var a := []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = src[0]
			a[Mesh.ARRAY_NORMAL] = src[1]
			a[Mesh.ARRAY_COLOR] = src[2]
			a[Mesh.ARRAY_INDEX] = src[3]
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			m = am
	_meshes[kind] = m
	return m


func _throw(kind: String, xf: Transform3D, car: Car, w: CityWorld) -> void:
	if _pieces.size() >= budget:
		var old: Array = _pieces.pop_front()
		(old[0] as Node).queue_free()
	var mesh := _mesh_for(kind, w)
	var b := RigidBody3D.new()
	b.collision_layer = 1 << 5
	b.collision_mask = 1 | (1 << 3)
	var tree := kind.begins_with("tree")
	var tall := kind in TALL or tree
	b.mass = 140.0 if tree else (60.0 if tall else (45.0 if kind == "utility_box" else 25.0))
	# Trees are placed scaled; a physics body must not be, so the scale goes
	# on the mesh and the shape instead.
	var sc := xf.basis.get_scale()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var aabb := mesh.get_aabb() if mesh else AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.0, 0.6))
	bs.size = (aabb.size * sc).max(Vector3.ONE * 0.1)
	if tree:
		bs.size.x = minf(bs.size.x, 1.2)   # (the trunk's line, not the crown's width)
		bs.size.z = minf(bs.size.z, 1.2)
	cs.shape = bs
	cs.position = Vector3(0, 1.3 * sc.y, 0) if tree else aabb.get_center() * sc
	if tree:
		bs.size.y = 2.6 * sc.y
	b.add_child(cs)
	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = sc
		if w._furn_src.has(kind) and not w.prop_meshes.has(kind):
			mi.material_override = w.furniture_mat
		b.add_child(mi)
	add_child(b)
	b.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var v := car.linear_velocity
	if tree:
		# Heavy: carried a little way, barely lifted, falls over the bonnet.
		b.linear_velocity = v * _rng.randf_range(0.35, 0.55) + Vector3.UP * _rng.randf_range(0.5, 1.5)
	else:
		b.linear_velocity = v * _rng.randf_range(0.6, 0.95) + Vector3.UP * _rng.randf_range(2.0, 5.0)
	# Tall posts topple over the car's nose.
	var axis := (-car.global_basis.x) if tall else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	b.angular_velocity = axis * maxf(v.length(), 6.0 if tree else 0.0) * (0.18 if tree else (0.25 if tall else 0.6))
	_pieces.append([b, 0.0])
