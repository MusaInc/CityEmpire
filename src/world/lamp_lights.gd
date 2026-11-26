class_name LampLights
extends Node3D
## Real street-lamp light near you. The lamps' light used to be faked
## everywhere with a draped pool mesh (CityWorld._pool_arrays): on hills,
## kerbs and bridge decks it floated or cut through things. Now the COUNT
## lamps nearest the camera each carry a real SpotLight3D under
## the lantern – it lights whatever is actually there (a sloping street, a
## deck, a car, a wall) – and the draped pools fade out inside RANGE
## (lamp_glow.gdshader near_real), carrying only the far streets.
## Night only; re-listed a few times a second. COUNT stays under the Mobile
## spot limit, with slots available for vehicle lamps and signs.

const COUNT := 6
const RANGE := 70.0
const EVERY := 0.3
const WET_ROAD_LIGHTS := 4
const SHADOW_RANGE := 24.0

var worlds: Array = []      # CityWorld (the island and the mainland)
var skyport: SkyportIsland  # optional Skyport Island (auto-discovered if present)
var camera_fn: Callable
var _lights: Array = []
var _t := 0.0
var _wet_road_lights := PackedVector4Array()
var _was_on := false


## Registers an island (such as SkyportIsland) whose lamp_heads() should be
## included in the local night SpotLight3D and wet-road reflection pools.
func add_island_lamps(island: Node) -> void:
	if island is SkyportIsland:
		skyport = island as SkyportIsland


func setup(p_worlds: Array, p_camera_fn: Callable) -> void:
	worlds = []
	skyport = null
	for w in p_worlds:
		if w == null:
			continue
		if w is SkyportIsland:
			skyport = w as SkyportIsland
		elif w is CityWorld:
			worlds.append(w)
			if skyport == null and w.get("skyport") is SkyportIsland:
				skyport = w.get("skyport") as SkyportIsland
	camera_fn = p_camera_fn
	_wet_road_lights.resize(WET_ROAD_LIGHTS)
	for i in COUNT:
		var l := SpotLight3D.new()
		l.name = "Lamp%d" % i
		l.light_color = Color(1.0, 0.8, 0.58)
		l.light_energy = 5.3
		l.light_indirect_energy = 0.0
		l.light_specular = 0.35
		l.spot_range = 17.0
		l.spot_angle = 52.0
		l.spot_angle_attenuation = 1.05
		l.spot_attenuation = 1.12
		l.shadow_enabled = false
		l.shadow_bias = 0.045
		l.shadow_normal_bias = 0.78
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
	var night_level := CarVisual.lamps
	var on := night_level > 0.24
	_t -= dt
	if _t > 0.0:
		return
	_t = EVERY
	if not on:
		for l: SpotLight3D in _lights:
			l.visible = false
		if _was_on:
			_was_on = false
			for i in WET_ROAD_LIGHTS:
				_wet_road_lights[i] = Vector4.ZERO
			for world: CityWorld in worlds:
				if world.ground_mat:
					world.ground_mat.set_shader_parameter("wet_road_lamps", _wet_road_lights)
			if skyport != null and is_instance_valid(skyport) and skyport.ground_mat:
				skyport.ground_mat.set_shader_parameter("wet_road_lamps", _wet_road_lights)
		return
	_was_on = true
	var cam: Vector3 = camera_fn.call()
	var cand: Array = []
	var range_sq := RANGE * RANGE
	for w: CityWorld in worlds:
		var k0 := Vector2i(floori(cam.x / CityWorld.CHUNK), floori(cam.z / CityWorld.CHUNK))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var key := k0 + Vector2i(dx, dz)
				var items: Array = w.call("chunk_lamps", key) if w.has_method("chunk_lamps") else w.chunk_props(key)
				for p in items:
					var lamp: Transform3D
					if p is Transform3D:
						lamp = p
					elif p is Array and p.size() >= 2:
						if p[0] != "streetlight":
							continue
						lamp = p[1]
					else:
						continue
					var head := lamp * CityWorld.LAMP_HEAD
					var d := head.distance_squared_to(cam)
					if d < range_sq:
						cand.append([d, head, -lamp.basis.z.normalized(), w.layout.district(head.x, head.z)])
	if skyport == null and not worlds.is_empty():
		var sp: Variant = worlds[0].get("skyport")
		if sp is SkyportIsland:
			skyport = sp as SkyportIsland
	if skyport != null and is_instance_valid(skyport) and SkyportIsland.distance_to(cam) < RANGE + 420.0:
		for head: Vector3 in skyport.lamp_heads():
			var d := head.distance_squared_to(cam)
			if d < range_sq:
				cand.append([d, head, Vector3.ZERO, "airport"])
	cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in WET_ROAD_LIGHTS:
		_wet_road_lights[i] = Vector4.ZERO
		if i < cand.size():
			var head: Vector3 = cand[i][1]
			_wet_road_lights[i] = Vector4(head.x, head.y, head.z, _lamp_temperature(head, cand[i][3]))
	for world: CityWorld in worlds:
		if world.ground_mat:
			world.ground_mat.set_shader_parameter("wet_road_lamps", _wet_road_lights)
	if skyport != null and is_instance_valid(skyport) and skyport.ground_mat:
		skyport.ground_mat.set_shader_parameter("wet_road_lamps", _wet_road_lights)
	for i in COUNT:
		var l: SpotLight3D = _lights[i]
		if i < cand.size():
			var head: Vector3 = cand[i][1]
			var roadward: Vector3 = cand[i][2]
			l.global_position = head - Vector3.UP * 0.15
			l.look_at(l.global_position + Vector3.DOWN + roadward * 0.18, Vector3.FORWARD)
			var district: String = cand[i][3]
			l.light_color = Color(1.0, 0.76, 0.52).lerp(Color(0.91, 0.95, 1.0), _lamp_temperature(head, district))
			l.light_energy = smoothstep(0.24, 0.70, night_level) * float(DISTRICT_ENERGY.get(district, 8.2))
			l.spot_range = 22.0 if district in ["airport", "docks"] else 20.5
			l.spot_angle = 56.0 if district in ["cbd", "midtown", "airport"] else 51.0
			# One local shadow pool on Medium or High. The other lamps
			# keep the rendered street coverage without extra shadow maps.
			l.shadow_enabled = i == 0 and Settings.quality >= Settings.Quality.MEDIUM and float(cand[i][0]) < SHADOW_RANGE * SHADOW_RANGE
			l.visible = true
		else:
			l.visible = false


## (+20% 2026-11-26: "street lights need to do slightly better in lighting up the street")
const DISTRICT_ENERGY := {"suburb": 7.0, "georgian": 7.0, "docks": 8.9, "cbd": 9.8, "airport": 9.6}
const DISTRICT_TEMPERATURE := {"suburb": 0.15, "georgian": 0.20, "waterfront": 0.38,
	"midtown": 0.54, "cbd": 0.72, "docks": 0.37, "airport": 0.77}


static func _lamp_temperature(head: Vector3, district: String) -> float:
	var variation := float(absi(hash(Vector2i(roundi(head.x), roundi(head.z)))) % 17) * 0.01
	return float(DISTRICT_TEMPERATURE.get(district, 0.4)) + variation
