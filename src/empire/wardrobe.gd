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
	"top_shirt": 120, "top_blazer": 480,
	"shoes_classic": 55, "shoes_blackout": 60, "shoes_gum": 70,
	"shoes_royal": 260, "shoes_volt": 320, "shoes_gold": 900,
	"head_cap": 15, "head_beanie": 14, "head_phones": 350,
	"face_shades": 220,
}
const STORES := {
	"clothes_everyday": {"name": "Threadline", "items": ["top_tee", "top_polo", "top_hoodie", "top_jumper", "top_long",
		"shoes_classic", "shoes_blackout", "shoes_gum", "head_cap", "head_beanie"]},
	"clothes_premium": {"name": "Maison Arden", "items": ["top_shirt", "top_blazer", "shoes_royal", "shoes_volt", "shoes_gold",
		"head_phones", "face_shades"]},
	# The city's independent boutiques (CityLife firms of type "clothing"):
	# a mid-range edit of both; the name is the boutique's (boutique_name).
	"clothes_boutique": {"name": "Boutique", "items": ["top_tee", "top_polo", "top_jumper", "top_long", "top_shirt",
		"shoes_classic", "shoes_gum", "shoes_royal", "head_cap", "head_beanie", "face_shades"]},
}
## The boutique you're in (its name on receipts and the store screen).
static var boutique_name := "Boutique"
## Style options everyone can wear, including in stores.
const FREE := ["head_bare", "face_none", "top_bomber"]


static func owned(flags: Dictionary) -> Array:
	if not flags.has("wardrobe"):
		# (Saves from before stores: you own what you're wearing.)
		var l := HeroLook.current(flags)
		flags["wardrobe"] = [l["top"], l["shoes"], l["head"], l["eyewear"]]
	return flags["wardrobe"]


static func owns(flags: Dictionary, item: String) -> bool:
	return item in FREE or not PRICES.has(item) or item in owned(flags)


static func price(item: String) -> int:
	return int(PRICES.get(item, 0))


## What the look costs in items you don't own yet.
static func unpaid(flags: Dictionary, look: Dictionary) -> Array:
	var out: Array = []
	for k in ["top", "shoes", "head", "eyewear"]:
		var it := String(look.get(k, ""))
		if it != "" and not owns(flags, it):
			out.append(it)
	return out


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
	var keep := {"trousers": look.get("trousers", "auto")}
	for k in ["top", "top_col", "pants_col", "shoes", "head", "eyewear"]:
		keep[k] = look.get(k, "")
	outs.push_front(keep)
	while outs.size() > 6:
		outs.pop_back()
	flags["outfits"] = outs
