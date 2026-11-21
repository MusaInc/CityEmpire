extends SceneTree
## Packs a Poly Haven (CC0) PBR set into one RGBA detail texture for the
## city shaders: R = albedo luminance normalised to mean 0.5, G/B = OpenGL
## normal x/y (z rebuilt in the shader), A = roughness. One sampler, one
## VRAM-compressed texture per material (mobile budget).
##   godot --headless -s res://tools/textures/pack_detail.gd -- <dir> <name> <out.png>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
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
