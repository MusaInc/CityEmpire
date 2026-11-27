class_name Brand
extends RefCounted
## WorldState's identity in one place: the gold W (assets/brand/w_mask.png,
## geometry from tools/brand/w_mark.py), the wordmark, and the colours the
## launch screen, title and phone share. The app icon and the launch image
## are rendered by the same script, so every W is the same W.

const NAVY_DEEP := Color(0.0353, 0.051, 0.0863)   # = boot_splash/bg_color (launch screen)
const NAVY := Color(0.063, 0.094, 0.157)
const GOLD := Color("#e1bd6a")
const GOLD_TEXT := Color("#e8c983")
const IVORY := Color("#f1ece2")
const MARK_ASPECT := 0.78      # height / width (tools/brand/w_mark.py H)
const SPLASH_FRAC := 0.22      # launch.png: mark width / the window's short side
const MASK := preload("res://assets/brand/w_mask.png")
const SHADER := preload("res://src/empire/ui/brand_mark.gdshader")


## The gold W at `width` px. sweep()/sweep_k drive the metallic highlight.
class Mark extends TextureRect:
	var mat: ShaderMaterial

	func _init(width := 48.0) -> void:
		texture = Brand.MASK
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_SCALE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mat = ShaderMaterial.new()
		mat.shader = Brand.SHADER
		material = mat
		set_width(width)

	func set_width(w: float) -> void:
		custom_minimum_size = Vector2(w, w * Brand.MARK_ASPECT)
		size = custom_minimum_size

	## One light sweep across the metal (seconds).
	func shine(dur := 1.3, strength := 0.55) -> Tween:
		var tw := create_tween()
		mat.set_shader_parameter("sweep_k", strength)
		tw.tween_method(func(v: float): mat.set_shader_parameter("sweep", v), -0.45, 1.45, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): mat.set_shader_parameter("sweep_k", 0.0))
		return tw


## The splash W's breathing halo: the same mask, blurred, on a rect grown
## round a Mark by `margin` × its width each side (place it with fit()).
class Glow extends TextureRect:
	const GLOW_SHADER := preload("res://src/empire/ui/brand_glow.gdshader")
	var mat: ShaderMaterial
	var margin := 0.45

	func _init() -> void:
		texture = Brand.MASK
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_SCALE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mat = ShaderMaterial.new()
		mat.shader = GLOW_SHADER
		mat.set_shader_parameter("mask_tex", Brand.MASK)
		material = mat

	func fit(mark: Control) -> void:
		var g := mark.size.x * margin
		position = mark.position - Vector2(g, g)
		size = mark.size + Vector2(g, g) * 2.0
		mat.set_shader_parameter("pad", Vector2(g / size.x, g / size.y))

	func set_strength(k: float) -> void:
		mat.set_shader_parameter("k", k)


## Mark + tracked WORLDSTATE caps. `h` = the mark's height.
class Wordmark extends HBoxContainer:
	var mark: Mark
	var word: Label

	func _init(h := 40.0, col := Brand.IVORY) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", int(h * 0.42))
		alignment = BoxContainer.ALIGNMENT_BEGIN
		mark = Mark.new(h / Brand.MARK_ASPECT)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(mark)
		word = Label.new()
		word.text = "WORLDSTATE"
		var fv := FontVariation.new()
		fv.base_font = Glass.font("medium")
		fv.spacing_glyph = int(round(h * 0.16))
		word.add_theme_font_override("font", fv)
		word.add_theme_font_size_override("font_size", int(round(h * 0.52)))
		word.add_theme_color_override("font_color", col)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		word.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(word)
