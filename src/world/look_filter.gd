class_name LookFilter
extends MeshInstance3D
## Full-screen stylisation quad parented to the game camera (see look.gdshader).
## Settings.look picks the style; "clean" hides the quad so it costs nothing.

const STYLES := {
	"clean": 0,
	"comic": 1,
	"toon": 2,
	"painted": 3,
	"crisp": 4,
	"cinematic": 5,
	"debug_pass": 8,
	"debug_edges": 9,
}
## Per-style shader parameters on top of the shader defaults.
const TUNING := {
	# Crisp (default since 0.7.3): a cleaner image, not a cartoon. Half-strength
	# small Kuwahara irons out texture noise/shimmer, thin depth outlines in a
	# darkened scene colour separate shapes, gentle grade. No bands, halftone,
	# haze, speed lines or vignette (the game draws its own fog and vignette).
	# 2026-11-20 visual pass: ~65% weaker (smoothing 0.55→0.18 flattened
	# paving and Blender detail into posterised patches; ink 0.55→0.3).
	"crisp": {"smooth_amount": 0.18, "line_px": 0.65, "depth_edge": 0.08, "color_edge": 0.6,
		"line_far": 220.0, "ink_amount": 0.3, "ink_shade": 1.0, "saturation": 1.05,
		"exposure": 1.0, "lift": 0.0, "split_tone": 0.06, "haze_amount": 0.0, "vignette": 0.0,
		"speed_lines": 0.0, "lens": 0.6},
	# Cinematic (default 2026-11-21): premium clean realism – sharpened, no
	# smoothing or ink, filmic contrast, faint cool-shadow/warm-light split.
	"cinematic": {"sharpen": 0.54, "clarity": 0.0, "film_contrast": 0.19, "film_toe": 0.006, "saturation": 1.08,
		"split_tone": 0.09, "shadow_tint": Color(0.84, 0.91, 1.06), "light_tint": Color(1.05, 1.01, 0.92),
		"vignette": 0.13, "lens": 0.44, "lens_distort": 0.012, "dither": 1.0},
	# Clean comic: crisp ink and flat cel tones, no halftone grain, gentle grade.
	"comic": {"line_px": 1.15, "bands": 3.0, "band_soft": 0.1, "saturation": 1.3, "halftone": 0.0,
		"color_edge": 0.38, "exposure": 1.06, "lift": 0.015, "split_tone": 0.22, "vignette": 0.12,
		"shadow_tint": Color(0.7, 0.62, 0.84)},
	"toon": {"line_px": 1.0, "bands": 4.0, "band_soft": 0.12, "saturation": 1.5, "halftone": 0.0,
		"color_edge": 0.4, "exposure": 1.12, "lift": 0.04, "split_tone": 0.35,
		"shadow_tint": Color(0.66, 0.5, 0.86), "vignette": 0.18},
	"painted": {"line_px": 0.9, "saturation": 1.3, "halftone": 0.0, "color_edge": 0.45,
		"depth_edge": 0.09, "exposure": 1.06, "split_tone": 0.4, "haze_amount": 0.5, "vignette": 0.3},
}

const LOOK_SHADER := preload("res://src/world/shaders/look.gdshader")
const CINEMATIC_SHADER := preload("res://src/world/shaders/look_cinematic.gdshader")

var mat: ShaderMaterial
var _speed := 0.0
var _uses_depth_shader := true


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	mat = ShaderMaterial.new()
	mat.shader = LOOK_SHADER
	mat.render_priority = 100  # after other transparent surfaces, before the web (127)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0  # the vertex shader ignores the transform
	# (Full screen in every camera that sees it: not in the water mirror's,
	# where it painted over the whole reflection.)
	layers = WaterMirror.LAYER
	ignore_occlusion_culling = true
	var settings := get_node_or_null("/root/Settings")
	if settings:
		if not settings.changed.is_connected(_on_settings_changed):
			settings.changed.connect(_on_settings_changed)
		set_style(settings.look)


func _exit_tree() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings and settings.changed.is_connected(_on_settings_changed):
		settings.changed.disconnect(_on_settings_changed)


func _on_settings_changed() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings:
		set_style(settings.look)


func set_style(look: String) -> void:
	var id: int = STYLES.get(look, 0)
	# The web build's Compatibility renderer hands back an empty screen/depth
	# copy here (the whole frame washes out white), so it stays clean there.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		id = 0
	visible = id != 0
	if id == 0:
		return
	# "cinematic" uses the dedicated MSAA-safe shader (hint_screen_texture only,
	# no hint_depth_texture) so hardware MSAA stays active on Mobile.
	var use_cinematic := look == "cinematic"
	var want_shader: Shader = CINEMATIC_SHADER if use_cinematic else LOOK_SHADER
	if mat.shader != want_shader:
		mat.shader = want_shader
	_uses_depth_shader = not use_cinematic
	var defaults := mat.shader.get_shader_uniform_list()
	var valid_uniforms := {}
	for u in defaults:
		var uname := String(u["name"])
		valid_uniforms[uname] = true
		mat.set_shader_parameter(uname, null)  # back to shader default
	if valid_uniforms.has("style"):
		mat.set_shader_parameter("style", id)
	# The screen copy only holds the opaque pass. Crisp & Cinematic draw FIRST
	# among the transparent surfaces so water, glass, rain and particles land
	# on top of them. Cartoon styles keep the old order (before the web at 127).
	mat.render_priority = -128 if look in ["crisp", "cinematic"] else 100
	var t: Dictionary = TUNING.get(look, {})
	for k in t:
		if valid_uniforms.has(k):
			mat.set_shader_parameter(k, t[k])


## 0..1 how fast the hero is going (speed lines); smoothed here.
func set_speed(amount: float, dt: float) -> void:
	_speed = lerpf(_speed, clampf(amount, 0.0, 1.0), 1.0 - exp(-4.0 * dt))
	if visible and _uses_depth_shader:
		mat.set_shader_parameter("speed", _speed)
