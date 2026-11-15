class_name HeroLook
extends RefCounted
## Your character in City Empire: who you are (face, skin, hair) and what you
## wear. Kept in Empire.flags["look"] as plain strings (ids and hex colours)
## so it saves with the empire. Everything is free: it's your character, not
## a shop.

const FACES := [["hero_ade", "Ade"], ["hero_kai", "Kai"], ["hero_malik", "Malik"], ["hero_ren", "Ren"], ["hero_theo", "Theo"]]
const HAIRS := [["hair_natural", "Natural"], ["hair_buzz", "Buzz Cut"], ["hair_crop", "Crop"], ["hair_fade", "High Fade"],
	["hair_curls", "Curls"], ["hair_pixie", "Pixie"], ["hair_bob", "Bob"], ["hair_ponytail", "Ponytail"], ["hair_bun", "Bun"]]
const TOPS := [["top_tee", "T-Shirt"], ["top_polo", "Polo"], ["top_shirt", "Shirt"], ["top_jumper", "Jumper"],
	["top_hoodie", "Hoodie"], ["top_blazer", "Blazer & Tie"], ["top_long", "Base Layer"]]
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

const DEFAULT := {"face": "hero_ade", "hair": "hair_natural", "top": "top_polo", "top_col": "#3f6db3",
	"pants_col": "#3b3f46", "shoes": "shoes_classic", "head": "head_bare", "eyewear": "face_none",
	"skin": "", "hair_col": ""}


static func current(flags: Dictionary) -> Dictionary:
	var d: Dictionary = DEFAULT.duplicate()
	var saved = flags.get("look", {})
	if saved is Dictionary:
		for k in saved:
			if d.has(k):
				d[k] = String(saved[k])
	return d


## The rig look (CharacterRig.apply_look) for these choices. "" skin/hair
## colour = the face's own.
static func build(l: Dictionary) -> Dictionary:
	var look := Shop.look({"face": l.get("eyewear", "face_none"), "head": l.get("head", "head_bare"),
		"top": l.get("top", "top_polo"), "hero": l.get("face", "hero_ade"), "hair": l.get("hair", "hair_natural"),
		"pants": "pants_navy", "shoes": l.get("shoes", "shoes_classic"), "suit": "sky"})
	if String(l.get("skin", "")) != "":
		look["skin"] = Color(String(l["skin"]))
	if String(l.get("hair_col", "")) != "":
		look["hair"] = Color(String(l["hair_col"]))
	look["suit"] = Color(String(l.get("top_col", DEFAULT["top_col"])))
	look["pants"] = Color(String(l.get("pants_col", DEFAULT["pants_col"])))
	# Bare hands (the hero model always wears gloves): the glove drawn in the
	# skin colour as the skin texture renders it (warmer and a shade deeper
	# than the nominal tone, or pale hands read as white gloves).
	var sk: Color = look["skin"]
	look["glove"] = Color(sk.r * 0.8, sk.g * 0.7, sk.b * 0.66)
	look["bare_hands"] = true
	look["trousers"] = "chinos" if String(l.get("top", "")) in ["top_shirt", "top_blazer"] else "cargo"
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
