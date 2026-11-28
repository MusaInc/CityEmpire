class_name SkyportUI
extends RefCounted
## Panels for Skyport Island's showrooms and sites, built with EmpireUI's
## own parts (one look everywhere): the vehicle card you get walking up to a
## display car (or picking from a showroom), showroom lists for the dealers,
## aviation sales and the marina, airport cargo imports, the terminal desk
## and the property investment list.

const S = preload("res://src/empire/ui/empire_style.gd")


static func _specs(md: Dictionary) -> String:
	match String(md.get("class", "car")):
		"heli":
			return "Cruise %d kt · climb %d m/s · %d seats" % [int(float(md["cruise"]) * 1.944), int(md["climb"]), int(md.get("seats", 2))]
		"plane":
			return "Cruise %d kt · top %d kt · %d seats" % [int(float(md["cruise"]) * 1.944), int(float(md["vmax"]) * 1.944), int(md.get("seats", 4))]
		"boat":
			return "Top %d kt" % int(float(md["vmax"]) * 1.944)
	return "Top %d mph · %d cases" % [int(float(md.get("top_speed", 30.0)) * 2.237), int(md.get("cargo", 8))]


static func _running(md: Dictionary) -> String:
	var cls := String(md.get("class", "car"))
	if cls == "car":
		return "Fuel about %s per 100 km" % EmpireData.money(float(EmpireData.economy().get("fuel_per_km", 0.2)) * 100.0)
	return "%s fee %s a day · fuel %s per 100 km" % ["Marina" if cls == "boat" else "Hangar", EmpireData.money(float(md.get("fee", 0.0))),
		EmpireData.money(float(EmpireData.economy().get("fuel_per_km", 0.2)) * (150.0 if cls == "boat" else 300.0))]


static func _owned(ui: EmpireUI, model: String) -> int:
	var n := 0
	for v in ui.game.empire.vehicles:
		if String(v["model"]) == model and not v.get("test", false):
			n += 1
	return n


