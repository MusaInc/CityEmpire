class_name HeroLook
extends RefCounted
## WorldState's two fixed player identities. Keep the saved body IDs
## and wardrobe keys so older saves can be read without a version bump.
const CHARACTERS := [["a", "Ade · Build A"], ["b", "Jules · Build B"]]
const IDENTITIES := {"a": "hero_ade", "b": "hero_jules"}
const TOPS := [["top_tee", "T-Shirt"], ["top_polo", "Polo"], ["top_shirt", "Shirt"], ["top_jumper", "Jumper"],
	["top_hoodie", "Hoodie"], ["top_blazer", "Blazer & Tie"], ["top_long", "Base Layer"], ["top_bomber", "Bomber Jacket"]]
const LOWER_CUTS := [["auto", "Match top"], ["cargo", "Cargo"], ["chinos", "Chinos"],
	["jeans", "Jeans"], ["joggers", "Joggers"], ["shorts", "Shorts"]]
const FASHION_TOPS := [["top_fashion_crop", "Crop Top"], ["top_fashion_tank", "Rib Tank"],
	["top_fashion_vest", "Tailored Vest"], ["top_fashion_camisole", "Camisole"], ["top_fashion_blouse", "Blouse"],
	["top_fashion_bodysuit", "Bodysuit"], ["top_fashion_cardigan", "Cardigan"], ["top_fashion_jacket", "Denim Jacket"],
	["top_fashion_squareneck", "Square-Neck Top"], ["top_fashion_moto", "Leather Zip Jacket"],
	["top_fashion_racer", "Cropped Leather Jacket"], ["top_fashion_pullover", "Fleece Pullover"]]
const DRESSES := [["top_fashion_fitteddress", "Fitted Dress"], ["top_fashion_loosedress", "Loose Dress"],
	["top_fashion_onedress", "One-Shoulder Dress"]]
const FASHION_BOTTOMS := [["miniskirt", "Mini Skirt"], ["midiskirt", "Midi Skirt"], ["maxiskirt", "Maxi Skirt"],
	["leggings", "Leggings"], ["fitjeans", "Fitted Jeans"], ["tailoredshorts", "Tailored Shorts"],
	["widejeans", "Wide-Leg Jeans"], ["bikershorts", "Cycling Shorts"]]
const FOOTWEAR := [["trainers", "Classic Trainers"], ["streettrainers", "Street Trainers"],
	["heels", "Block Heels"], ["boots", "Ankle Boots"], ["sandals", "Strap Sandals"]]
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

static func tops_for(body: String) -> Array:
	return separates_for(body) + DRESSES if body == "b" else TOPS


static func separates_for(body: String) -> Array:
	return TOPS.filter(func(item): return item[0] != "top_blazer") + FASHION_TOPS if body == "b" else TOPS


static func top_for(body: String, id: String) -> String:
	if body == "b" and id == "top_blazer":
		return "top_shirt"
	if body != "b" and id.begins_with("top_fashion_"):
		return DEFAULT["top"]
	return id


static func bottoms_for(body: String) -> Array:
	return LOWER_CUTS + FASHION_BOTTOMS if body == "b" else LOWER_CUTS


static func is_dress(id: String) -> bool:
	return DRESSES.any(func(dress): return dress[0] == id)


const DEFAULT := {"body": "a", "top": "top_polo", "top_col": "#3f6db3",
	"trousers": "auto", "pants_col": "#3b3f46", "shoes": "shoes_classic", "footwear": "trainers", "head": "head_bare", "eyewear": "face_none"}


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
	if not bottoms_for(body).any(func(entry): return entry[0] == d["trousers"]):
		d["trousers"] = "auto"
	d["top"] = top_for(body, String(d["top"]))
	if body != "b" or not FOOTWEAR.any(func(entry): return entry[0] == d["footwear"]):
		d["footwear"] = "trainers"
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
			starting.merge(FASHION_LOOKS[0][1])
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
		lower = "chinos" if top in ["top_shirt", "top_blazer"] else "cargo"
		if top == "top_fashion_bodysuit":
			lower = "leggings"
	look["trousers"] = "dress" if is_dress(top) else lower
	look["footwear"] = l["footwear"]
	return look


static func label(list: Array, id: String) -> String:
	for x in list:
		if x[0] == id:
			return x[1]
	return id
