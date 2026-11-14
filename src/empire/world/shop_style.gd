class_name ShopStyle
extends RefCounted
## How each kind of shop looks, and each shop's own brand.
##
##  * look(type): the interior – wall and floor finish, ceiling lights,
##    lighting colour, what fills the spare floor (seating, mannequins,
##    plinths) – so a café, a takeaway and a clothing store don't read as
##    the same corner shop.
##  * brand(name, type): a shop's identity, stable from its name: a colour
##    pair, a typeface (OFL fonts in assets/fonts/brand), a fascia style
##    (painted, lightbox, neon, script) and a roundel logo with its initial.
##    QuikSave keeps its red-and-white.

const FONT_DIR := "res://assets/fonts/brand/"
const FONTS := {
	"serif": "PlayfairDisplay.ttf", "display": "BebasNeue-Regular.ttf", "script": "Pacifico-Regular.ttf",
	"condensed": "Oswald.ttf", "fat": "AbrilFatface-Regular.ttf", "round": "Righteous-Regular.ttf",
	"retro": "Lobster-Regular.ttf", "neon": "Monoton-Regular.ttf",
}

## [primary, accent] colour pairs and typefaces per kind of shop.
const PALETTES := {
	"convenience": [["#1f6b5c", "#f2c14e"], ["#26457d", "#f4f1e8"], ["#6a2f6b", "#f6d6e6"], ["#2f6e2f", "#f2e6b8"],
		["#7a2f2a", "#f3e2c4"], ["#22526b", "#9fe1e8"], ["#4a4f5a", "#f5b13d"], ["#1e5f8a", "#ffffff"]],
	"clothing": [["#141416", "#c9a45c"], ["#1d2a44", "#efe6d2"], ["#5c1f2e", "#f0c9c8"], ["#25402f", "#c7a96b"],
		["#f2efe9", "#141416"], ["#3d3a6b", "#e8d7a8"], ["#8a6a4e", "#f7efe2"]],
	"cafe": [["#5d7a5a", "#f3ead6"], ["#a8502f", "#f6e7cf"], ["#3a2a22", "#d9b26a"], ["#2f6a6a", "#f6c9a8"],
		["#e9dcc4", "#3a2a22"], ["#7a4a6b", "#f3e3d0"]],
	"takeaway": [["#c8202a", "#ffd23f"], ["#141416", "#ff3b3b"], ["#f07a1a", "#141416"], ["#1c7a3a", "#ffffff"],
		["#2a2a8a", "#ffcc33"], ["#b0173a", "#ffffff"]],
	"bakery": [["#e9b7c4", "#5a3a2a"], ["#f2e6cf", "#2a3a5a"], ["#a9cfc8", "#5a3a2a"], ["#5a3a2a", "#f2d9a8"],
		["#d8a64a", "#2b2b2b"]],
	"phones": [["#f4f6f8", "#1e6fe0"], ["#121418", "#29d3e8"], ["#5b2aa8", "#ffffff"], ["#0f3d5c", "#7fe0ff"],
		["#e8e8ea", "#111111"]],
}
const TYPEFACES := {
	"convenience": ["condensed", "display", "round", ""],
	"clothing": ["serif", "display", "fat", "condensed"],
	"cafe": ["script", "retro", "serif"],
	"takeaway": ["round", "display", "neon", "fat"],
	"bakery": ["retro", "script", "serif"],
	"phones": ["condensed", "display", "round"],
}
const SIGN_STYLES := {
	"convenience": ["painted", "lightbox"],
	"clothing": ["painted", "painted", "lightbox"],
	"cafe": ["painted", "script"],
	"takeaway": ["neon", "lightbox", "neon"],
	"bakery": ["painted", "script"],
	"phones": ["lightbox", "lightbox", "neon"],
}

static var _fonts := {}
## The player's own brand (Empire.brand, set by the game when it changes):
## every shop you run wears it. Empty = each shop keeps its own identity.
static var house := {}
## Your head office's tier (0 = none): the lobby and tower crown wear your brand.
static var hq_tier := 0

