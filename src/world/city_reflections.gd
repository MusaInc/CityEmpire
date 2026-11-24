class_name CityReflections
extends Node3D
## Real city reflections for the Mobile renderer (no SSR there): one
## reflection probe captured just above the camera, covering ~600 m of the
## city, so glass facades, car paint, chrome and wet streets mirror the real
## buildings and streets round you instead of only the sky (2026-11-21).
## UPDATE_ONCE: it re-renders only when moved – after you've travelled
## RECAPTURE m or the light has changed (every LIGHT_EVERY s) – never every
## frame. Off on the Low quality preset.

const RECAPTURE := 180.0
const LIGHT_EVERY := 60.0
var probe: ReflectionProbe
var _last := Vector3(INF, 0, INF)
var _t := 0.0
var view_fn := Callable()   # () -> Vector3: where you are (camera or vehicle)


func _ready() -> void:
	probe = ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(600.0, 260.0, 600.0)
	probe.max_distance = 450.0
	probe.box_projection = false
	probe.interior = false
	probe.enable_shadows = false
	probe.intensity = 1.18
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.mesh_lod_threshold = 8.0
	add_child(probe)


func _process(dt: float) -> void:
	if not view_fn.is_valid():
		return
	_t += dt
	var p: Vector3 = view_fn.call()
	if p.distance_to(_last) > RECAPTURE or _t > LIGHT_EVERY:
		_t = 0.0
		_last = p
		# (Moving an UPDATE_ONCE probe is what makes it render again; a nudge
		# forces it when only the light changed.)
		probe.global_position = p + Vector3(0.0, 6.0 + randf() * 0.01, 0.0)
