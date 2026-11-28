class_name HeroLook
extends RefCounted
## WorldState's two fixed player identities. Keep the saved body IDs
## and wardrobe keys so older saves can be read without a version bump.
const CHARACTERS := [["a", "Ade"], ["b", "Jules"]]
const IDENTITIES := {"a": "hero_ade", "b": "hero_jules"}
const TOPS := [["top_tee", "T-Shirt"], ["top_polo", "Polo"], ["top_shirt", "Shirt"], ["top_linen", "Linen Camp Shirt"],
	["top_jumper", "Jumper"], ["top_qzip", "Quarter-Zip Knit"], ["top_hoodie", "Hoodie"], ["top_long", "Base Layer"],
	["top_bomber", "Bomber Jacket"], ["top_leather", "Leather Moto"], ["top_oversize", "Oversized Tee"],
	["top_track", "Track Jacket"], ["top_blazer", "Suit Jacket"], ["top_coat", "Overcoat"]]
const LOWER_CUTS := [["auto", "Match top"], ["cargo", "Cargo"], ["chinos", "Chinos"], ["tailored", "Tailored Trousers"],
	["jeans", "Jeans"], ["joggers", "Joggers"], ["track", "Track Pants"], ["shorts", "Shorts"]]
const FASHION_TOPS := [["top_fashion_ribcrop", "Cropped Rib Cardigan"], ["top_fashion_zipcrop", "Cropped Zip Hoodie"],
	["top_fashion_tailoredknit", "Tailored V-Neck"], ["top_fashion_crossbra", "Crossback Sports Top"],
	["top_fashion_blouse", "Linen Blouse"], ["top_fashion_tank", "Fitted Rib Tank"],
	["top_fashion_squareneck", "Square-Neck Top"], ["top_fashion_vest", "Tailored Vest"],
	["top_fashion_moto", "Leather Moto Jacket"], ["top_fashion_racer", "Cropped Leather Jacket"],
	["top_fashion_jacket", "Denim Jacket"], ["top_fashion_pullover", "Fleece Pullover"],
	["top_oversize", "Oversized Tee"], ["top_track", "Track Jacket"], ["top_coat", "Overcoat"]]
const DRESSES := [["top_fashion_cowldress", "Satin Slit Gown"], ["top_fashion_fitteddress", "Fitted Cocktail Dress"],
	["top_fashion_loosedress", "Draped Midi Dress"], ["top_fashion_onedress", "One-Shoulder Dress"]]
const FASHION_BOTTOMS := [["relaxeddenim", "Relaxed Denim"], ["fitjeans", "High-Waisted Jeans"],
	["widejeans", "Wide-Leg Jeans"], ["chinos", "Tailored Trousers"], ["utilitymini", "Utility Mini"],
	["beltedmini", "Belted Mini"], ["midiskirt", "Midi Skirt"], ["tailoredshorts", "Tailored Shorts"],
	["leggings", "Active Leggings"], ["sprintshorts", "Training Shorts"], ["track", "Track Pants"]]
const FOOTWEAR := [["streettrainers", "Low Trainers"], ["highstreet", "High Tops"],
	["pumps", "Pumps"], ["boots", "Ankle Boots"], ["sandals", "Strappy Sandals"], ["eveningstraps", "Evening Heels"]]
const ACCESSORIES := [["none", "None"], ["day", "Gold Pendant"], ["street", "Silver Chain"],
	["office", "Brass Pendant"], ["evening", "Evening Pendant"]]

