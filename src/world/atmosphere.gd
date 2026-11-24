class_name Atmosphere
extends Node3D
## Sky, sun/moon, fog, weather and tonemapping for the whole game.
##
## Time of day: `hour` (0–24). In a live game it runs through a full day in
## DAY_MINUTES real minutes (Settings.time_of_day = "cycle") or holds a fixed
## hour. The sun rises in the east, crosses the south and sets behind the
## strait in the west; after dusk the same light becomes a cool moon.
## Everything that should react reads shared global shader uniforms:
##   sky_top / sky_horizon (linear)  sun_dir  night (0..1)  wetness  rain
## and the city's lamps read `night` via CityWorld.set_night().
##
## Weather: clear, bright (hard summer sun), haze (heat haze), cloudy, rain,
## storm, fog. "changing" drifts between them
## every few minutes; every parameter eases (no pops). Rain draws streaks
## round the camera (RainFx), wets streets/roofs/water (wetness rises while it
## rains and dries afterwards), storms add lightning (and a thunder signal).
## Captures and tools get a fixed golden hour, clear (`live` = false), unless
## asked for `--time=<h>` / `--weather=<name>`.

signal thunder(delay: float, strength: float)

const ZENITH := Color(0.14, 0.37, 0.72)
const HORIZON := Color(0.75, 0.83, 0.90)
## The default (captures, tools, first launch): late-afternoon golden hour.
const DEFAULT_HOUR := 16.0
const DAY_MINUTES := 16.0
## Sun direction at DEFAULT_HOUR (kept for callers that want the fixed one).
const SUN_ROT := Vector3(-38.0, -112.0, 0.0)
const WEATHERS := ["clear", "bright", "haze", "cloudy", "rain", "storm", "fog"]
## Per weather: cloud cover, rain, fog, storm (lightning), cloud darkness,
## and the look on top: sun (sunlight ×), haze (extra distance haze that
## fades far buildings into the sky, 0..1), warm (a warm, dusty haze colour),
## punch (harder light: deeper shade, richer colour, more bloom on sunlit
## glass), mist (a low fog lying in the streets and over the water, 0..1).
const WEATHER_PARAMS := {
	"clear": {"cloud": 0.34, "rain": 0.0, "fog": 0.0, "storm": 0.0, "dark": 0.0,
		"sun": 1.06, "haze": 0.14, "warm": 0.08, "punch": 0.25, "mist": 0.0},
	"bright": {"cloud": 0.12, "rain": 0.0, "fog": 0.0, "storm": 0.0, "dark": 0.0,
		"sun": 1.24, "haze": 0.04, "warm": 0.18, "punch": 1.0, "mist": 0.0},
	"haze": {"cloud": 0.22, "rain": 0.0, "fog": 0.08, "storm": 0.0, "dark": 0.0,
		"sun": 1.12, "haze": 0.85, "warm": 1.0, "punch": 0.4, "mist": 0.0},
	"cloudy": {"cloud": 0.72, "rain": 0.0, "fog": 0.08, "storm": 0.0, "dark": 0.28,
		"sun": 1.0, "haze": 0.32, "warm": 0.0, "punch": 0.0, "mist": 0.0},
	"rain": {"cloud": 0.90, "rain": 0.82, "fog": 0.20, "storm": 0.0, "dark": 0.82,
		"sun": 1.0, "haze": 0.36, "warm": 0.0, "punch": 0.15, "mist": 0.22},
	"storm": {"cloud": 1.0, "rain": 1.0, "fog": 0.28, "storm": 1.0, "dark": 1.0,
		"sun": 1.0, "haze": 0.46, "warm": 0.0, "punch": 0.2, "mist": 0.28},
	"fog": {"cloud": 0.6, "rain": 0.0, "fog": 0.92, "storm": 0.0, "dark": 0.22,
		"sun": 1.0, "haze": 0.45, "warm": 0.0, "punch": 0.0, "mist": 1.0},
}
## Low fog: its top (world m; the streets are ~2–60 m, the sea −1.6) and
## how fast it thickens below that.
const MIST_TOP := 7.0
const MIST_DENSITY := 0.09

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain_fx: RainFx
## Runs the clock and weather changes (main sets it for real play).
var live := false
var hour := DEFAULT_HOUR
var weather := "clear"
## Current (eased) weather parameters and derived values other systems read.
var w := WEATHER_PARAMS["clear"].duplicate()
var wetness := 0.0
var night := 0.0
var _flash := 0.0
var _next_bolt := 8.0
var _weather_left := 240.0
var _rng := RandomNumberGenerator.new()
var _sky_t := 0.0
var _world: Node


