class_name Wardrobe
extends RefCounted
## Clothes you own (Empire.flags.wardrobe) and the two clothing stores on
## Skyport Island. The Style screen is the store when you're in one (try
## anything they stock, pay for what you keep) and your wardrobe otherwise
## (only what you own; colours are free). The first-run character maker
## gives you your starting outfit free. Saved outfits: flags.outfits.

## Item -> price. Faces, hair and colours are free (they're you).
const PRICES := {
	"top_tee": 18, "top_polo": 28, "top_hoodie": 45, "top_jumper": 40, "top_long": 24,
	"top_shirt": 120, "top_linen": 95, "top_qzip": 110, "top_leather": 340, "top_blazer": 480,
	"top_oversize": 35, "top_track": 85, "top_coat": 640, "track": 60, "tailored": 140,
	"shoes_classic": 55, "shoes_blackout": 60, "shoes_gum": 70,
	"shoes_royal": 260, "shoes_volt": 320, "shoes_gold": 900,
	"head_cap": 15, "head_beanie": 14, "head_phones": 350,
	"face_shades": 220,
	"top_fashion_zipcrop": 95, "top_fashion_tailoredknit": 145, "top_fashion_crossbra": 65,
	"top_fashion_blouse": 125, "top_fashion_tank": 45, "top_fashion_squareneck": 90, "top_fashion_vest": 135,
	"top_fashion_moto": 320, "top_fashion_racer": 290, "top_fashion_jacket": 155, "top_fashion_pullover": 75,
	"top_fashion_cowldress": 680, "top_fashion_fitteddress": 420, "top_fashion_loosedress": 240, "top_fashion_onedress": 520,
	"utilitymini": 86, "beltedmini": 130, "midiskirt": 145, "tailoredshorts": 85, "fitjeans": 115, "widejeans": 120,
	"leggings": 70, "sprintshorts": 55, "chinos": 120,
	"highstreet": 120, "pumps": 158, "boots": 195, "sandals": 115, "eveningstraps": 205,
	"street": 89, "office": 140, "evening": 230,
}
const JULES_STOCK := {
	"clothes_everyday": ["top_fashion_zipcrop", "top_fashion_tank", "top_fashion_jacket", "top_fashion_pullover",
		"utilitymini", "fitjeans", "widejeans", "leggings", "tailoredshorts", "highstreet", "sandals", "street",
		"top_oversize", "top_track", "track", "top_fashion_crossbra", "sprintshorts"],
	"clothes_premium": ["top_fashion_tailoredknit", "top_fashion_blouse", "top_fashion_squareneck", "top_fashion_vest",
		"top_fashion_moto", "top_fashion_racer", "beltedmini", "midiskirt", "chinos", "pumps", "boots", "office",
		"top_coat", "top_fashion_cowldress", "top_fashion_fitteddress", "top_fashion_loosedress", "top_fashion_onedress",
		"eveningstraps", "evening"],
	"clothes_boutique": ["top_fashion_zipcrop", "top_fashion_blouse", "top_fashion_tank", "top_fashion_squareneck",
		"top_fashion_jacket", "top_fashion_loosedress", "utilitymini", "fitjeans", "midiskirt", "highstreet",
		"top_fashion_tailoredknit", "beltedmini", "pumps", "boots", "office"],
}
const STORES := {
	"clothes_everyday": {"name": "Threadline", "items": ["top_tee", "top_polo", "top_hoodie", "top_jumper", "top_long",
		"top_oversize", "top_track", "track", "top_linen",
		"shoes_classic", "shoes_blackout", "shoes_gum", "head_cap", "head_beanie"]},
	"clothes_premium": {"name": "Maison Arden", "items": ["top_shirt", "top_qzip", "top_leather", "top_blazer", "top_coat",
		"tailored", "shoes_royal", "shoes_volt", "shoes_gold", "head_phones", "face_shades"]},
	# The city's independent boutiques (CityLife firms of type "clothing"):
	# a mid-range edit of both; the name is the boutique's (boutique_name).
	"clothes_boutique": {"name": "Boutique", "items": ["top_tee", "top_polo", "top_jumper", "top_long", "top_shirt",
		"top_linen", "top_qzip", "top_leather", "top_oversize", "top_coat", "tailored",
		"shoes_classic", "shoes_gum", "shoes_royal", "head_cap", "head_beanie", "face_shades"]},
}
## The boutique you're in (its name on receipts and the store screen).
static var boutique_name := "Boutique"
## All wearable clothing/accessory slots checked on store checkout or exit.
const SLOTS := ["top", "trousers", "footwear", "shoes", "head", "eyewear", "accessory"]
## Style options everyone can wear, including in stores.
const FREE := ["head_bare", "face_none", "top_bomber", "top_fashion_ribcrop", "relaxeddenim", "streettrainers", "day", "none"]


