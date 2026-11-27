extends RefCounted
## Launch lifecycle regression: background scene load, retry and duplicate input.


func test_retry_loads_one_scene_and_releases_overlay(t) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var previous := tree.current_scene
	var script_path := "user://startup_fixture.gd"
	var script := GDScript.new()
	script.source_code = "extends Node\nvar startup_ready := false\n"
	t.check(script.reload() == OK and ResourceSaver.save(script, script_path) == OK, "create readiness fixture script")
	var fixture := Node.new()
	fixture.set_script(script)
	fixture.name = "StartupFixture"
	var packed := PackedScene.new()
	packed.pack(fixture)
	fixture.free()
	var path := "user://startup_fixture.tscn"
	t.check(ResourceSaver.save(packed, path) == OK, "create temporary scene")
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	boot.auto_start = false
	boot.scene_path = path
	tree.root.add_child(boot)
	await tree.process_frame
	boot._failed()
	t.check(boot.retry.visible and is_equal_approx(boot.track.modulate.a, 0.0), "failure provides a usable retry")
	t.check(boot.retry.has_focus(), "retry is accessible to keyboard/controller")
	boot.retry.pressed.emit()
	boot._begin()  # rapid second activation must not schedule a second scene
	var deadline := Time.get_ticks_msec() + 10000
	while tree.root.get_node_or_null("StartupFixture") == null and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var game := tree.root.get_node_or_null("StartupFixture")
	if game:
		await tree.process_frame
		t.check(is_instance_valid(boot) and boot._target < 1.0, "overlay holds until the scene reports readiness")
		t.check(tree.root.disable_3d, "3D rendering waits until world initialization")
		game.startup_ready = true
	while is_instance_valid(boot) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	t.check(not is_instance_valid(boot), "loading overlay is removed after transition")
	t.check(not tree.root.disable_3d, "3D rendering resumes after initialization")
	var matches := 0
	var loaded: Node
	for child in tree.root.get_children():
		if child.name == "StartupFixture":
			matches += 1
			loaded = child
	t.check(matches == 1, "one game scene despite duplicate activation")
	t.check(loaded != null and tree.current_scene == loaded, "new scene becomes current")
	tree.current_scene = previous
	if is_instance_valid(loaded):
		loaded.queue_free()
	if is_instance_valid(boot):
		boot.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))