static func sun_direction() -> Vector3:
	return Basis.from_euler(SUN_ROT * PI / 180.0) * Vector3.BACK


## Sun elevation and azimuth (degrees) for an hour: up at ~05:30, highest
## (70°) at noon in the south, down at ~18:30 in the west.
static func sun_angles(h: float) -> Vector2:
	var el := 70.0 * sin(PI * (h - 5.5) / 13.0)
	if h < 5.5 or h > 18.5:
		# Below the horizon: keep going down smoothly through the night.
		var t := fposmod(h - 18.5, 24.0) / 11.0  # 0 at dusk, 1 at dawn
		el = -40.0 * sin(PI * t)
	var yaw := -112.0 + (h - DEFAULT_HOUR) * 15.0
	return Vector2(el, yaw)


func _ready() -> void:
	add_to_group("atmosphere")  # (homes read `night` to warm their lights)
	_rng.randomize()
	var settings := get_node_or_null("/root/Settings")
	var preset: Dictionary = settings.preset() if settings else {"shadows": true, "glow": true}
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://src/world/shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Blending the sky with neutral bounce keeps shadow materials readable.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.ambient_light_color = Color(0.78, 0.79, 0.80)
	env.ambient_light_sky_contribution = 0.22
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.35
	env.fog_sun_scatter = 0.3
	env.fog_aerial_perspective = 0.8
	env.glow_enabled = preset.get("glow", true)
	env.glow_intensity = 0.26
	env.glow_bloom = 0.045
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_angular_distance = 0.85
	sun.shadow_enabled = preset.get("shadows", true)
	sun.shadow_bias = 0.045
	sun.shadow_normal_bias = 0.55
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	# Reserve the near cascade for the hero, vehicles and immediate street furniture.
	sun.directional_shadow_split_1 = 0.075
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	rain_fx = RainFx.new()
	rain_fx.name = "Rain"
	add_child(rain_fx)
	if settings and not settings.changed.is_connected(_on_settings_changed):
		settings.changed.connect(_on_settings_changed)
	_apply_quality_preset()
	_apply(0.0, true)


## Main calls this once settings and command-line overrides are known.
## Set by --time: captures keep that hour (the title camera's shots don't
## replace it).
var fixed_hour := false


func configure(args: Dictionary, world: Node) -> void:
	_world = world
	var capture := args.has("shot") or args.has("cam") or args.has("tour")
	live = not capture
	if args.has("time"):
		hour = fposmod(float(args["time"]), 24.0)
		live = false
		fixed_hour = true
	if args.has("weather") and args["weather"] in WEATHERS:
		set_weather(args["weather"], true)
	elif live:
		_from_settings(true)
	var st := _settings()
	if st and not st.changed.is_connected(_on_settings_changed):
		st.changed.connect(_on_settings_changed)
	_apply_quality_preset()
	_apply(0.0, true)


func _exit_tree() -> void:
	var st := _settings()
	if st and st.changed.is_connected(_on_settings_changed):
		st.changed.disconnect(_on_settings_changed)


func _on_settings_changed() -> void:
	_apply_quality_preset()
	if live:
		_from_settings(false)


