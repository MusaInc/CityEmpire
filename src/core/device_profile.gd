class_name DeviceProfile
extends RefCounted
## Performance profile by device (2026-11-27 engine pass): picks the
## first-launch graphics preset and frame-rate target from the iPhone /
## iPad model and its memory, so capable devices start at 60 fps on High,
## mid-range ones at 60 on Medium (the FrameGovernor trades resolution, then
## locks a steady 30 if 60 can't be held), and older ones at a steady 30 on
## Low. Used once: after that the player's own Settings choices stand.
##
## Model identifiers ("iPhone15,2") – the major number is the chip
## generation: iPhone 14+ = A15 and later, 12–13 = A13/A14; iPad 13+ = M1 /
## A14 and later, 8–12 = A12/A13.


static func classify(model := "", ram_bytes := -1) -> Dictionary:
	if model == "":
		model = OS.get_model_name()
	if ram_bytes < 0:
		var mi := OS.get_memory_info()
		ram_bytes = int(mi.get("physical", -1))
	var tier := "high"
	var re := RegEx.create_from_string("^(iPhone|iPad|iPod)(\\d+),\\d+$")
	var m := re.search(model)
	if m:
		var fam := m.get_string(1)
		var major := int(m.get_string(2))
		if fam == "iPhone":
			tier = "high" if major >= 14 else ("mid" if major >= 12 else "low")
		elif fam == "iPad":
			tier = "high" if major >= 13 else ("mid" if major >= 8 else "low")
		else:
			tier = "low"
	elif OS.get_name() in ["iOS", "Android"]:
		tier = "mid"   # (an unknown phone: the governor adapts from here)
	# Memory caps the tier whatever the chip (textures, streaming caches).
	if ram_bytes > 0 and ram_bytes < 3.5e9:
		tier = "low"
	elif ram_bytes > 0 and ram_bytes < 5.5e9 and tier == "high":
		tier = "mid"
	match tier:
		"high":
			return {"tier": tier, "quality": 2, "fps_60": true}
		"mid":
			return {"tier": tier, "quality": 1, "fps_60": true}
		_:
			return {"tier": tier, "quality": 0, "fps_60": false}
