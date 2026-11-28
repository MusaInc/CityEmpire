class_name CareerPages
extends RefCounted
## Phone pages for Careers (2026-11-26): Jobs (overview), Operations and
## Reports (businesses).

const G = preload("res://src/empire/ui/glass.gd")


static func _card(v: VBoxContainer) -> VBoxContainer:
	var c := G.card(18, 10, G.CARD)
	v.add_child(c[0])
	return c[1]


# ------------------------------------------------------------ Jobs
static func jobs(ph: Phone, body: VBoxContainer) -> void:
	var g := ph.game
	var e := g.empire
	var v := PhonePages.scroller(body, 18)
	var st := Careers.state(e)
	var head := _card(v)
	head.add_child(G.text("Work", "title2"))
	head.add_child(G.para("Earn your way up: courier runs and shifts pay straight into your own account. %s earned so far · %d runs." % [
		EmpireData.money(float(st["earned"])), int(st["runs"])], "footnote"))
	# Courier
	var cc := _card(v)
	cc.add_child(G.text("Courier runs", "title3"))
	var r := g.career.run()
	if r.is_empty():
		cc.add_child(G.para("A parcel to a door 0.5–1.5 km away. Paid on arrival; half as much again if you're quick. On foot or in any car.", "footnote"))
		cc.add_child(G.button("Take a delivery", func():
			var err := g.career.start_run()
			ph.ui.toast(err if err != "" else "Parcel collected – follow the GPS", "bad" if err != "" else "good")
			ph.refresh(), "filled", "regular", null, "truck"))
	else:
		cc.add_child(G.para("Parcel for %s · %s on delivery (+50%% if within %d min)" % [String(r["to_name"]), EmpireData.money(float(r["pay"])), int(float(r["minutes"]))], "body"))
		cc.add_child(G.button("Abandon the run", func():
			g.career.cancel_run()
			ph.refresh(), "gray", "regular"))
	# Shifts
	var sc := _card(v)
	sc.add_child(G.text("Shift work", "title3"))
	var block := Careers.shift_block(e)
	sc.add_child(G.para("Four hours at a business near you, paid by the hour (better in smarter districts). Up to two shifts a day; your own shops keep trading." + ("" if block == "" else "  " + block), "footnote"))
	for it in g.career.employers(4):
		var u: Dictionary = it[0]
		var m: float = it[1]
		var row := G.hbox(10)
		row.add_child(G.para("%s · %s · £%.2f/h" % [String(u.get("name", "Business")), ph.ui._dist_text(m), Careers.shift_rate(g.career.affluence(u))], "body"))
		var here := m <= CareerPlay.SHIFT_REACH
		var b := G.button("Work 4 h" if here else "Go", func():
			if here:
				var err := g.career.work_shift(u)
				if err != "":
					ph.ui.toast(err, "warn")
			else:
				g.gps.set_destination(Premises.door_point(u), String(u.get("name", "")))
				ph.ui.close_panel(true)
			ph.refresh(), "filled" if here else "gray", "small", null, "" if here else "gps")
		b.disabled = here and block != ""
		row.add_child(b)
		sc.add_child(row)
	# Status and perks
	var pc := _card(v)
	pc.add_child(G.text("Status: %s" % Careers.tier(e), "title3"))
	pc.add_child(G.para("Net worth %s. Established (£250k): every delivery free. Tycoon (£1m): a driver takes you anywhere. Magnate (£5m): auto-restock is free and your managers buy at the bulk price." % EmpireData.money(Careers.net_worth(e)), "footnote"))
	if Careers.has_perk(e, "driver"):
		for b2: Business in e.businesses:
			var u2: Dictionary = g.unit_by_id.get(String(b2.premises.get("id", "")), {})
			if u2.is_empty():
				continue
			pc.add_child(G.button("Driver to %s" % b2.name, func():
				var err := g.career.driven_to(Premises.door_point(u2) + Premises.outward(u2) * 2.5, 0.0)
				if err != "":
					ph.ui.toast(err, "warn")
				else:
					ph.ui.close_panel(true), "gray", "small", null, "vehicles"))