func _apply_quality_preset() -> void:
	var st := _settings()
	if st == null:
		return
	var preset: Dictionary = st.preset()
	if env:
		env.glow_enabled = bool(preset.get("glow", true))
	if sun:
		sun.shadow_enabled = bool(preset.get("shadows", true))
		var q := int(st.get("quality"))
		if q <= 0:
			sun.directional_shadow_max_distance = 120.0
			sun.directional_shadow_split_1 = 0.12
		elif q == 1:
			sun.directional_shadow_max_distance = 160.0
			sun.directional_shadow_split_1 = 0.11
		else:
			sun.directional_shadow_max_distance = 240.0
			sun.directional_shadow_split_1 = 0.085


## The Settings autoload (looked up, not named: tool scripts run without it).
func _settings() -> Node:
	return get_node_or_null("/root/Settings") if is_inside_tree() else null


func _from_settings(instant: bool) -> void:
	var st := _settings()
	if st == null:
		return
	match st.time_of_day:
		"day":
			hour = 13.0
		"sunset":
			hour = 17.9
		"night":
			hour = 23.0
	if st.weather in WEATHERS:
		set_weather(st.weather, instant)
	elif not weather in WEATHERS or instant:
		set_weather("clear", instant)


func set_weather(name: String, instant := false) -> void:
	weather = name
	_weather_left = _rng.randf_range(150.0, 320.0)
	if instant:
		w = WEATHER_PARAMS[name].duplicate()
		wetness = clampf(w["rain"] * 1.2, 0.0, 1.0)


func _process(dt: float) -> void:
	var st := _settings() if live else null
	if st:
		if st.time_of_day == "cycle":
			hour = fposmod(hour + dt * 24.0 / (DAY_MINUTES * 60.0), 24.0)
		if st.weather == "changing":
			_weather_left -= dt
			if _weather_left <= 0.0:
				set_weather(_next_weather())
	_apply(dt, false)


## Mostly fair: bright, clear and warm skies most of the time, occasional
## passing showers, rare storms or coastal morning fog.
func _next_weather() -> String:
	var foggy := 0.09 if hour < 9.0 or hour > 21.0 else 0.03
	var wet_now := weather in ["rain", "storm"]
	var opts := {
		"clear": 0.30,
		"bright": 0.24,
		"haze": 0.12,
		"cloudy": 0.18,
		"rain": 0.0 if wet_now else 0.09,
		"storm": 0.0 if wet_now else 0.03,
		"fog": foggy,
	}
	var total := 0.0
	for k in opts:
		total += opts[k] if k != weather else 0.0
	var x := _rng.randf() * total
	for k in opts:
		if k == weather:
			continue
		x -= opts[k]
		if x <= 0.0:
			return k
	return "clear"