## Brand studio choices: [primary, accent] pairs, typefaces, fascia styles.
const HOUSE_PALETTES := [["#0f3d5c", "#f5b13d"], ["#141416", "#c9a45c"], ["#c8202a", "#ffffff"], ["#1f6b5c", "#f2e6b8"],
	["#26457d", "#f4f1e8"], ["#5b2aa8", "#ffd23f"], ["#f2efe9", "#141416"], ["#e9b7c4", "#3a2a22"],
	["#f07a1a", "#141416"], ["#2f6a6a", "#f6c9a8"], ["#121418", "#29d3e8"], ["#7a2f2a", "#f3e2c4"]]
const HOUSE_FACES := ["display", "condensed", "round", "serif", "fat", "script", "retro", "neon"]
const HOUSE_SIGNS := ["painted", "lightbox", "neon", "script"]
const FACE_NAMES := {"display": "Bold", "condensed": "Modern", "round": "Friendly", "serif": "Classic", "fat": "Fashion",
	"script": "Script", "retro": "Retro", "neon": "Neon", "": "Plain"}
const SIGN_NAMES := {"painted": "Painted", "lightbox": "Lightbox", "neon": "Neon", "script": "Signwritten"}
const NAME_A := ["Urban", "Golden", "Harbour", "Crown", "Bright", "Metro", "Corner", "Liberty", "Apex", "Union", "Northern",
	"Royal", "Copper", "Silver", "Blue", "Summit"]
const NAME_B := ["& Co", "Market", "Brothers", "Goods", "House", "Stores", "Collective", "Trading Co", "Supply", "Works",
	"Exchange", "Group"]


## A brand-studio suggestion (stable for a roll number).
static func suggest_name(roll: int) -> String:
	var r := absi(hash(roll * 7919 + 13))
	return "%s %s" % [NAME_A[r % NAME_A.size()], NAME_B[(r / 17) % NAME_B.size()]]


## A sensible starting brand for a new company (`name` from the brand studio).
static func default_house(name: String) -> Dictionary:
	return {"name": name, "primary": "#0f3d5c", "accent": "#f5b13d", "face": "display", "sign": "lightbox"}


## The identity dictionary (as brand()) for a house brand.
static func house_ident(h: Dictionary) -> Dictionary:
	var nm := String(h.get("name", ""))
	return {"primary": Color(String(h.get("primary", "#0f3d5c"))), "accent": Color(String(h.get("accent", "#f5b13d"))),
		"face": String(h.get("face", "display")), "sign": String(h.get("sign", "lightbox")), "initial": initial_of(nm),
		"name": nm}


## The first letter of a name's first real word ("" for none).
static func initial_of(name: String) -> String:
	for w in name.split(" ", false):
		if w.length() > 0 and w[0] != "&":
			return w.left(1).to_upper()
	return ""


static func font(key: String) -> Font:
	if key == "" or not FONTS.has(key):
		return EmpireStyle.font("black")
	if not _fonts.has(key):
		_fonts[key] = load(FONT_DIR + FONTS[key])
	return _fonts[key]


## A shop's identity, stable from its name (and kind of shop).
static func brand(name: String, type_id: String, rival := false) -> Dictionary:
	if rival:
		return {"primary": Color(CityLife.rival_cfg().get("colour", "#d8262f")), "accent": Color.WHITE, "face": "display",
			"sign": "lightbox", "initial": "Q"}
	var h := absi(name.hash())
	var pals: Array = PALETTES.get(type_id, PALETTES["convenience"])
	var pal: Array = pals[h % pals.size()]
	var faces: Array = TYPEFACES.get(type_id, TYPEFACES["convenience"])
	var signs: Array = SIGN_STYLES.get(type_id, SIGN_STYLES["convenience"])
	var initial := initial_of(name)
	return {"primary": Color(pal[0]), "accent": Color(pal[1]), "face": faces[(h / 7) % faces.size()],
		"sign": signs[(h / 13) % signs.size()], "initial": initial}


## Shopfront joinery, so a street of shops isn't one design repeated:
##  * timber: painted heritage front, tall stall risers with raised panels
##    (bakeries, cafés, independents);
##  * aluminium: anodised frames on a polished granite riser (chains, takeaways);
##  * steel: slim black frames, glass almost to the floor (fashion, tech).
## Plus whether it has a roller shutter (down when it's shut at night).
## `type_id` "" is an empty unit. Stable per unit (`h`, its id's hash).
const HERITAGE := [Color(0.11, 0.24, 0.2), Color(0.34, 0.1, 0.1), Color(0.12, 0.16, 0.27), Color(0.09, 0.09, 0.1),
	Color(0.86, 0.83, 0.75), Color(0.24, 0.3, 0.32)]
