class_name RenderLab
extends CanvasLayer
## Rendering-only controls and metrics shared by the on-device HUD and capture tool.

const PROFILES := [["reference", "Reference"], ["hybrid", "Hybrid"], ["balanced", "Balanced"], ["quality", "Quality"], ["gi", "GI study"]]
const UPSCALERS := [["auto", "Auto"], ["spatial", "Spatial"], ["temporal", "Temporal"]]
const PROBE_LAYER := 1 << 18

static var last_sample := {}

var _label: Label
var _elapsed := 0.0
var _last_us := 0
var _frame_ms: Array[float] = []


static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


static func lab_effects(profile: String) -> bool:
	return forward_plus() and profile in ["balanced", "quality", "gi"]


static func scaling_mode(preference: String, profile: String) -> Viewport.Scaling3DMode:
	var rd := RenderingServer.get_rendering_device()
	var forward := forward_plus()
	if rd and RenderingServer.get_current_rendering_driver_name() == "metal":
		var temporal := rd.has_feature(RenderingDevice.SUPPORTS_METALFX_TEMPORAL)
		if forward and temporal and preference != "spatial" and (lab_effects(profile) or preference == "temporal"):
			return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
		if rd.has_feature(RenderingDevice.SUPPORTS_METALFX_SPATIAL):
			return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	if forward and preference != "spatial" and lab_effects(profile):
		return Viewport.SCALING_3D_MODE_FSR2
	return Viewport.SCALING_3D_MODE_BILINEAR


static func min_scale(mode: Viewport.Scaling3DMode) -> float:
	if mode == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL:
		var rd := RenderingServer.get_rendering_device()
		if rd:
			return clampf(float(rd.limit_get(RenderingDevice.LIMIT_METALFX_TEMPORAL_SCALER_MIN_SCALE)) / 1e6, 0.42, 1.0)
	return 0.42


static func scale_name(mode: Viewport.Scaling3DMode) -> String:
	match mode:
		Viewport.SCALING_3D_MODE_METALFX_SPATIAL: return "MetalFX spatial"
		Viewport.SCALING_3D_MODE_METALFX_TEMPORAL: return "MetalFX temporal"
		Viewport.SCALING_3D_MODE_FSR2: return "FSR2"
		Viewport.SCALING_3D_MODE_FSR: return "FSR"
		_: return "Bilinear"


static func configure_environment(env: Environment, sun: DirectionalLight3D, profile: String) -> void:
	var enhancements := lab_effects(profile)
	var quality := enhancements and profile in ["quality", "gi"]
	env.ssao_enabled = enhancements
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.3
	env.ssao_detail = 0.55
	env.ssao_sharpness = 0.95
	env.ssil_enabled = quality and profile != "gi"
	env.ssil_radius = 2.2
	env.ssil_intensity = 0.72
	env.ssr_max_steps = 32
	env.ssr_depth_tolerance = 0.15
	env.sdfgi_enabled = enhancements and profile == "gi"
	env.sdfgi_min_cell_size = 0.35
	env.sdfgi_cascades = 4
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 0.55
	env.volumetric_fog_length = 42.0
	env.volumetric_fog_detail_spread = 2.6
	env.volumetric_fog_sky_affect = 0.15
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_temporal_reprojection_amount = 0.72
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.52
	sun.light_angular_distance = 1.1 if quality else 1.0
	if forward_plus():
		var scatter := quality and RenderingServer.get_current_rendering_driver_name() == "metal"
		RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW if scatter else RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED)
		RenderingServer.global_shader_parameter_set("lab_skin_sss", 0.18 if scatter else 0.0)


static func weather_effects(env: Environment, profile: String, wet: float, rain: float, fog: float, indoors: bool) -> void:
	var rich := lab_effects(profile) and profile in ["quality", "gi"]
	var reflections := rich and (wet > 0.15 or indoors)
	var haze := rich and not indoors and maxf(rain, fog) > 0.16
	if env.ssr_enabled != reflections:
		env.ssr_enabled = reflections
	if env.volumetric_fog_enabled != haze:
		env.volumetric_fog_enabled = haze
	if haze:
		env.volumetric_fog_density = 0.003 + fog * 0.010 + rain * 0.003


static func metrics(vp: Viewport) -> Dictionary:
	var rid := vp.get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return {
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"gpu_ms": snappedf(gpu, 0.01) if gpu > 0.0 else null,
		"render_cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.01),
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mib": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mib": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"scale": snappedf(vp.scaling_3d_scale, 0.001),
		"upscaler": scale_name(vp.scaling_3d_mode),
	}


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.position.y = 12.0
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	Settings.changed.connect(_sync)
	_sync()


func _sync() -> void:
	var on := Settings.lab_metrics and DisplayServer.get_name() != "headless"
	_label.visible = on
	_frame_ms.clear()
	_elapsed = 0.0
	_last_us = Time.get_ticks_usec()
	set_process(on)
	if on:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var frame := (now - _last_us) * 0.001
	_last_us = now
	if frame > 1500.0:
		_frame_ms.clear()
		_elapsed = 0.0
		return
	_frame_ms.append(frame)
	_elapsed += frame
	if _elapsed < 850.0:
		return
	var m := metrics(get_viewport())
	_frame_ms.sort()
	var p95 := _frame_ms[floori((_frame_ms.size() - 1) * 0.95)]
	m["profile"] = Settings.lab_profile
	m["frames"] = _frame_ms.size()
	m["frame_p50_ms"] = snappedf(_frame_ms[floori((_frame_ms.size() - 1) * 0.50)], 0.01)
	m["frame_p95_ms"] = snappedf(p95, 0.01)
	last_sample = m
	var gpu := "GPU —" if m["gpu_ms"] == null else "GPU %.1f ms" % m["gpu_ms"]
	_label.text = "%s / %s   ·   %s   ·   %s %.0f%%\n%.0f FPS · p95 %.1f ms · %s · %d draws · %.0f MiB GPU" % [
		m["renderer"], m["driver"], Settings.lab_profile.capitalize(), m["upscaler"], float(m["scale"]) * 100.0,
		_frame_ms.size() * 1000.0 / _elapsed, p95, gpu, m["draws"], m["video_mib"]]
	_frame_ms.clear()
	_elapsed = 0.0