func _apply(dt: float, instant: bool) -> void:
	# Ease the weather towards its target (~25 s for most of the change).
	var target: Dictionary = WEATHER_PARAMS.get(weather, WEATHER_PARAMS["clear"])
	var k := 1.0 if instant else 1.0 - exp(-dt / 9.0)
	for key in w:
		w[key] = lerpf(w[key], target[key], k)
	# Streets soak in a minute of rain and dry out in ~2 minutes once it clears.
	var wet_to := clampf(float(w["rain"]) * 1.3, 0.0, 1.0)
	if not instant:
		var rate := 1.0 / 45.0 if wet_to > wetness else 1.0 / 110.0
		wetness = move_toward(wetness, wet_to, rate * dt)
	# Lightning: a bright double flicker every 6–20 s in a storm.
	if float(w["storm"]) > 0.5 and live:
		_next_bolt -= dt
		if _next_bolt <= 0.0:
			_next_bolt = _rng.randf_range(6.0, 20.0)
			_flash = 1.0
			thunder.emit(_rng.randf_range(0.6, 3.0), _rng.randf_range(0.5, 1.0))
	_flash = maxf(_flash - dt * 3.2, 0.0)
	var fl := _flash * (0.6 + 0.4 * sin(_flash * 40.0)) if _flash > 0.0 else 0.0

	var ang := sun_angles(hour)
	var el := ang.x
	var overcast := smoothstep(0.55, 1.0, float(w["cloud"]))
	var cloud_softness := smoothstep(0.48, 0.90, float(w["cloud"]))
	var fog := float(w["fog"])
	night = 1.0 - smoothstep(-8.0, 3.0, el)
	var lamps := maxf(night, overcast * 0.35 * float(w["dark"]))

	# --- light: the sun above -3°, the moon below.
	var day_light := smoothstep(-3.0, 8.0, el)
	if el > -3.0:
		sun.rotation_degrees = Vector3(-maxf(el, 1.5), ang.y, 0.0)
		# Cinematic sunset without washing the entire city in heavy orange:
		# warm golden-peach sunlight paired with cool indigo-slate sky shadows.
		sun.light_color = _ramp(el, [[0.0, Color(1.0, 0.66, 0.42)], [8.0, Color(1.0, 0.80, 0.62)],
			[25.0, Color(1.0, 0.92, 0.82)], [60.0, Color(1.0, 0.97, 0.92)]])
		sun.light_energy = day_light * _rampf(el, [[0.0, 1.55], [10.0, 2.08], [25.0, 2.48], [60.0, 2.62]])
		sky_mat.set_shader_parameter("sun_glow", 1.05)
		sky_mat.set_shader_parameter("disc_size", 0.999989)
		sky_mat.set_shader_parameter("disc_k", 6.5)
		sky_mat.set_shader_parameter("sun_tint", sun.light_color)
	else:
		# Moon: high in the south-east, cool and crisp.
		sun.rotation_degrees = Vector3(-42.0, 150.0, 0.0)
		sun.light_color = Color(0.66, 0.76, 0.98)
		sun.light_energy = 0.52 * (1.0 - smoothstep(-12.0, -3.0, el))
		sky_mat.set_shader_parameter("sun_glow", 0.28)
		sky_mat.set_shader_parameter("disc_size", 0.999984)
		sky_mat.set_shader_parameter("disc_k", 2.4)
		sky_mat.set_shader_parameter("sun_tint", Color(0.78, 0.86, 1.0))
	var punch := float(w["punch"])
	var hz := float(w["haze"])
	var warm := float(w["warm"])
	sun.light_energy *= (1.0 - 0.72 * overcast) * lerpf(1.0, float(w["sun"]), day_light)
	sun.light_energy *= 1.0 - 0.18 * cloud_softness * day_light
	# Dawn mist: on calm mornings a low fog lies in the streets and over the
	# water and burns off by mid-morning (less if it's windy and wet).
	var dawn := smoothstep(4.0, 6.0, hour) * (1.0 - smoothstep(8.0, 10.5, hour))
	var mist := maxf(float(w["mist"]), dawn * 0.75 * (1.0 - float(w["rain"])) * (1.0 - 0.7 * punch))
	sun.shadow_opacity = lerpf(1.0 - 0.52 * overcast, 0.98 - 0.65 * cloud_softness, day_light)

	# --- sky colours by sun height, moody slate-blue under rain/storm.
	var zen := _ramp(el, [[-18.0, Color(0.018, 0.032, 0.075)], [-6.0, Color(0.06, 0.11, 0.28)],
		[0.0, Color(0.13, 0.25, 0.52)], [8.0, Color(0.17, 0.35, 0.64)], [25.0, ZENITH], [60.0, Color(0.15, 0.40, 0.76)]])
	var hor := _ramp(el, [[-18.0, Color(0.065, 0.095, 0.165)], [-6.0, Color(0.32, 0.28, 0.42)],
		[0.0, Color(0.92, 0.66, 0.50)], [8.0, Color(0.88, 0.80, 0.74)], [25.0, HORIZON], [60.0, Color(0.72, 0.82, 0.92)]])
	var haze := _ramp(el, [[-18.0, Color(0.07, 0.09, 0.15)], [-6.0, Color(0.46, 0.30, 0.34)],
		[0.0, Color(0.96, 0.64, 0.42)], [8.0, Color(0.98, 0.74, 0.54)], [25.0, Color(1.0, 0.78, 0.58)],
		[60.0, Color(0.96, 0.88, 0.78)]])
	var grey := 0.26 + 0.52 * day_light
	var grey_c := Color(grey * 0.82, grey * 0.89, grey * 0.98) * lerpf(1.0, 0.54, float(w["dark"]))
	zen = zen.lerp(grey_c * 0.72, overcast * 0.82)
	hor = hor.lerp(grey_c * 0.96, overcast * 0.72)
	haze = haze.lerp(grey_c * 0.92, overcast * 0.80)
	# Hard summer sun: a deeper blue overhead. Heat haze: a pale, milky sky,
	# the horizon dusty gold-white.
	zen = zen.lerp(Color(0.10, 0.32, 0.68), punch * 0.28 * day_light)
	hor = hor.lerp(Color(0.92, 0.86, 0.76), hz * warm * 0.45 * day_light)
	zen = zen.lerp(hor, hz * 0.20 * day_light)
	haze = haze.lerp(Color(1.0, 0.86, 0.64), hz * warm * 0.4 * day_light)
	zen = zen.lerp(Color(0.8, 0.86, 1.0), fl * 0.6)
	hor = hor.lerp(Color(0.8, 0.86, 1.0), fl * 0.6)
	var fog_col := hor.lerp(Color(0.46, 0.64, 0.88), 0.45 * day_light).lerp(grey_c * 0.92, overcast * 0.52)
	fog_col = fog_col.lerp(Color(0.88, 0.80, 0.68) * lerpf(0.35, 1.0, day_light), warm * 0.55)
	# The sky shader is radiance-mapped: update it a few times a second, not
	# every frame (it changes slowly), except for lightning.
	_sky_t -= dt
	if _sky_t <= 0.0 or instant or fl > 0.0:
		_sky_t = 0.25
		sky_mat.set_shader_parameter("zenith", zen)
		sky_mat.set_shader_parameter("horizon", hor)
		sky_mat.set_shader_parameter("haze", haze)
		sky_mat.set_shader_parameter("ground", hor.darkened(0.68))
		var cl := _ramp(el, [[-12.0, Color(0.11, 0.14, 0.22)], [-3.0, Color(0.58, 0.38, 0.38)],
			[3.0, Color(1.0, 0.62, 0.42)], [15.0, Color(1.0, 0.88, 0.74)], [40.0, Color(1.0, 0.98, 0.95)]])
		var cs := _ramp(el, [[-12.0, Color(0.04, 0.06, 0.11)], [-3.0, Color(0.24, 0.22, 0.32)],
			[10.0, Color(0.50, 0.52, 0.64)], [40.0, Color(0.58, 0.63, 0.72)]])
		sky_mat.set_shader_parameter("cloud_lit", cl.lerp(grey_c * 1.04, overcast * 0.65))
		sky_mat.set_shader_parameter("cloud_shade", cs.lerp(grey_c * 0.48, overcast * 0.72))
		sky_mat.set_shader_parameter("cloud_cover", w["cloud"])
		sky_mat.set_shader_parameter("cloud_dark", w["dark"])
		sky_mat.set_shader_parameter("sky_fog_tint", fog_col)
		sky_mat.set_shader_parameter("sky_fog_amount", 0.04 + 0.52 * fog + 0.08 * hz)
		sky_mat.set_shader_parameter("stars", night * (1.0 - overcast) * (1.0 - fog))
		sky_mat.set_shader_parameter("flash", fl)

	# --- ambient, exposure, fog.
	# Deeper, sky-tinted shadows by day; readable urban glow at night.
	env.ambient_light_energy = _rampf(el, [[-15.0, 0.30], [-4.0, 0.38], [2.0, 0.46], [20.0, 0.52]]) \
		* (1.0 + 0.14 * overcast + 0.06 * hz * day_light) + fl * 2.0
	var direct_daylight := day_light * (1.0 - overcast)
	env.ambient_light_energy *= 1.0 - 0.30 * direct_daylight
	env.ambient_light_sky_contribution = 0.56 + 0.24 * direct_daylight
	# The non-sky share: warm ground bounce by day, cool slate-blue at night.
	env.ambient_light_color = _ramp(el, [[-10.0, Color(0.36, 0.45, 0.66)], [2.0, Color(0.68, 0.58, 0.60)],
		[15.0, Color(0.76, 0.75, 0.74)], [40.0, Color(0.75, 0.79, 0.86)]]).lerp(Color(0.66, 0.71, 0.79), overcast * 0.65)
	env.tonemap_exposure = lerpf(1.02, 1.16, night) * lerpf(1.0, 1.08, overcast) * (1.0 + 0.03 * hz * day_light)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var alt := clampf((cam.global_position.y - 40.0) / 200.0, 0.0, 1.0) if cam else 0.0
	var hk := lerpf(1.0, 0.58, hz)
	env.fog_depth_begin = lerpf(185.0, 26.0, fog) * lerpf(1.0, 0.65, hz) * (1.0 + 0.8 * alt * (1.0 - fog))
	env.fog_depth_end = lerpf(1950.0, 620.0, fog) * hk * (1.0 + 0.45 * alt * (1.0 - fog))
	env.fog_density = lerpf(lerpf(0.48, 0.74, hz), 0.90, fog) * (1.0 - 0.14 * alt * (1.0 - fog))
	env.fog_depth_curve = lerpf(1.45, 1.15, hz)
	env.fog_light_color = fog_col
	env.fog_light_energy = lerpf(1.0, 0.58, night)
	env.fog_sun_scatter = (0.38 + 0.25 * hz) * day_light * (1.0 - overcast)
	env.fog_aerial_perspective = lerpf(0.78, 0.58, hz)
	env.fog_height = MIST_TOP + 4.0 * mist
	env.fog_height_density = MIST_DENSITY * mist
	env.glow_intensity = lerpf(0.24 + 0.04 * punch + 0.04 * hz, 0.48, night)
	env.glow_hdr_threshold = lerpf(1.38, 0.95, night)
	env.adjustment_contrast = 1.065 + (0.025 * punch - 0.02 * hz) * day_light - 0.015 * fog
	env.adjustment_saturation = 1.06 + (0.03 * punch - 0.025 * hz) * day_light - 0.025 * fog

	# --- shared shader inputs.
	var top_l := zen.srgb_to_linear()
	var hor_l := hor.srgb_to_linear()
	RenderingServer.global_shader_parameter_set("sky_top", Vector3(top_l.r, top_l.g, top_l.b))
	RenderingServer.global_shader_parameter_set("sky_horizon", Vector3(hor_l.r, hor_l.g, hor_l.b))
	RenderingServer.global_shader_parameter_set("sun_dir", sun.global_basis * Vector3.BACK)
	RenderingServer.global_shader_parameter_set("night", lamps)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	CarVisual.visible_wetness = wetness
	RenderingServer.global_shader_parameter_set("rain", w["rain"])
	CarVisual.lamps = lamps   # (your cars' headlights, lamp glows and brake-light boost)
	if _world and _world.has_method("set_night"):
		_world.set_night(lamps)
	rain_fx.set_rain(float(w["rain"]), hor_l, lamps)


## Sun height → colour, piecewise linear over [[elevation, Color], ...].
static func _ramp(x: float, keys: Array) -> Color:
	if x <= keys[0][0]:
		return keys[0][1]
	for i in keys.size() - 1:
		if x <= keys[i + 1][0]:
			var t := (x - float(keys[i][0])) / (float(keys[i + 1][0]) - float(keys[i][0]))
			return (keys[i][1] as Color).lerp(keys[i + 1][1], t)
	return keys[-1][1]


static func _rampf(x: float, keys: Array) -> float:
	if x <= keys[0][0]:
		return keys[0][1]
	for i in keys.size() - 1:
		if x <= keys[i + 1][0]:
			var t := (x - float(keys[i][0])) / (float(keys[i + 1][0]) - float(keys[i][0]))
			return lerpf(keys[i][1], keys[i + 1][1], t)
	return keys[-1][1]