## The card for one vehicle: what it is, what it costs to buy and run,
## buy it or try it.
static func vehicle_card(ui: EmpireUI, model: String, site: String) -> void:
	var md := EmpireData.vehicle_model(model)
	var cls := String(md.get("class", "car"))
	var price := float(md.get("price", 0))
	var v := ui._open(String(md.get("name", model)), 790 if cls == "car" else 825, 440 if cls == "car" else 465)
	var gallery := S.hbox(22)
	v.add_child(gallery)
	var preview := S.vbox(5)
	gallery.add_child(preview)
	if cls == "car":
		var car_shot := Glass.rounded(ui.thumbs.vehicle(model, Vector2(310, 195)), Vector2(310, 195), 20)
		preview.add_child(car_shot)
	else:
		preview.add_child(_craft_preview(model, cls))
		preview.add_child(S.label("Drag to rotate", 13, S.MUTED))
	var detail := S.vbox(10)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.alignment = BoxContainer.ALIGNMENT_CENTER
	gallery.add_child(detail)
	var description := S.label(String(md.get("desc", "A good everyday car" if cls == "car" else "")), 17, S.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not description.text.is_empty():
		detail.add_child(description)
	var top := S.hbox(16)
	top.add_child(S.label(EmpireData.money(price), 40, S.PAPER, "black"))
	var own := _owned(ui, model)
	if own > 0:
		top.add_child(S.chip("You own %d" % own, S.GREEN))
	if model == "used_kestrel":
		top.add_child(S.chip("Used · 82% condition", S.AMBER))
	detail.add_child(top)
	for item in [[_specs(md), S.PAPER], [_running(md), S.MUTED]]:
		var line := S.label(item[0], 16, item[1])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(line)
	var acts := S.hbox(10)
	var buy_cb := func() -> void:
		var err := ""
		if cls == "car":
			err = ui.game.skyport_play.buy_car(model, site)
		else:
			err = ui.game.skyport_play.buy(model)
		if err != "":
			ui.toast(err, "bad")
			return
		Sfx.play("cash", -3.0)
		ui.close_panel(true)
		ui.toast("It's yours: %s" % ({"car": "parked on the forecourt", "heli": "on the helipad – the GPS shows where",
			"plane": "on a stand by the hangars", "boat": "in a berth at the marina"}.get(cls, "")), "good")
	var buy_lbl := "Buy · %s" % EmpireData.money(price)
	if price >= 25000.0:
		var cb := Glass.confirm_button(buy_lbl, "Confirm · %s" % EmpireData.money(price), buy_cb, "regular")
		cb.custom_minimum_size.x = 220
		acts.add_child(cb)
	else:
		acts.add_child(S.button(buy_lbl, buy_cb, true, 220))
	acts.add_child(S.button({"car": "Test drive", "boat": "Test sail"}.get(cls, "Test flight"), func():
		ui.game.skyport_play.start_test(model, site), false, 180))
	acts.add_child(S.spacer())
	acts.add_child(S.button("Back", func(): showroom(ui, site) if site in SkyportPlay.STOCK else ui.close_panel(true), false, 110))
	v.add_child(acts)


static func _craft_preview(model: String, cls: String) -> Control:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(345, 240)
	container.stretch = true
	var view := SubViewport.new()
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(view)
	var environment := WorldEnvironment.new()
	var studio := Environment.new()
	studio.background_mode = Environment.BG_COLOR
	studio.background_color = Color("263741")
	studio.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	studio.ambient_light_color = Color("c0d4e5")
	studio.ambient_light_energy = 0.66
	environment.environment = studio
	view.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -24, 0)
	key.light_energy = 1.25
	view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-27, 151, 0)
	rim.light_energy = 0.68
	rim.light_color = Color("deebed")
	view.add_child(rim)

	var spec := SkyportPlay.craft_spec(model)
	var craft := CraftModels.build(cls, model, spec)
	view.add_child(craft)
	craft.rotation.y = -0.60
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var size: Vector3 = spec["size"]
	var radius := maxf(size.z, size.x)
	cam.size = radius * 0.88
	view.add_child(cam)
	var eye := Vector3(1.25, 0.72, 1.4) * radius
	cam.transform = Transform3D(Basis.looking_at(Vector3.UP * size.y * 0.36 - eye), eye)
	cam.current = true
	container.gui_input.connect(func(event: InputEvent):
		var drag := 0.0
		if event is InputEventScreenDrag:
			drag = event.relative.x
		elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			drag = event.relative.x
		if not is_zero_approx(drag):
			craft.rotate_y(drag * 0.012)
			view.render_target_update_mode = SubViewport.UPDATE_ONCE
			container.accept_event())
	return container


## A showroom's list (dealers, aviation, marina): one row each with a real
## thumbnail, tap for the card. Kestrel Motors adds "run this dealership".
static func showroom(ui: EmpireUI, site: String) -> void:
	var st := ui.game.skyport_play.site(site)
	var v := ui._open(String(st.get("name", "Showroom")), 780, 540)
	var list := S.vbox(8)
	for model in SkyportPlay.STOCK.get(site, []):
		var md := EmpireData.vehicle_model(model)
		var m := String(model)
		var thumb := Glass.rounded(ui.thumbs.vehicle(m, Vector2(124, 72)), Vector2(124, 72), 14)
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var info := Glass.vbox(2)
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var own := _owned(ui, m)
		var nh := Glass.hbox(8)
		nh.add_child(Glass.line(String(md.get("name", m)), "headline"))
		if own > 0:
			nh.add_child(Glass.badge("OWN %d" % own, Glass.GREEN))
		info.add_child(nh)
		info.add_child(Glass.line(_specs(md), "footnote", Glass.LABEL2))
		var price_btn := S.button(EmpireData.money(float(md.get("price", 0))), func(): vehicle_card(ui, m, site), true, 150)
		price_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		list.add_child(ui._row([thumb, info, price_btn]))
	v.add_child(ui._scroll(list, 340))
	if site == "dealer_budget":
		v.add_child(dealership_box(ui))


