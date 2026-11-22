class_name HeroLook
extends RefCounted
## Your character in City Empire: who you are (face, skin, hair) and what you
## wear. Kept in Empire.flags["look"] as plain strings (ids and hex colours)
## so it saves with the empire. Everything is free: it's your character, not
## a shop.

## Body types (character.glb / character_b.glb): the same clothes, hair and
## kit on either; each has its own faces. Neutral names, chosen freely.
const BODIES := [["a", "Build A"], ["b", "Build B"]]
const BODY_B_ENABLED := true
const FACES := [["hero_ade", "Ade"], ["hero_kai", "Kai"], ["hero_malik", "Malik"], ["hero_ren", "Ren"], ["hero_theo", "Theo"]]
const FACES_B := [["hero_rio", "Rio"], ["hero_sam", "Sam"], ["hero_noa", "Noa"], ["hero_remy", "Remy"], ["hero_jules", "Jules"]]


static func faces_for(body: String) -> Array:
	return FACES_B if body == "b" else FACES
const HAIRS := [["hair_natural", "Natural"], ["hair_buzz", "Buzz Cut"], ["hair_crop", "Crop"], ["hair_fade", "High Fade"],
	["hair_curls", "Curls"], ["hair_pixie", "Pixie"], ["hair_ponytail", "Ponytail"], ["hair_bun", "Bun"]]
const TOPS := [["top_tee", "T-Shirt"], ["top_polo", "Polo"], ["top_shirt", "Shirt"], ["top_jumper", "Jumper"],
	["top_hoodie", "Hoodie"], ["top_blazer", "Blazer & Tie"], ["top_long", "Base Layer"], ["top_bomber", "Bomber Jacket"]]
const LOWER_CUTS := [["auto", "Match top"], ["cargo", "Cargo"], ["chinos", "Chinos"],
	["jeans", "Jeans"], ["joggers", "Joggers"], ["shorts", "Shorts"]]
const FASHION_TOPS := [["top_fashion_crop", "Crop Top"], ["top_fashion_tank", "Rib Tank"],
	["top_fashion_vest", "Tailored Vest"], ["top_fashion_camisole", "Camisole"], ["top_fashion_blouse", "Blouse"],
	["top_fashion_bodysuit", "Bodysuit"], ["top_fashion_cardigan", "Cardigan"], ["top_fashion_jacket", "Denim Jacket"]]
const DRESSES := [["top_fashion_fitteddress", "Fitted Dress"], ["top_fashion_loosedress", "Loose Dress"]]
const FASHION_BOTTOMS := [["miniskirt", "Mini Skirt"], ["midiskirt", "Midi Skirt"], ["maxiskirt", "Maxi Skirt"],
	["leggings", "Leggings"], ["fitjeans", "Fitted Jeans"], ["tailoredshorts", "Tailored Shorts"]]
const FOOTWEAR := [["trainers", "Classic Trainers"], ["streettrainers", "Street Trainers"],
	["heels", "Block Heels"], ["boots", "Ankle Boots"], ["sandals", "Strap Sandals"]]
const FASHION_LOOKS := [
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
]
const HATS := [["head_bare", "None"], ["head_cap", "Cap"], ["head_beanie", "Beanie"], ["head_phones", "Headphones"]]
const EYEWEAR := [["face_none", "None"], ["face_shades", "Shades"]]
const SHOES := [["shoes_classic", "White"], ["shoes_blackout", "Black"], ["shoes_gum", "Gum Sole"], ["shoes_royal", "Royal"],
	["shoes_volt", "Volt"], ["shoes_gold", "Gold"]]

## Natural skin tones, light to deep.
const SKIN := ["#f1d2bd", "#e6b796", "#d39d78", "#b97c58", "#9a6142", "#7a4a30", "#5b3522", "#3e2418"]
const HAIR := ["#0b0907", "#2a1b12", "#4e3220", "#7a4a2a", "#a0522d", "#c9a165", "#e3cf9e", "#8d8d8f", "#d9d7d2"]
## Clothes: the colours people actually wear.
const CLOTH := ["#f2f1ec", "#c9c4b8", "#1a1c20", "#3b3f46", "#1f2d4a", "#3f6db3", "#8fb3d9", "#5d1f2a",
	"#a8322d", "#d9822b", "#e3c74a", "#2f4a33", "#6f8a52", "#b59a74", "#6b4a3a", "#c96f92"]
