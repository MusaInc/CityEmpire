class_name CraftCamera
extends Node3D
## Third-person camera for Craft (helicopters, planes, boats): behind and
## above, distance by size and speed, looking a little ahead along the
## flight path, eased so turns and banks don't jolt. Pulls in when a
## building would block the view (one ray). view_yaw() as the other cameras.

var cam: Camera3D
var target: Craft
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	cam = Camera3D.new()
	cam.far = 9000.0
	cam.fov = 68.0
	add_child(cam)
	_ray.collision_mask = 1


func set_target(c: Craft) -> void:
	target = c
	var f := c.forward()
	_pos = c.global_position - f * _dist() + Vector3.UP * _height()
	_look = c.global_position
	cam.global_position = _pos
	cam.look_at(_look + Vector3.UP * 0.01, Vector3.UP)


func _dist() -> float:
	var L: float = (target.spec.get("size", Vector3(3, 2, 8)) as Vector3).z
	var base := {"heli": 14.0, "plane": 16.0, "boat": 10.0}.get(target.kind, 12.0) as float
	return base + L * 0.9 + clampf(target.speed * 0.12, 0.0, 14.0)


func _height() -> float:
	return {"heli": 5.5, "plane": 5.0, "boat": 4.0}.get(target.kind, 4.0) as float + \
		(target.spec.get("size", Vector3(3, 2, 8)) as Vector3).y * 0.6


func view_yaw() -> float:
	var f := -cam.global_basis.z
	return atan2(-f.x, -f.z)


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var f := target.forward()
	var v := target.velocity
	var want := target.global_position - f * _dist() + Vector3.UP * _height() - v * 0.08
	_pos = _pos.lerp(want, 1.0 - exp(-4.0 * dt))
	var ahead := target.global_position + f * (6.0 + target.speed * 0.4) + Vector3.UP * 1.5
	_look = _look.lerp(ahead, 1.0 - exp(-6.0 * dt))
	# Something solid between the craft and the camera: come in front of it.
	var p := _pos
	_ray.from = target.global_position + Vector3.UP * 2.0
	_ray.to = p
	_ray.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		p = (hit["position"] as Vector3) + ((_ray.from - p).normalized()) * 1.0
	cam.global_position = p
	if (_look - p).length() > 0.1:
		cam.look_at(_look, Vector3.UP)
