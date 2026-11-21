extends SceneTree
## Packs a Poly Haven (CC0) PBR set into one RGBA detail texture for the
## city shaders: R = albedo luminance normalised to mean 0.5, G/B = OpenGL
## normal x/y (z rebuilt in the shader), A = roughness. One sampler, one
## VRAM-compressed texture per material (mobile budget).
##   godot --headless -s res://tools/textures/pack_detail.gd -- <dir> <name> <out.png>
##   ... -- --albedo <image.png> <out.png> [normal strength]
## The second form takes a colour-only (tileable) image – e.g. the generated
## WorldState material studies – and derives the normal from its luminance as
## height (wrapping, so it stays tileable) and roughness from it (darker gaps
## such as mortar read rougher).
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a[0] == "--albedo":
		_from_albedo(a[1], a[2], float(a[3]) if a.size() > 3 else 3.0)
		quit()
		return
	var dir := a[0]
	var name := a[1]
	var dif := Image.load_from_file("%s/%s_diff_1k.jpg" % [dir, name])
	var nor := Image.load_from_file("%s/%s_nor_gl_1k.jpg" % [dir, name])
	var rou := Image.load_from_file("%s/%s_rough_1k.jpg" % [dir, name])
	var w := dif.get_width()
	var h := dif.get_height()
	var mean := 0.0
	for y in h:
		for x in w:
			var c := dif.get_pixel(x, y)
			mean += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	mean /= float(w * h)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := dif.get_pixel(x, y)
			var l := (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) / maxf(mean, 0.01) * 0.5
			var n := nor.get_pixel(x, y)
			out.set_pixel(x, y, Color(clampf(l, 0.0, 1.0), n.r, n.g, rou.get_pixel(x, y).r))
	out.save_png(a[2])
	print("packed %s: mean luminance %.3f" % [name, mean])
	quit()


func _from_albedo(src: String, dst: String, strength: float) -> void:
	var img := Image.load_from_file(src)
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var mean := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			lum[y * w + x] = l
			mean += l
	mean /= float(w * h)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var l := lum[y * w + x]
			var dx := lum[y * w + (x + 1) % w] - lum[y * w + (x - 1 + w) % w]
			var dy := lum[((y + 1) % h) * w + x] - lum[((y - 1 + h) % h) * w + x]
			var n := Vector3(-dx * strength, dy * strength, 1.0).normalized()
			var rough := clampf(0.72 + 0.3 * (mean - l) / maxf(mean, 0.01), 0.45, 1.0)
			out.set_pixel(x, y, Color(clampf(l / maxf(mean, 0.01) * 0.5, 0.0, 1.0), n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, rough))
	out.save_png(dst)
	print("packed %s from albedo: mean luminance %.3f" % [src.get_file(), mean])
