extends RefCounted
## Exercise the capsule and ordinary on-foot steering at the fixed physics rate.

class Walk:
	extends RefCounted
	var human_steer := true
	var move := Vector3.ZERO

	func drive(_player, _dt: float) -> Dictionary:
		return {"move": move, "aim": Vector3.RIGHT, "jump": false}


func test_slow_stairs_keep_the_stride(t) -> void:
	var tree: SceneTree = t
	var stage := Node3D.new()
	tree.root.add_child(stage)
	PrototypeWorld.add_box(stage, Vector3(0, -0.5, 0), Vector3(32, 1, 8), Color.GRAY, false)
	for i in 8:
		var height := (i + 1) * 0.165
		PrototypeWorld.add_box(stage, Vector3(i * 0.34, height * 0.5, 0), Vector3(0.34, height, 3), Color.GRAY, false)
		PrototypeWorld.add_box(stage, Vector3(6.0 - i * 0.34, height * 0.5, 0), Vector3(0.34, height, 3), Color.GRAY, false)
	PrototypeWorld.add_box(stage, Vector3(3, 0.66, 0), Vector3(1, 1.32, 3), Color.GRAY, false)
	var player := Player.new()
	player.everyday = true
	player.swing_enabled = false
	player.params = preload("res://config/empire_params.tres")
	var walk := Walk.new()
	player.bot = walk
	stage.add_child(player)
	player.respawn(Vector3(-1.90, 0.92, 0.4))
	for i in 24:
		await tree.physics_frame
	var rises: Array[float] = []
	player.stepped_up.connect(func(height: float): rises.append(height))
	walk.move = Vector3.RIGHT * 0.42
	var top := player.position.y
	var largest_advance := 0.0
	for i in 430:
		var before := player.position
		await tree.physics_frame
		top = maxf(top, player.position.y)
		largest_advance = maxf(largest_advance, player.position.x - before.x)
	t.check(top > 2.15 and rises.size() == 8, "the capsule clears each riser once at a walk")
	t.check(player.position.x > 6.4 and player.is_on_floor(), "the same stride returns to the ground on the far side")
	t.check(largest_advance < 0.07, "stair clearance never adds a forward jump")
	stage.queue_free()
	await tree.process_frame
