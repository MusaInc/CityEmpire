class_name EmpireWidgets
extends RefCounted
## Drawn interface pieces: the phone's line icons (no emoji – they don't
## exist in every system font) and the brand studio's shopfront preview.


## A 2 px line icon, drawn in `color` in a square box.
class Icon extends Control:
	var key := ""
	var color := Color.WHITE

	func _init(p_key := "", p_color := Color.WHITE, px := 26.0) -> void:
		key = p_key
		color = p_color
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	var _o := Vector2.ZERO
	var _s := 1.0

	func _pt(x: float, y: float) -> Vector2:
		return _o + Vector2(x, y) * _s

	func _draw() -> void:
		var s := minf(size.x, size.y)
		_s = s
		_o = (size - Vector2(s, s)) * 0.5
		var w := maxf(2.0, s / 13.0)
		var c := color
		match key:
			"businesses":
				# A shopfront: striped awning over a window and a door.
				draw_rect(Rect2(_pt(0.12, 0.42), Vector2(0.76, 0.48) * s), c, false, w)
				var aw := PackedVector2Array([_pt(0.06, 0.22), _pt(0.94, 0.22), _pt(0.9, 0.42), _pt(0.1, 0.42)])
				draw_colored_polygon(aw, Color(c, 0.35))
				draw_polyline(aw + PackedVector2Array([aw[0]]), c, w, true)
				for i in 3:
					var x := 0.25 + i * 0.25
					draw_line(_pt(x, 0.22), _pt(x - 0.02, 0.42), c, w)
				draw_rect(Rect2(_pt(0.56, 0.6), Vector2(0.2, 0.3) * s), c, false, w)
				draw_rect(Rect2(_pt(0.22, 0.56), Vector2(0.24, 0.16) * s), Color(c, 0.5))
			"city":
				draw_rect(Rect2(_pt(0.1, 0.45), Vector2(0.22, 0.45) * s), c, false, w)
				draw_rect(Rect2(_pt(0.38, 0.12), Vector2(0.24, 0.78) * s), c, false, w)
				draw_rect(Rect2(_pt(0.68, 0.32), Vector2(0.22, 0.58) * s), c, false, w)
				for y in 3:
					draw_line(_pt(0.45, 0.25 + y * 0.18), _pt(0.55, 0.25 + y * 0.18), c, w)
			"map":
				var pin := _pt(0.5, 0.38)
				draw_arc(pin, s * 0.22, PI * 0.82, PI * 2.18, 24, c, w, true)
				draw_line(pin + Vector2(-0.19, 0.11) * s, _pt(0.5, 0.88), c, w, true)
				draw_line(pin + Vector2(0.19, 0.11) * s, _pt(0.5, 0.88), c, w, true)
				draw_circle(pin, s * 0.07, c)
			"bank":
				draw_colored_polygon(PackedVector2Array([_pt(0.5, 0.08), _pt(0.92, 0.32), _pt(0.08, 0.32)]), Color(c, 0.35))
				draw_polyline(PackedVector2Array([_pt(0.08, 0.32), _pt(0.5, 0.08), _pt(0.92, 0.32), _pt(0.08, 0.32)]), c, w, true)
				for i in 4:
					var x := 0.2 + i * 0.2
					draw_line(_pt(x, 0.4), _pt(x, 0.76), c, w)
				draw_line(_pt(0.08, 0.86), _pt(0.92, 0.86), c, w * 1.4)
			"company":
				draw_rect(Rect2(_pt(0.08, 0.3), Vector2(0.84, 0.56) * s), c, false, w)
				draw_rect(Rect2(_pt(0.36, 0.14), Vector2(0.28, 0.16) * s), c, false, w)
				draw_line(_pt(0.08, 0.54), _pt(0.92, 0.54), c, w)
				draw_rect(Rect2(_pt(0.44, 0.48), Vector2(0.12, 0.12) * s), c)
			"vehicles":
				var body := PackedVector2Array([_pt(0.06, 0.7), _pt(0.06, 0.52), _pt(0.24, 0.48), _pt(0.36, 0.3),
					_pt(0.68, 0.3), _pt(0.82, 0.48), _pt(0.94, 0.52), _pt(0.94, 0.7), _pt(0.06, 0.7)])
				draw_polyline(body, c, w, true)
				draw_line(_pt(0.24, 0.48), _pt(0.82, 0.48), c, w)
				for x: float in [0.27, 0.73]:
					draw_circle(_pt(x, 0.72), s * 0.1, c)
			"property":
				draw_polyline(PackedVector2Array([_pt(0.06, 0.48), _pt(0.5, 0.1), _pt(0.94, 0.48)]), c, w, true)
				draw_polyline(PackedVector2Array([_pt(0.18, 0.4), _pt(0.18, 0.88), _pt(0.82, 0.88), _pt(0.82, 0.4)]), c, w, true)
				draw_rect(Rect2(_pt(0.42, 0.6), Vector2(0.16, 0.28) * s), c)
			"goals":
				draw_line(_pt(0.2, 0.08), _pt(0.2, 0.92), c, w)
				var fl := PackedVector2Array([_pt(0.2, 0.12), _pt(0.86, 0.12), _pt(0.72, 0.3), _pt(0.86, 0.48), _pt(0.2, 0.48)])
				draw_colored_polygon(fl, Color(c, 0.35))
				draw_polyline(fl, c, w, true)
			"game":
				var cc := _pt(0.5, 0.5)
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(cc + Vector2.from_angle(a) * s * 0.26, cc + Vector2.from_angle(a) * s * 0.42, c, w * 1.6)
				draw_arc(cc, s * 0.27, 0.0, TAU, 32, c, w, true)
				draw_arc(cc, s * 0.1, 0.0, TAU, 20, c, w, true)
			"brand":
				draw_arc(_pt(0.5, 0.5), s * 0.4, 0.0, TAU, 32, c, w, true)
				for i in 4:
					draw_circle(_pt(0.5, 0.5) + Vector2.from_angle(-PI * 0.75 + i * 0.5) * s * 0.24, s * 0.07, c)
			"tower":
				draw_rect(Rect2(_pt(0.32, 0.18), Vector2(0.36, 0.72) * s), c, false, w)
				draw_line(_pt(0.5, 0.04), _pt(0.5, 0.18), c, w)
				for y in 4:
					draw_line(_pt(0.4, 0.3 + y * 0.14), _pt(0.6, 0.3 + y * 0.14), c, w)
			"megaphone":
				draw_colored_polygon(PackedVector2Array([_pt(0.16, 0.38), _pt(0.72, 0.14), _pt(0.72, 0.82), _pt(0.16, 0.6)]), Color(c, 0.35))
				draw_polyline(PackedVector2Array([_pt(0.16, 0.38), _pt(0.72, 0.14), _pt(0.72, 0.82), _pt(0.16, 0.6), _pt(0.16, 0.38)]), c, w, true)
				draw_line(_pt(0.3, 0.64), _pt(0.36, 0.88), c, w)
				draw_arc(_pt(0.74, 0.48), s * 0.16, -PI * 0.35, PI * 0.35, 12, c, w, true)
			_:
				draw_circle(_pt(0.5, 0.5), s * 0.3, c)