static func dealership_box(ui: EmpireUI) -> Control:
	var e := ui.game.empire
	var box := S.vbox(6)
	if not Ventures.owns_dealer(e):
		var h := S.hbox(10)
		h.add_child(S.label("This dealership is for sale: run it as a business.", 16, S.MUTED))
		h.add_child(S.spacer())
		var buy_dl := Glass.confirm_button("Buy the business · %s" % EmpireData.money(Ventures.DEALER_PRICE),
			"Confirm · %s" % EmpireData.money(Ventures.DEALER_PRICE), func():
			var err := Ventures.buy_dealer(e)
			ui.toast(err if err != "" else "Kestrel Motors is yours", "bad" if err != "" else "good")
			showroom(ui, "dealer_budget"), "regular")
		buy_dl.custom_minimum_size.x = 280
		h.add_child(buy_dl)
		box.add_child(h)
		return box
	var dl: Dictionary = e.flags["dealership"]
	box.add_child(S.label("YOUR DEALERSHIP · %d sold · yesterday %s" % [int(dl["sold"]), EmpireData.money(float(dl.get("last", 0.0)), true)], 14, S.AMBER, "black"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in Ventures.DEALER_MODELS:
		var mm := String(m)
		row.add_child(S.button("%s ×%d · +%s" % [String(EmpireData.vehicle_model(mm)["name"]).get_slice(" ", 0), int(dl["stock"].get(mm, 0)),
			EmpireData.money(Ventures.trade_price(mm))], func():
			var err := Ventures.dealer_buy_stock(e, mm)
			ui.toast(err if err != "" else "Bought at trade for the forecourt", "bad" if err != "" else "good")
			showroom(ui, "dealer_budget"), false, 0))
	box.add_child(row)
	var pr := S.hbox(6)
	pr.add_child(S.label("Prices:", 15, S.MUTED))
	for k in [[0.9, "Sale −10%"], [1.0, "List"], [1.1, "+10%"]]:
		var kk: float = k[0]
		pr.add_child(S.chip_button(String(k[1]), absf(float(dl["markup"]) - kk) < 0.01, func():
			dl["markup"] = kk
			showroom(ui, "dealer_budget")))
	box.add_child(pr)
	return box


static func clothes(ui: EmpireUI, site: String) -> void:
	ui.open_store(site)


# ------------------------------------------------------------- imports
static var _imp_sup := "sea"
static var _imp_biz := ""
static var _imp_lines := {}


static func imports(ui: EmpireUI) -> void:
	var e := ui.game.empire
	var v := ui._open("Skyport Cargo · imports", 860, 600)
	if e.businesses.is_empty():
		v.add_child(S.label("Imports go straight to one of your shops. Rent a shop first.", 18, S.MUTED))
		return
	if _imp_biz == "" or e.business(_imp_biz) == null:
		_imp_biz = String((e.businesses[0] as Business).id)
	var b: Business = e.business(_imp_biz)
	# Which shop, which supplier.
	var shops := HFlowContainer.new()
	shops.add_theme_constant_override("h_separation", 6)
	shops.add_theme_constant_override("v_separation", 6)
	shops.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shops.add_child(S.label("For", 15, S.MUTED))
	for bb: Business in e.businesses:
		var bid := String(bb.id)
		shops.add_child(S.chip_button(bb.name, bid == _imp_biz, func():
			_imp_biz = bid
			_imp_lines = {}
			imports(ui)))
	v.add_child(shops)
	var sups := HFlowContainer.new()
	sups.add_theme_constant_override("h_separation", 6)
	sups.add_theme_constant_override("v_separation", 6)
	sups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in Ventures.SUPPLIERS:
		var sid := String(s["id"])
		sups.add_child(S.chip_button("%s · %s" % [s["how"], s["name"]], sid == _imp_sup, func():
			_imp_sup = sid
			imports(ui)))
	v.add_child(sups)
	# Lines: what this shop sells, in cases, against the wholesale price.
	var list := S.vbox(6)
	var sup := Ventures.supplier(_imp_sup)
	for pid in b.sellable():
		var p := EmpireData.product(pid)
		var whole := e.case_price(pid)
		var imp := float(p.get("case_cost", 0.0)) * float(sup["price_k"])
		var n := int(_imp_lines.get(pid, 0))
		var id := String(pid)
		list.add_child(ui._row([ui._fixed(String(p["name"]), 220, 17, S.PAPER, "bold"),
			ui._fixed("%s a case (wholesale %s)" % [EmpireData.money(imp, true), EmpireData.money(whole, true)], 300, 15, S.GREEN if imp < whole else S.MUTED),
			S.spacer(), S.button("−", func():
				_imp_lines[id] = maxi(int(_imp_lines.get(id, 0)) - 2, 0)
				imports(ui), false, 50),
			ui._fixed("%d" % n, 40, 18, S.PAPER, "black"),
			S.button("+", func():
				_imp_lines[id] = int(_imp_lines.get(id, 0)) + 2
				imports(ui), false, 50)]))
	v.add_child(ui._scroll(list, 270))
	var lines := {}
	for k in _imp_lines:
		if int(_imp_lines[k]) > 0:
			lines[k] = int(_imp_lines[k])
	var q := Ventures.import_quote(e, lines, _imp_sup)
	v.add_child(S.label("Goods %s · freight %s · duty %s · delivery %s%s" % [EmpireData.money(float(q["goods"])), EmpireData.money(float(q["freight"])),
		EmpireData.money(float(q["duty"])), EmpireData.money(float(q["delivery"])), " (free: your warehouse)" if Ventures.owns_estate(e, "logistics") else ""], 15, S.MUTED))
	var foot := S.hbox(10)
	var due := int(float(q["arrive_t"]) / 1440.0)
	var mins := int(fposmod(float(q["arrive_t"]), 1440.0))
	foot.add_child(S.label("%d cases · arrives day %d %02d:%02d at %s" % [q["cases"], due, mins / 60, mins % 60, b.name], 16, S.PAPER, "bold"))
	foot.add_child(S.spacer())
	var go := S.button("Order · %s" % EmpireData.money(float(q["total"])), func():
		var err := Ventures.import_order(e, _imp_biz, lines, _imp_sup)
		if err != "":
			ui.toast(err, "bad")
			return
		Sfx.play("cash", -4.0)
		_imp_lines = {}
		ui.toast("Ordered – it'll be in the stockroom on arrival", "good")
		imports(ui), true, 220)
	go.disabled = int(q["cases"]) < Ventures.MIN_CASES
	foot.add_child(go)
	v.add_child(foot)
	var due_list: Array = Ventures.imports_due(e)
	if not due_list.is_empty():
		v.add_child(S.label("ON THE WAY: %d order%s" % [due_list.size(), "" if due_list.size() == 1 else "s"], 13, S.AMBER, "black"))


static func terminal(ui: EmpireUI) -> void:
	var v := ui._open("Skyport Airport", 620, 360)
	var term_desc := S.label("Departures and arrivals keep the island busy. Your own aircraft live on the stands and in the hangars; buy them at Skyport Aviation (Hangar 1).", 17, S.MUTED)
	term_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	term_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(term_desc)
	v.add_child(S.button("GPS to Skyport Aviation", func():
		ui.game.set_gps(ui.game.skyport_play.site("aviation")["door"], "Skyport Aviation", {"kind": "place", "id": "aviation"})
		ui.close_panel(true), true, 300))
	v.add_child(S.button("GPS to Skyport Cargo (imports)", func():
		ui.game.set_gps(ui.game.skyport_play.site("cargo")["door"], "Skyport Cargo", {"kind": "place", "id": "cargo"})
		ui.close_panel(true), false, 300))


# ------------------------------------------------------------ property
static func estates(ui: EmpireUI, v: VBoxContainer) -> void:
	var e := ui.game.empire
	var list := S.vbox(8)
	for d in Ventures.ESTATES:
		var id := String(d["id"])
		var owned := Ventures.owns_estate(e, id)
		var cv := ui._card()
		var c: VBoxContainer = cv[1]
		# The building's photo beside its details (tap: the gallery).
		var row := S.hbox(14)
		var pic := Button.new()
		pic.focus_mode = Control.FOCUS_NONE
		pic.custom_minimum_size = Vector2(200, 120)
		for stn in ["normal", "hover", "pressed", "focus"]:
			pic.add_theme_stylebox_override(stn, StyleBoxEmpty.new())
		var fr := PhotoBook.frame(id, "front", Vector2(200, 120), Ventures.estate_at(d))
		fr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.add_child(fr)
		var dd: Dictionary = d
		pic.pressed.connect(func(): PhotoBook.gallery(ui, id, String(dd["name"]), String(dd["desc"]),
			[["Price", EmpireData.money(float(dd["price"])), S.AMBER], ["Kind", String(dd["kind"]).capitalize()],
			["Income", ("Up to %s a day" % EmpireData.money(float(dd["rent"]) * float(dd["units"]))) if int(dd["units"]) > 0 else "Saves fees"]],
			[["Back to Property", func(): ui.open_phone("property"), true]], Ventures.estate_at(dd)))
		row.add_child(pic)
		var col := S.vbox(8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		c.add_child(row)
		c = col
		var top := S.hbox(10)
		top.add_child(S.label(String(d["name"]), 20, S.PAPER, "black"))
		top.add_child(S.chip(String(d["kind"]).capitalize(), S.BLUE))
		top.add_child(S.spacer())
		top.add_child(S.label(EmpireData.money(Ventures.valuation(e, id) if owned else float(d["price"])), 20, S.AMBER if not owned else S.GREEN, "black"))
		c.add_child(top)
		var desc_l := S.label(String(d["desc"]), 15, S.MUTED)
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(desc_l)
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 8)
		acts.add_theme_constant_override("v_separation", 6)
		acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if owned:
			var st: Dictionary = e.flags["estates"][id]
			if int(d["units"]) > 0:
				c.add_child(S.label("%d%% let · %s a day net · condition %d%%" % [int(float(st["occ"]) * 100.0), EmpireData.money(float(st.get("last", 0.0)), true),
					int(float(st["cond"]) * 100.0)], 16, S.PAPER, "bold"))
				for rl in Ventures.RENT_LEVELS:
					var k: float = rl[0]
					acts.add_child(S.chip_button(String(rl[1]), absf(float(st["rent_k"]) - k) < 0.01, func():
						Ventures.set_rent(e, id, k)
						ui.open_phone("property")))
			else:
				c.add_child(S.label("Condition %d%% · upkeep %s a day" % [int(float(st["cond"]) * 100.0), EmpireData.money(float(d["upkeep"]))], 16, S.PAPER, "bold"))
			if Ventures.renovate_block(e, id) != "":
				acts.add_child(S.chip("Top condition", S.GREEN))
			else:
				acts.add_child(S.button("Renovate · %s" % EmpireData.money(Ventures.renovate_cost(id)), func():
					var err := Ventures.renovate(e, id)
					var more := int(e.flags["estates"][id]["renovated"]) <= Ventures.MAX_RENOVATIONS
					ui.toast(err if err != "" else ("Renovated: like new, and worth more rent" if more else "Renovated: like new"), "bad" if err != "" else "good")
					ui.open_phone("property"), false, 220))
			acts.add_child(S.button("GPS", func():
				ui.game.set_gps(Ventures.estate_at(d), String(d["name"]), {"kind": "place", "id": id})
				ui.close_panel(true), false, 80))
			var sell_val := Ventures.valuation(e, id)
			var sell_btn := Glass.confirm_button("Sell · %s" % EmpireData.money(sell_val),
				"Confirm sell · %s" % EmpireData.money(sell_val), func():
				var err := Ventures.sell_estate(e, id)
				if err != "":
					ui.toast(err, "bad")
					return
				Sfx.play("cash", -4.0)
				ui.toast("Sold %s for %s" % [String(d["name"]), EmpireData.money(sell_val)], "good")
				if ui.phone and is_instance_valid(ui.phone):
					ui.phone.refresh()
				else:
					ui.open_phone("property"), "small", Glass.RED, "tinted")
			acts.add_child(sell_btn)
		else:
			c.add_child(S.label("%s" % ("Up to %s a day in rent" % EmpireData.money(float(d["rent"]) * float(d["units"])) if int(d["units"]) > 0 else "Upkeep %s a day" % EmpireData.money(float(d["upkeep"]))), 15, S.PAPER))
			acts.add_child(S.button("GPS", func():
				ui.game.set_gps(Ventures.estate_at(d), String(d["name"]), {"kind": "place", "id": id})
				ui.close_panel(true), false, 80))
			var buy_est := Glass.confirm_button("Buy · %s" % EmpireData.money(float(d["price"])),
				"Confirm · %s" % EmpireData.money(float(d["price"])), func():
				var err := Ventures.buy_estate(e, id)
				ui.toast(err if err != "" else "%s is yours" % d["name"], "bad" if err != "" else "good")
				if ui.phone and is_instance_valid(ui.phone):
					ui.phone.refresh()
				else:
					ui.open_phone("property"), "regular")
			buy_est.custom_minimum_size.x = 200
			acts.add_child(buy_est)
		c.add_child(acts)
		list.add_child(cv[0])
	v.add_child(list)