const TROUSERS := ["#1a1c20", "#3b3f46", "#25304a", "#2f4a73", "#8a7a5a", "#c9bc9c", "#3d4530", "#5a3d2c", "#e8e6df"]

static func tops_for(body: String) -> Array:
	return TOPS + FASHION_TOPS + DRESSES if body == "b" else TOPS


static func bottoms_for(body: String) -> Array:
	return LOWER_CUTS + FASHION_BOTTOMS if body == "b" else LOWER_CUTS


static func is_dress(id: String) -> bool:
	return id == DRESSES[0][0] or id == DRESSES[1][0]


const DEFAULT := {"body": "a", "face": "hero_ade", "hair": "hair_natural", "top": "top_polo", "top_col": "#3f6db3",
	"trousers": "auto", "pants_col": "#3b3f46", "shoes": "shoes_classic", "footwear": "trainers", "head": "head_bare", "eyewear": "face_none",
	"skin": "", "hair_col": ""}


static func current(flags: Dictionary) -> Dictionary:
	var d: Dictionary = DEFAULT.duplicate()
	var saved = flags.get("look", {})
	if saved is Dictionary:
		for k in saved:
			if d.has(k):
				d[k] = String(saved[k])
	if String(d["body"]) not in ["a", "b"]:
		d["body"] = "a"
	d["hair"] = Shop.hair_id(d["hair"])
	var body := String(d["body"])
	if not bottoms_for(body).any(func(entry): return entry[0] == d["trousers"]):
		d["trousers"] = "auto"
	if body != "b" and String(d["top"]).begins_with("top_fashion_"):
		d["top"] = DEFAULT["top"]
	if body != "b" or not FOOTWEAR.any(func(entry): return entry[0] == d["footwear"]):
		d["footwear"] = "trainers"
	# (a face belongs to a body type: switching body takes that body's first face)
	var fl := faces_for(String(d["body"]))
	if not fl.any(func(f): return f[0] == d["face"]):
		d["face"] = fl[0][0]
	return d


## The rig look (CharacterRig.apply_look) for these choices. "" skin/hair
## colour = the face's own.
static func build(l: Dictionary) -> Dictionary:
	var body := String(l.get("body", "a"))
	var top := String(l.get("top", "top_polo"))
	if body != "b" and top.begins_with("top_fashion_"):
		top = DEFAULT["top"]
	var look := Shop.look({"face": l.get("eyewear", "face_none"), "head": l.get("head", "head_bare"),
		"top": top, "hero": l.get("face", "hero_ade"), "hair": l.get("hair", "hair_natural"),
		"pants": "pants_navy", "shoes": l.get("shoes", "shoes_classic"), "suit": "sky"})
	if String(l.get("skin", "")) != "":
		look["skin"] = Color(String(l["skin"]))
	if String(l.get("hair_col", "")) != "":
		look["hair"] = Color(String(l["hair_col"]))
	look["body"] = String(l.get("body", "a"))
	look["suit"] = Color(String(l.get("top_col", DEFAULT["top_col"])))
	look["pants"] = Color(String(l.get("pants_col", DEFAULT["pants_col"])))
	# Bare hands (the hero model always wears gloves): the glove drawn in the
	# skin colour as the skin texture renders it (warmer and a shade deeper
	# than the nominal tone, or pale hands read as white gloves).
	var sk: Color = look["skin"]
	look["glove"] = Color(sk.r * 0.8, sk.g * 0.7, sk.b * 0.66)
	look["bare_hands"] = true
	var lower := String(l.get("trousers", "auto"))
	if lower == "auto" or not bottoms_for(body).any(func(entry): return entry[0] == lower):
		lower = "chinos" if top in ["top_shirt", "top_blazer"] else "cargo"
		if top == "top_fashion_bodysuit":
			lower = "leggings"
	look["trousers"] = "dress" if is_dress(top) else lower
	look["footwear"] = l.get("footwear", "trainers") if body == "b" else "trainers"
	return look


## The face's own colours (for showing "default" swatches).
static func face_colors(face_id: String) -> Dictionary:
	var it := Shop.item(face_id)
	return {"skin": it.get("skin", Color.WHITE), "hair": it.get("hair", Color.BLACK)}


static func label(list: Array, id: String) -> String:
	for x in list:
		if x[0] == id:
			return x[1]
	return id
