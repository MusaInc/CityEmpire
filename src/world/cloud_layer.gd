class_name CloudLayer
extends Node3D
## Clouds in the world at the tallest towers' height (the spire is 272 m):
## SLICES horizontal planes 290-330 m up following the camera (the pattern is
## in world space, so they don't slide with it). cloud_layer.gdshader shades
## them. Two slices on Medium, three on High (transparent overdraw).

const BASE := 290.0
const DEPTH := 40.0
var slices := 3
var cover := 0.45
var dark := 0.0
var view_fn := Callable()   # () -> Vector3
var _mats: Array[ShaderMaterial] = []


func _ready() -> void:
	var shader := load("res://src/world/shaders/cloud_layer.gdshader") as Shader
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000.0, 9000.0)
	for i in slices:
		var k := float(i) / maxf(slices - 1, 1)
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("slice", k)
		sm.render_priority = -2
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = BASE + DEPTH * k
		mi.extra_cull_margin = 500.0
		add_child(mi)
		_mats.append(sm)


func _process(_dt: float) -> void:
	if view_fn.is_valid():
		var p: Vector3 = view_fn.call()
		global_position = Vector3(snappedf(p.x, 100.0), 0.0, snappedf(p.z, 100.0))
	for m in _mats:
		m.set_shader_parameter("cover", cover)
		m.set_shader_parameter("dark", dark)