# ------------------------------------------------------------ Operations
static func operations(ph: Phone, body: VBoxContainer) -> void:
	var g := ph.game
	var e := g.empire
	var v := PhonePages.scroller(body, 18)
	var head := _card(v)
	head.add_child(G.text("Restocking", "title2"))
	head.add_child(G.para("Each shop restocks itself overnight if it has a manager or the supplier's auto-restock (%s a delivery), up to its daily purchasing budget. Orders of 20, 60 and 150 cases get 5, 10 and 15%% off." % EmpireData.money(Careers.auto_fee(e)), "footnote"))
	if e.businesses.is_empty():
		head.add_child(G.para("You don't run a shop yet.", "body"))
		return
	var tg: Dictionary = Careers.state(e)["targets"]
	for b: Business in e.businesses:
		var c := _card(v)
		var p := Careers.purchasing(e, b.id)
		c.add_child(G.text(b.name, "title3"))
		var who := "Branch manager orders" if b.has_role("manager") else ("Supplier auto-restock" if bool(p["auto"]) else "You order the stock")
		c.add_child(G.para("%s · budget %s/day" % [who, EmpireData.money(float(p["budget"]))], "footnote"))
		var t: Dictionary = tg.get(b.id, {})
		if not t.is_empty():
			c.add_child(G.para("Today's target: %s · bonus %s" % [String(t["label"]), EmpireData.money(float(t["bonus"]))], "body"))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not b.has_role("manager"):
			row.add_child(G.button("Auto-restock: %s" % ("on" if bool(p["auto"]) else "off"), func():
				p["auto"] = not bool(p["auto"])
				ph.refresh(), "filled" if bool(p["auto"]) else "gray", "small"))
		row.add_child(G.button("Budget −", func():
			p["budget"] = maxf(100.0, float(p["budget"]) - 100.0)
			ph.refresh(), "gray", "small"))
		row.add_child(G.button("Budget +", func():
			p["budget"] = minf(20000.0, float(p["budget"]) + 100.0)
			ph.refresh(), "gray", "small"))
		c.add_child(row)
		if not b.has_role("manager"):
			c.add_child(G.para("Hire a manager at the shop's staff screen to have it run itself – re-orders, rotas and the till.", "footnote"))
	# Financing
	var fc := _card(v)
	var st := Careers.state(e)
	var lim := Careers.credit_limit(e)
	fc.add_child(G.text("Credit line", "title3"))
	fc.add_child(G.para("Borrow against your businesses at 0.12%% a day: %s drawn of %s." % [EmpireData.money(float(st["credit"])), EmpireData.money(lim)], "footnote"))
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 8)
	fr.add_theme_constant_override("v_separation", 6)
	fr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for amt: float in [5000.0, 25000.0, 100000.0]:
		var bd := G.button("Draw %s" % EmpireData.money(amt), func():
			var err := Careers.draw_credit(e, amt)
			ph.ui.toast(err if err != "" else "Credit drawn", "bad" if err != "" else "good")
			ph.refresh(), "gray", "small")
		bd.disabled = float(st["credit"]) + amt > lim
		fr.add_child(bd)
	var br := G.button("Repay all", func():
		var err := Careers.repay_credit(e, float(st["credit"]))
		ph.ui.toast(err if err != "" else "Credit repaid", "bad" if err != "" else "good")
		ph.refresh(), "gray", "small")
	br.disabled = float(st["credit"]) <= 0.0
	fr.add_child(br)
	fc.add_child(fr)


# ------------------------------------------------------------ Reports
static func reports(ph: Phone, body: VBoxContainer) -> void:
	var e := ph.game.empire
	var v := PhonePages.scroller(body, 16)
	var r := Careers.report(e, 7)
	var tot: Dictionary = r["total"]
	var head := _card(v)
	head.add_child(G.text("Last 7 days", "title2"))
	var fig := HFlowContainer.new()
	fig.add_theme_constant_override("h_separation", 16)
	fig.add_theme_constant_override("v_separation", 8)
	fig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fig.add_child(G.figure("Revenue", EmpireData.money(float(tot["revenue"]))))
	fig.add_child(G.figure("Profit", EmpireData.money(float(tot["profit"])), G.GREEN if float(tot["profit"]) >= 0.0 else G.RED))
	fig.add_child(G.figure("Customers", str(int(tot["customers"]))))
	head.add_child(fig)
	head.add_child(G.para("%d shops · %d office companies · club worth %s" % [(r["rows"] as Array).size(), int(r["offices"]), EmpireData.money(float(r["club"]))], "footnote"))
	for row: Dictionary in r["rows"]:
		var c := _card(v)
		c.add_child(G.text(String(row["name"]), "title3"))
		c.add_child(G.para("%s revenue · %s profit · %d customers · %d stock-outs · %d walked out · reputation %d" % [
			EmpireData.money(float(row["revenue"])), EmpireData.money(float(row["profit"])), int(row["customers"]), int(row["stockouts"]),
			int(row["walked_out"]), int(float(row["reputation"]))], "footnote"))
		if String(row["advice"]) != "":
			c.add_child(G.para(String(row["advice"]), "callout", G.ORANGE))