## A shopfront drawn with a brand (ShopStyle.house_ident): stone frame,
## fascia in the brand's sign style with the name in its face and the logo
## roundel, a striped awning, lit windows and a door.
class BrandPreview extends Control:
	var ident := {}
	var night := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var prim: Color = ident.get("primary", Color("#0f3d5c"))
		var acc: Color = ident.get("accent", Color("#f5b13d"))
		var face := String(ident.get("face", "display"))
		var sign := String(ident.get("sign", "lightbox"))
		var nm := String(ident.get("name", ""))
		if nm == "":
			nm = "Your Company"
		var sky := Color("#1b2b38") if not night else Color("#0a1118")
		draw_rect(r, sky)
		# The building: stone with upper windows.
		var stone := Color(0.82, 0.79, 0.73) if not night else Color(0.42, 0.41, 0.4)
		var bx := Rect2(Vector2(size.x * 0.04, size.y * 0.04), Vector2(size.x * 0.92, size.y * 0.96))
		draw_rect(bx, stone)
		for i in 5:
			var wx := bx.position.x + bx.size.x * (0.06 + i * 0.19)
			draw_rect(Rect2(Vector2(wx, bx.position.y + size.y * 0.05), Vector2(bx.size.x * 0.12, size.y * 0.13)),
				Color(0.2, 0.26, 0.32) if not night else Color(0.95, 0.82, 0.5, 0.8))
		# Fascia.
		var fy := size.y * 0.27
		var fh := size.y * 0.17
		var fr := Rect2(Vector2(bx.position.x + size.x * 0.03, fy), Vector2(bx.size.x - size.x * 0.06, fh))
		var fas := prim
		var ink := acc
		match sign:
			"lightbox":
				fas = acc if acc.get_luminance() > 0.6 else Color(0.96, 0.96, 0.95)
				ink = prim
			"neon":
				fas = Color(0.06, 0.06, 0.07)
				ink = acc.lightened(0.15)
		draw_rect(fr, fas)
		draw_rect(Rect2(fr.position + Vector2(0, -size.y * 0.018), Vector2(fr.size.x, size.y * 0.018)), stone.darkened(0.25))
		# Logo roundel.
		var lc := fr.position + Vector2(fh * 0.62, fh * 0.5)
		draw_circle(lc, fh * 0.4, acc if sign != "lightbox" else prim)
		draw_circle(lc, fh * 0.33, prim if sign != "lightbox" else acc)
		var f: Font = ShopStyle.font(face)
		var ini := String(ident.get("initial", nm.left(1).to_upper()))
		var isz := int(fh * 0.5)
		var iw := f.get_string_size(ini, HORIZONTAL_ALIGNMENT_LEFT, -1, isz).x
		draw_string(f, lc + Vector2(-iw * 0.5, isz * 0.36), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, isz,
			acc if sign != "lightbox" else prim)
		# The name, fitted to the fascia.
		var txt := nm if face in ["script", "retro"] else nm.to_upper()
		var avail := fr.size.x - fh * 1.5
		var fs := int(fh * 0.62)
		while fs > 10 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
			fs -= 1
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := Vector2(fr.position.x + fh * 1.2 + (avail - tw) * 0.5, fr.position.y + fh * 0.5 + fs * 0.34)
		if sign == "neon":
			for g in 3:
				draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6 + g * 4, Color(ink, 0.12))
		draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		# Awning stripes.
		var ay := fy + fh
		var ah := size.y * 0.1
		var n := 12
		for i in n:
			var x0 := fr.position.x + fr.size.x * i / n
			var x1 := fr.position.x + fr.size.x * (i + 1) / n
			var poly := PackedVector2Array([Vector2(x0, ay), Vector2(x1, ay), Vector2(x1 + 4, ay + ah), Vector2(x0 + 4, ay + ah)])
			draw_colored_polygon(poly, prim if i % 2 == 0 else acc.lerp(Color.WHITE, 0.15))
		# Windows and the door.
		var gy := ay + ah
		var gh := bx.end.y - gy - size.y * 0.06
		var glass := Color(0.55, 0.68, 0.74) if not night else Color(1.0, 0.88, 0.62)
		var dx := fr.position.x + fr.size.x * 0.42
		var dw := fr.size.x * 0.16
		for seg in [[fr.position.x, dx], [dx + dw, fr.end.x]]:
			var wr := Rect2(Vector2(float(seg[0]) + 6, gy + 6), Vector2(float(seg[1]) - float(seg[0]) - 12, gh - 6))
			draw_rect(wr, glass)
			draw_rect(Rect2(wr.position, Vector2(wr.size.x, wr.size.y * 0.35)), Color(1, 1, 1, 0.12))
			draw_rect(wr, prim.darkened(0.4), false, 4.0)
			# A poster in the glass.
			draw_rect(Rect2(wr.position + Vector2(wr.size.x * 0.12, wr.size.y * 0.2), Vector2(wr.size.x * 0.28, wr.size.y * 0.42)), acc)
		draw_rect(Rect2(Vector2(dx + 4, gy + 6), Vector2(dw - 8, gh - 6)), glass.darkened(0.25))
		draw_rect(Rect2(Vector2(dx + 4, gy + 6), Vector2(dw - 8, gh - 6)), prim.darkened(0.4), false, 4.0)
		draw_line(Vector2(dx + dw * 0.75, gy + gh * 0.45), Vector2(dx + dw * 0.75, gy + gh * 0.7), Color(0.85, 0.85, 0.85), 3.0)
		# Pavement.
		draw_rect(Rect2(Vector2(0, bx.end.y - size.y * 0.06), Vector2(size.x, size.y * 0.06)), Color(0.55, 0.55, 0.53))
