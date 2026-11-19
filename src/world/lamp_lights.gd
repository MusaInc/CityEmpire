class_name LampLights
extends Node3D
## Real street-lamp light near you. The lamps' light used to be faked
## everywhere with a draped pool mesh (CityWorld._pool_arrays): on hills,
## kerbs and bridge decks it floated or cut through things. Now the COUNT
## lamps nearest the camera each carry a real, shadowless SpotLight3D under
## the lantern – it lights whatever is actually there (a sloping street, a
## deck, a car, a wall) – and the draped pools fade out inside RANGE
## (lamp_glow.gdshader near_real), carrying only the far streets.
## Night only; re-listed a few times a second. COUNT stays under the Mobile
## renderer's per-object light limit (8) so nothing flickers.

const COUNT := 8
const RANGE := 70.0
const EVERY := 0.3

var worlds: Array = []      # CityWorld (the island and the mainland)
var camera_fn: Callable
var _lights: Array = []
var _t := 0.0


func setup(p_worlds: Array, p_camera_fn: Callable) -> void:
	worlds = p_worlds.filter(func(w): return w != null)
	camera_fn = p_camera_fn
	for i in COUNT:
		var l := SpotLight3D.new()
		l.name = "Lamp%d" % i
		l.light_color = Color(1.0, 0.8, 0.58)
		l.light_energy = 5.0
		l.light_indirect_energy = 0.0
		l.light_specular = 0.35
		l.spot_range = 20.0
		l.spot_angle = 72.0
		l.spot_angle_attenuation = 0.9
		l.spot_attenuation = 0.9
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = RANGE - 10.0
		l.distance_fade_length = 10.0
		l.visible = false
		l.rotation = Vector3(-PI * 0.5, 0, 0)   # straight down
		add_child(l)
		_lights.append(l)
	top_level = true
	for w: CityWorld in worlds:
		if not w._glow_mats.is_empty():
			w._glow_mats[0].set_shader_parameter("near_real", RANGE)


func _process(dt: float) -> void:
	if worlds.is_empty():
		return
	var on: bool = (worlds[0] as CityWorld)._glow_on
	_t -= dt
	if _t > 0.0:
		return
	_t = EVERY
	if not on:
		for l: SpotLight3D in _lights:
			l.visible = false
		return
	var cam: Vector3 = camera_fn.call()
	var cand: Array = []
	for w: CityWorld in worlds:
		var k0 := Vector2i(floori(cam.x / CityWorld.CHUNK), floori(cam.z / CityWorld.CHUNK))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for p in w.chunk_props(k0 + Vector2i(dx, dz)):
					if p[0] != "streetlight":
						continue
					var head: Vector3 = (p[1] as Transform3D) * CityWorld.LAMP_HEAD
					var d := head.distance_squared_to(cam)
					if d < RANGE * RANGE:
						cand.append([d, head])
	cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in COUNT:
		var l: SpotLight3D = _lights[i]
		if i < cand.size():
			l.global_position = (cand[i][1] as Vector3) - Vector3.UP * 0.15
			l.visible = true
		else:
			l.visible = false