const FASHION_LOOKS := [
	["Red Leather", {"top": "top_fashion_racer", "trousers": "widejeans", "footwear": "streettrainers",
		"top_col": "#803537", "pants_col": "#282d37", "shoes": "shoes_classic"}],
	["Grey Lounge", {"top": "top_fashion_pullover", "trousers": "bikershorts", "footwear": "streettrainers",
		"top_col": "#737373", "pants_col": "#212227", "shoes": "shoes_classic"}],
	["City Leather", {"top": "top_fashion_moto",
		"trousers": "midiskirt", "footwear": "streettrainers", "top_col": "#733d2b",
		"pants_col": "#242329", "shoes": "shoes_royal"}],
	["Casual", {"top": "top_fashion_tank", "trousers": "fitjeans", "footwear": "streettrainers",
		"top_col": "#d9cbb9", "pants_col": "#365172", "shoes": "shoes_classic"}],
	["Streetwear", {"top": "top_fashion_jacket", "trousers": "leggings", "footwear": "streettrainers",
		"top_col": "#465c83", "pants_col": "#26272d", "shoes": "shoes_classic"}],
	["Smart", {"top": "top_fashion_blouse", "trousers": "midiskirt", "footwear": "boots",
		"top_col": "#ece0cb", "pants_col": "#405047", "shoes": "shoes_blackout"}],
	["Formal", {"top": "top_fashion_fitteddress", "trousers": "auto", "footwear": "heels",
		"top_col": "#283344", "shoes": "shoes_blackout"}],
	["Summer", {"top": "top_fashion_loosedress", "trousers": "auto", "footwear": "sandals",
		"top_col": "#c78372", "shoes": "shoes_gum"}],
	["Evening", {"top": "top_fashion_camisole", "trousers": "maxiskirt", "footwear": "heels",
		"top_col": "#905568", "pants_col": "#3a2938", "shoes": "shoes_gold"}],
	["Cocktail", {"top": "top_fashion_onedress", "trousers": "auto", "footwear": "heels",
		"top_col": "#742d49", "pants_col": "#3a2938", "shoes": "shoes_blackout"}],
]
const HATS := [["head_bare", "None"], ["head_cap", "Cap"], ["head_beanie", "Beanie"], ["head_phones", "Headphones"]]
const EYEWEAR := [["face_none", "None"], ["face_shades", "Shades"]]
const SHOES := [["shoes_classic", "White"], ["shoes_blackout", "Black"], ["shoes_gum", "Gum Sole"], ["shoes_royal", "Royal"],
	["shoes_volt", "Volt"], ["shoes_gold", "Gold"]]

## Clothes: the colours people actually wear.
const CLOTH := ["#f2f1ec", "#c9c4b8", "#1a1c20", "#3b3f46", "#1f2d4a", "#3f6db3", "#8fb3d9", "#5d1f2a",
	"#a8322d", "#d9822b", "#e3c74a", "#2f4a33", "#6f8a52", "#b59a74", "#6b4a3a", "#c96f92"]
const TROUSERS := ["#1a1c20", "#3b3f46", "#25304a", "#2f4a73", "#8a7a5a", "#c9bc9c", "#3d4530", "#5a3d2c", "#e8e6df"]

static var _collection: Dictionary


static func collection(body: String) -> Array:
	if _collection.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/hero_outfits.json"))
		if parsed is Dictionary:
			_collection = parsed
	return _collection.get(body, [])


static func tops_for(body: String) -> Array:
	return separates_for(body) + DRESSES if body == "b" else TOPS


static func separates_for(body: String) -> Array:
	return FASHION_TOPS if body == "b" else TOPS


static func top_for(body: String, id: String) -> String:
	if body == "b":
		if tops_for(body).any(func(piece): return piece[0] == id):
			return id
		if "dress" in id:
			return DRESSES[0][0]
		if id in ["top_fashion_racer", "top_fashion_jacket", "top_hoodie", "top_bomber"]:
			return "top_fashion_zipcrop"
		if id in ["top_fashion_moto", "top_fashion_blouse", "top_fashion_vest", "top_shirt", "top_blazer"]:
			return "top_fashion_tailoredknit"
		if id in ["top_fashion_pullover", "top_fashion_bodysuit", "top_fashion_crop"]:
			return "top_fashion_crossbra"
		return "top_fashion_ribcrop"
	if body != "b" and id.begins_with("top_fashion_"):
		return DEFAULT["top"]
	return id


static func bottoms_for(body: String) -> Array:
	return FASHION_BOTTOMS if body == "b" else LOWER_CUTS


static func footwear_for(body: String) -> Array:
	return FOOTWEAR if body == "b" else [["trainers", "Classic Trainers"], ["derbies", "Leather Derbies"]]


static func is_dress(id: String) -> bool:
	return DRESSES.any(func(dress): return dress[0] == id)


const DEFAULT := {"body": "a", "top": "top_polo", "top_col": "#3f6db3",
	"trousers": "auto", "pants_col": "#3b3f46", "shoes": "shoes_classic", "footwear": "trainers", "head": "head_bare", "eyewear": "face_none", "accessory": "none"}


