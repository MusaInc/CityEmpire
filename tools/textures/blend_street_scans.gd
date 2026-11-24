extends SceneTree
## Merge the normalized CC0 scan detail with the existing WorldState studies.
## The result keeps luminance, XY normal and roughness in one sample.

const DIR := "res://assets/textures/pbr/"


func _initialize() -> void:
	var ok := _blend("worldstate_street_asphalt.png", "asphalt_01.png", "street_asphalt_scan.png")
	ok = _blend("worldstate_pavement_concrete.png", "concrete_pavement.png", "pavement_concrete_scan.png") and ok
	quit(0 if ok else 1)


func _blend(study: String, scan: String, result: String) -> bool:
	var base := Image.load_from_file(DIR + study)
	var detail := Image.load_from_file(DIR + scan)
	if base == null or detail == null:
		return false
	base.convert(Image.FORMAT_RGBA8)
	detail.convert(Image.FORMAT_RGBA8)
	detail.resize(base.get_width(), base.get_height(), Image.INTERPOLATE_LANCZOS)
	for y in base.get_height():
		for x in base.get_width():
			var a := base.get_pixel(x, y)
			var b := detail.get_pixel(x, y)
			base.set_pixel(x, y, Color(lerpf(a.r, b.r, 0.64), lerpf(a.g, b.g, 0.66),
				lerpf(a.b, b.b, 0.66), lerpf(a.a, b.a, 0.70)))
	return base.save_png(DIR + result) == OK
