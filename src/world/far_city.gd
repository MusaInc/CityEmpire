class_name FarCity
extends Node3D
## The city seen from far off: every streamed chunk also has a far version –
## its buildings' plain massing (the chunk's "Low" mesh) and its ground on a
## coarse grid (BuildingMesher.add_far_ground) – kept resident for the whole
## map and shown exactly while that chunk is NOT streamed in. Without it the
## islands simply vanished past the streaming range (~0.9–1.45 km): from a
## plane, a helicopter or the far side of the bay there was only seabed
## where the cities should be.
##
## Built on the worker pool after start-up (nothing is drawn until it's
## ready; the streamed chunks cover the near view meanwhile). No shadows, no
## collision: two draws per far chunk (massing + ground), each a few
## thousand triangles at most.

var world: CityWorld
var _keys: Array = []
var _arrays: Array = []
var _task := -1
var _nodes := {}          # chunk key -> Node3D
var _lock := Mutex.new()


func setup(w: CityWorld) -> void:
	world = w
	name = "FarCity"
	_keys = w._all_keys.duplicate()
	_arrays.resize(_keys.size())
	_task = WorkerThreadPool.add_group_task(_gen, _keys.size(), -1, false, "far city")


func _gen(i: int) -> void:
	var key: Vector2i = _keys[i]
	var rect := Rect2(Vector2(key) * CityWorld.CHUNK, Vector2(CityWorld.CHUNK, CityWorld.CHUNK))
	var low := BuildingMesher.new()
	for b in world._by_chunk.get(key, []):
		low.add_building(b, false)
		if b["kind"] == "normal":
			low.add_skyline(b)
	var gm := BuildingMesher.new()
	gm.add_far_ground(world.layout, rect)
	var res := {"low": null if low.is_empty() else low.arrays(), "ground": null if gm.is_empty() else gm.arrays()}
	_lock.lock()
	_arrays[i] = res
	_lock.unlock()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1


func ready_now() -> bool:
	return _task < 0


## Block until built (tests and captures).
func finish() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_instantiate()


func _process(_dt: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_group_task_completed(_task):
			return
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_instantiate()
	for key in _nodes:
		(_nodes[key] as Node3D).visible = not world._loaded.has(key)


func _instantiate() -> void:
	_task = -1
	for i in _keys.size():
		var res: Variant = _arrays[i]
		if res == null:
			continue
		var root := Node3D.new()
		root.name = "Far_%d_%d" % [_keys[i].x, _keys[i].y]
		for part: Array in [["low", world.building_mat], ["ground", world.ground_mat]]:
			var a: Variant = res[part[0]]
			if a == null:
				continue
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = part[1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		if root.get_child_count() == 0:
			root.free()
			continue
		root.visible = not world._loaded.has(_keys[i])
		add_child(root)
		_nodes[_keys[i]] = root
	_arrays.clear()


## Triangles in the far layer (tests / perf notes).
func triangle_count() -> int:
	var n := 0
	for key in _nodes:
		for mi in (_nodes[key] as Node3D).get_children():
			n += (mi as MeshInstance3D).mesh.get_faces().size() / 3
	return n