static func front(type_id: String, h: int, brand_c: Color, chain := false) -> Dictionary:
	var pick := float((h / 3) % 100) / 100.0
	var style := "aluminium"
	if chain or type_id == "takeaway":
		style = "aluminium"
	elif type_id in ["cafe", "bakery"]:
		style = "timber" if pick < 0.75 else "steel"
	elif type_id == "clothing":
		style = "steel" if pick < 0.55 else "timber"
	elif type_id == "phones":
		style = "steel" if pick < 0.6 else "aluminium"
	elif type_id == "convenience":
		style = "timber" if pick < 0.4 else "aluminium"
	else:
		style = "timber" if pick < 0.35 else "aluminium"   # an empty unit: whatever was there
	var f := {"style": style, "panels": false, "mullion": 0.03}
	match style:
		"timber":
			# Painted in a heritage colour, or a deep shade of the brand's own.
			var c: Color = HERITAGE[h % HERITAGE.size()] if (h / 11) % 3 != 0 or type_id == "" else brand_c.darkened(0.45)
			if type_id == "":
				c = c.lerp(Color(0.5, 0.5, 0.48), 0.35)  # faded paint on an empty shop
			f.merge({"frame": c, "riser": 0.55, "riser_col": c, "panels": true, "mullion": 0.045}, true)
		"steel":
			f.merge({"frame": Color(0.07, 0.07, 0.08), "riser": 0.12, "riser_col": Color(0.07, 0.07, 0.08), "mullion": 0.022}, true)
		_:
			var al := Color(0.63, 0.65, 0.67) if (h / 7) % 3 != 0 else Color(0.33, 0.28, 0.22)  # silver or bronze
			f.merge({"frame": al, "riser": 0.34, "riser_col": Color(0.15, 0.15, 0.16)}, true)
	var shutter_share := 0.5 if type_id in ["takeaway", "phones", "convenience"] else 0.2
	f["shutter"] = type_id != "" and float((h / 17) % 100) / 100.0 < shutter_share
	f["shutter_col"] = Color(0.56, 0.58, 0.6) if (h / 5) % 2 == 0 else brand_c.darkened(0.35)
	return f


## Interior finish per kind of shop.
static func look(type_id: String) -> Dictionary:
	match type_id:
		"clothing":
			return {"wall": Color(0.93, 0.91, 0.87), "floor": Color(0.72, 0.56, 0.4), "floor_style": 3, "ceiling": Color(0.16, 0.16, 0.17),
				"lights": "track", "tint": Color(1.0, 0.9, 0.78), "decor": "boutique", "dado": false}
		"cafe":
			return {"wall": Color(0.9, 0.86, 0.78), "floor": Color(0.45, 0.31, 0.2), "floor_style": 3, "ceiling": Color(0.82, 0.8, 0.76),
				"lights": "pendant", "tint": Color(1.0, 0.84, 0.62), "decor": "seating", "dado": true, "tiles": true}
		"takeaway":
			return {"wall": Color(0.95, 0.95, 0.94), "floor": Color(0.62, 0.22, 0.2), "floor_style": 0, "ceiling": Color(0.92, 0.92, 0.9),
				"lights": "panel", "tint": Color(1.0, 0.98, 0.94), "decor": "stools", "dado": false, "tiles": true}
		"bakery":
			return {"wall": Color(0.95, 0.9, 0.82), "floor": Color(0.66, 0.42, 0.3), "floor_style": 0, "ceiling": Color(0.9, 0.87, 0.82),
				"lights": "pendant", "tint": Color(1.0, 0.86, 0.66), "decor": "seating", "dado": true}
		"phones":
			return {"wall": Color(0.96, 0.96, 0.97), "floor": Color(0.86, 0.86, 0.87), "floor_style": 4, "ceiling": Color(0.97, 0.97, 0.98),
				"lights": "linear", "tint": Color(0.95, 0.97, 1.0), "decor": "plinths", "dado": false}
	return {"wall": Color(0.8, 0.77, 0.71), "floor": Color(0.72, 0.7, 0.66), "floor_style": 0, "ceiling": Color(0.78, 0.78, 0.76),
		"lights": "grid", "tint": Color(1.0, 0.97, 0.92), "decor": "corner", "dado": true}