static func stocks(store: String, id: String, body: String) -> bool:
	return id in FREE or id in STORES[store]["items"] or (body == "b" and id in JULES_STOCK.get(store, []))


static func owned(flags: Dictionary) -> Array:
	if not flags.has("wardrobe"):
		# (Saves from before stores: you own what you're wearing.)
		var l := HeroLook.current(flags)
		flags["wardrobe"] = [l["top"], l["shoes"], l["head"], l["eyewear"]]
	return flags["wardrobe"]


static func owns(flags: Dictionary, item: String, body := "a") -> bool:
	if body == "b" and item == "top_shirt" and "top_blazer" in owned(flags):
		return true
	return item in FREE or not PRICES.has(item) or item in owned(flags)


static func price(item: String) -> int:
	return int(PRICES.get(item, 0))


## What the look costs in items you don't own yet.
static func unpaid(flags: Dictionary, look: Dictionary) -> Array:
	var out: Array = []
	for k in SLOTS:
		var it := String(look.get(k, ""))
		if it != "" and not owns(flags, it, String(look.get("body", "a"))):
			out.append(it)
	return out


## Reverts every unpaid slot in `look` back to `saved_look` (or HeroLook.DEFAULT)
## and saves the clean look back onto `empire.flags["look"]`.
static func revert_unpaid(empire: Empire, look: Dictionary, saved_look: Dictionary) -> Dictionary:
	var back := look.duplicate(true)
	var body := String(back.get("body", saved_look.get("body", "a")))
	for k in SLOTS:
		var it := String(back.get(k, ""))
		if it != "" and not owns(empire.flags, it, body):
			if saved_look.has(k):
				back[k] = saved_look[k]
			elif HeroLook.DEFAULT.has(k):
				back[k] = HeroLook.DEFAULT[k]
			else:
				back.erase(k)
	empire.flags["look"] = back
	return back


static func buy(e: Empire, items: Array, store: String) -> String:
	var total := 0
	for it in items:
		total += price(String(it))
	if total <= 0:
		return ""
	if not e.pay(float(total), "clothes", "%s: %d item%s" % [boutique_name if store == "clothes_boutique" else String(STORES.get(store, {}).get("name", "Clothes")), items.size(), "" if items.size() == 1 else "s"]):
		return "Not enough money (%s)" % EmpireData.money(float(total))
	var o := owned(e.flags)
	for it in items:
		if not it in o:
			o.append(it)
	return ""


static func save_outfit(flags: Dictionary, look: Dictionary) -> void:
	var outs: Array = flags.get("outfits", [])
	var keep := {"body": look.get("body", "a"), "trousers": look.get("trousers", "auto"),
		"footwear": look.get("footwear", "trainers")}
	for k in ["top", "top_col", "pants_col", "shoes", "head", "eyewear", "accessory"]:
		keep[k] = look.get(k, "")
	outs.push_front(keep)
	while outs.size() > 6:
		outs.pop_back()
	flags["outfits"] = outs