static func current(flags: Dictionary) -> Dictionary:
	var d: Dictionary = DEFAULT.duplicate()
	var saved = flags.get("look", {})
	if saved is Dictionary:
		for k in saved:
			if d.has(k):
				d[k] = String(saved[k])
		if not saved.has("body"):
			d["body"] = Shop.item(String(saved.get("face", ""))).get("body", "a")
	if not IDENTITIES.has(d["body"]):
		d["body"] = "a"
	var body := String(d["body"])
	d["top"] = top_for(body, String(d["top"]))
	if body == "b":
		# Migrate older looks by category. The hero and the original save slot
		# stay the same, including saved swatches and the shoe colour.
		var defaults := {
			"top_fashion_ribcrop": ["relaxeddenim", "streettrainers"],
			"top_fashion_zipcrop": ["utilitymini", "highstreet"],
			"top_fashion_tailoredknit": ["beltedmini", "pumps"],
			"top_fashion_crossbra": ["sprintshorts", "streettrainers"],
			"top_fashion_blouse": ["chinos", "pumps"],
			"top_fashion_tank": ["fitjeans", "streettrainers"],
			"top_fashion_squareneck": ["midiskirt", "pumps"],
			"top_fashion_vest": ["chinos", "pumps"],
			"top_fashion_moto": ["fitjeans", "boots"],
			"top_fashion_racer": ["widejeans", "highstreet"],
			"top_fashion_jacket": ["leggings", "streettrainers"],
			"top_fashion_pullover": ["leggings", "streettrainers"],
			"top_fashion_cowldress": ["relaxeddenim", "eveningstraps"],
			"top_fashion_fitteddress": ["relaxeddenim", "pumps"],
			"top_fashion_loosedress": ["relaxeddenim", "sandals"],
			"top_fashion_onedress": ["relaxeddenim", "eveningstraps"],
			"top_oversize": ["relaxeddenim", "streettrainers"],
			"top_track": ["track", "streettrainers"],
			"top_coat": ["relaxeddenim", "pumps"],
		}
		d["head"] = "head_bare"
		var pairing: Array = defaults.get(d["top"], ["relaxeddenim", "streettrainers"])
		if not bottoms_for(body).any(func(piece): return piece[0] == d["trousers"]):
			d["trousers"] = pairing[0]
		if not footwear_for(body).any(func(piece): return piece[0] == d["footwear"]):
			d["footwear"] = pairing[1]
		if not ACCESSORIES.any(func(piece): return piece[0] == d["accessory"]):
			d["accessory"] = "none"
	else:
		if not bottoms_for(body).any(func(piece): return piece[0] == d["trousers"]):
			d["trousers"] = "auto"
		if not footwear_for(body).any(func(piece): return piece[0] == d["footwear"]):
			d["footwear"] = "trainers"
		d["accessory"] = "none"
	return d


## Save the current outfit separately when choosing the other character.
static func change(flags: Dictionary, changes: Dictionary) -> void:
	var look := current(flags)
	var body := String(changes.get("body", look["body"]))
	if not IDENTITIES.has(body):
		return
	if body != look["body"]:
		var outfits: Dictionary = flags.get("character_outfits", {})
		outfits[look["body"]] = look
		flags["character_outfits"] = outfits
		var starting := {"body": body}
		if body == "b":
			var choices := collection(body)
			if not choices.is_empty():
				starting.merge(choices[0]["look"])
		look = outfits.get(body, current({"look": starting})).duplicate()
	look.merge(changes, true)
	flags["look"] = current({"look": look})


## Convert a saved wardrobe selection into the fixed hero's rig look.
static func build(selection: Dictionary) -> Dictionary:
	var l := current({"look": selection})
	var body: String = l["body"]
	var top: String = l["top"]
	var look := Shop.look({"face": l["eyewear"], "head": l["head"], "top": top,
		"hero": IDENTITIES[body], "hair": "hair_natural", "pants": "pants_navy",
		"shoes": l["shoes"], "suit": "sky"})
	look["body"] = body
	look["top"] = top.trim_prefix("top_")
	look["accessory"] = l["accessory"]
	look["suit"] = Color(String(l.get("top_col", DEFAULT["top_col"])))
	look["pants"] = Color(String(l.get("pants_col", DEFAULT["pants_col"])))
	# Bare hands (the hero model always wears gloves): the glove drawn in the
	# skin colour as the skin texture renders it (warmer and a shade deeper
	# than the nominal tone, or pale hands read as white gloves).
	var sk: Color = look["skin"]
	look["glove"] = Color(sk.r * 0.8, sk.g * 0.7, sk.b * 0.66)
	look["bare_hands"] = true
	var lower: String = l["trousers"]
	if lower == "auto":
		lower = "tailored" if top == "top_blazer" else ("chinos" if top in ["top_shirt", "top_coat", "top_qzip", "top_linen"] else ("track" if top == "top_track" else ("jeans" if top == "top_leather" else "cargo")))
		if top == "top_fashion_bodysuit":
			lower = "leggings"
	look["trousers"] = "dress" if is_dress(top) else lower
	look["footwear"] = l["footwear"]
	if body == "b" and l["footwear"] == "pumps" and l["shoes"] == "shoes_gum":
		look["shoe"] = Color("#a97550")
	return look


static func label(list: Array, id: String) -> String:
	for x in list:
		if x[0] == id:
			return x[1]
	return id
