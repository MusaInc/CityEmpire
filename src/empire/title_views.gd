class_name TitleViews
extends RefCounted
## The title menu's cinematic backdrops (config/empire/title_views.json):
## hand-placed cameras around the real world, each with its own hour and
## weather and a slow dolly from (eye, look) to (eye2, look2). A different
## view every launch – never the one you saw last time.
##
## Each view: id, name (shown small on the menu), mood, hour, weather, fov,
## eye/look (start), eye2/look2 (end; optional = a locked-off shot), dur
## (seconds for one pass; the camera eases there and back). "ground": [x, z]
## makes every y relative to the ground there.
##
## Review them all: --title-tour=<dir> [--title-ui] [--title-wait=s].
## Views with "art": true are never on the menu: they photograph the city
## for the phone's launcher tiles (tools/brand/app_art.py).

const PATH := "res://config/empire/title_views.json"
const LAST := "user://title.cfg"

static var _views: Array = []


static func all() -> Array:
	if _views.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_views = (d as Dictionary).get("views", [])
	return _views


static func by_id(id: String) -> Dictionary:
	for v in all():
		if String(v.get("id", "")) == id:
			return v
	return {}


## A view other than last launch's (remembered in user://title.cfg).
static func pick(force := "") -> Dictionary:
	var vs := all()
	if vs.is_empty():
		return {}
	if force != "":
		var f := by_id(force)
		if not f.is_empty():
			return f
	var cfg := ConfigFile.new()
	cfg.load(LAST)
	var last := String(cfg.get_value("title", "last", ""))
	var menu: Array = vs.filter(func(v): return not bool(v.get("art", false)))
	var pool: Array = menu.filter(func(v): return String(v.get("id", "")) != last)
	if pool.is_empty():
		pool = menu
	var v: Dictionary = pool[randi() % pool.size()]
	cfg.set_value("title", "last", String(v.get("id", "")))
	cfg.save(LAST)
	return v


static func _v3(a, base_y: float) -> Vector3:
	var arr: Array = a if a is Array else [0, 0, 0]
	return Vector3(float(arr[0]), float(arr[1]) + base_y, float(arr[2]))


## Resolved world-space points: {eye, look, eye2, look2, focus}.
static func resolve(v: Dictionary, layout: CityLayout) -> Dictionary:
	var by := 0.0
	if v.has("ground") and layout:
		var g: Array = v["ground"]
		var gy := layout.ground_y(float(g[0]), float(g[1]))
		by = 1.0 if is_nan(gy) else gy
	# ("ground_eye_only": the camera stands on the ground there, the target
	# is absolute – a view from the hills back to the city.)
	var ly := 0.0 if bool(v.get("ground_eye_only", false)) else by
	var eye := _v3(v.get("eye"), by)
	var look := _v3(v.get("look"), ly)
	var eye2 := _v3(v["eye2"], by) if v.has("eye2") else eye
	var look2 := _v3(v["look2"], ly) if v.has("look2") else look
	# Stream round the middle of what the camera sees, not the camera.
	var mid := eye.lerp(look, 0.45)
	var focus := _v3(v["focus"], by) if v.has("focus") else Vector3(mid.x, by, mid.z)
	return {"eye": eye, "look": look, "eye2": eye2, "look2": look2, "focus": focus}


## Camera transform `t` seconds into the view: a slow ease out and back.
static func at(r: Dictionary, dur: float, t: float) -> Transform3D:
	var ph := fmod(t / maxf(dur, 1.0), 2.0)
	var k := ph if ph <= 1.0 else 2.0 - ph
	k = 0.5 - 0.5 * cos(k * PI)
	var eye: Vector3 = (r["eye"] as Vector3).lerp(r["eye2"], k)
	var look: Vector3 = (r["look"] as Vector3).lerp(r["look2"], k)
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
