class_name DevServer
extends Node
## Persistent visual-dev session (tools/citydev): one running game, a free
## camera driven over HTTP, instant screenshots. Bound to 127.0.0.1 only -
## reach it through the authenticated proxy (Caddy /citydev/, dashboard
## login) or an SSH/Tailscale tunnel. Started by `--devserver=<port>`.
##
## Endpoints (GET, query parameters; every camera parameter is optional and
## any request may carry them - they apply before the reply):
##   /                    live view page (frames on request, WASD/QE/mouse)
##   /frame.jpg           the current frame, JPEG (w= width, default 960)
##   /shot.png            a full-size PNG (name= also saves <devshots>/<name>.png)
##   /cam                 x y z yaw pitch fov (deg) | agl= height above ground
##   /look                x,y,z,lx,ly,lz in one "v=" (world m; y above ground)
##   /move                f r u (m, camera frame), dyaw dpitch (deg)
##   /goto                x z [agl] - jump the camera (the city streams there)
##   /hour                h= (0-24), freeze=1 holds the clock there
##   /state               JSON: camera, hero, fps, frame time, memory
##   /hero                show=1|0 - the hero in the shot or not
##   /restart             quits with code 3 (the service starts it again)
## Camera changes wait `settle` drawn frames (default 2) before replying, so
## the next frame/shot already shows the new place.

const IDLE_QUIT := 3600.0      # s without a request: quit (frees ~3 GB; `citydev up` restarts)
const FOLLOW := 60.0           # m: the (hidden) hero is moved under the camera past this, so chunks stream

var game: EmpireGame
var port := 8190
var shots_dir := ""
var pos := Vector3.ZERO
var yaw := 0.0                 # deg, 0 = looking -Z (north)
var pitch := -12.0             # deg
var fov := 62.0
var _server := TCPServer.new()
var _clients: Array = []
var _idle := 0.0
var _freeze := -1.0
var _frame_ms := 0.0
var geo := false               # geometry inspector: flat colours, paused world, frames on request
var mode := "flat"             # geo: "flat" | "wire"
var _geo_done := {}            # instance ids already recoloured
var _mats := {}                # colour -> StandardMaterial3D
var _draw_ms := 0.0


func start(p_game: EmpireGame, p_port: int, p_shots: String, p_geo := false) -> void:
	game = p_game
	geo = p_geo
	port = p_port
	shots_dir = p_shots
	process_mode = Node.PROCESS_MODE_ALWAYS
	var err := _server.listen(port, "127.0.0.1")
	print("DEVSERVER listening on 127.0.0.1:%d (%s)" % [port, error_string(err)])
	var hp := game.player.global_position
	pos = hp + Vector3(0, 8.0, 14.0)
	game.player.visible = false
	game.ui.visible = false
	game.camera.cine = func(_dt: float) -> Array:
		return [_xf(), fov]
	if geo:
		Engine.max_fps = 30          # (nothing is drawn between requests: don't spin the CPU)
		_geo_setup()


func _xf() -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0), EULER_ORDER_YXZ)
	return Transform3D(b, pos)


var _beat := 0.0


func _process(dt: float) -> void:
	_frame_ms = lerpf(_frame_ms, dt * 1000.0, 0.2)
	_beat += dt
	if _beat > 5.0 and OS.get_environment("CITYDEV_DEBUG") != "":
		_beat = 0.0
		print("DEVSERVER tick clients=", _clients.size(), " pending=", _server.is_connection_available())
	if _freeze >= 0.0:
		game.empire.minute = _freeze
	if not geo:
		# (full mode: the game camera runs first each frame; this wins)
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.global_transform = _xf()
			cam.fov = fov
			cam.far = 6000.0
	_idle += dt
	if _idle > IDLE_QUIT and _clients.is_empty():
		print("DEVSERVER idle %d s: quitting" % int(IDLE_QUIT))
		get_tree().quit(0)
	while _server.is_connection_available():
		_clients.append({"c": _server.take_connection(), "buf": PackedByteArray(), "t0": Time.get_ticks_msec(), "busy": false})
	for cl: Dictionary in _clients.duplicate():
		var c: StreamPeerTCP = cl["c"]
		c.poll()
		# (wall clock: a slow frame must not time out a request it hasn't read yet)
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(cl["t0"]) > 600000:
			_clients.erase(cl)
			continue
		if cl["busy"]:
			continue
		var n := c.get_available_bytes()
		var buf: PackedByteArray = cl["buf"]
		if n > 0:
			buf.append_array(c.get_data(n)[1])
			cl["buf"] = buf   # (packed arrays are values: write it back)
		var s := buf.get_string_from_utf8()
		if s.contains("\r\n\r\n"):
			cl["busy"] = true
			_idle = 0.0
			_handle(cl, s.get_slice("\r\n", 0))


func _handle(cl: Dictionary, line: String) -> void:
	var target := line.get_slice(" ", 1)
	var path := target.get_slice("?", 0).trim_prefix("/")
	var q := {}
	if target.contains("?"):
		for kv in target.get_slice("?", 1).split("&"):
			q[kv.get_slice("=", 0).uri_decode()] = kv.get_slice("=", 1).uri_decode() if kv.contains("=") else "1"
	var moved := _apply(path, q)
	if moved:
		_follow()
		if not geo:
			for i in int(q.get("settle", "2")):
				await RenderingServer.frame_post_draw
	match path:
		"", "index.html":
			_reply(cl, 200, "text/html; charset=utf-8", PAGE.to_utf8_buffer())
		"frame.jpg":
			var img := await _frame()
			var w := int(q.get("w", "960"))
			if img.get_width() > w:
				img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_BILINEAR)
			_reply(cl, 200, "image/jpeg", img.save_jpg_to_buffer(float(q.get("quality", "0.75"))))
		"shot.png":
			var img2 := await _frame()
			if q.has("name") and shots_dir != "":
				DirAccess.make_dir_recursive_absolute(shots_dir)
				img2.save_png(shots_dir.path_join(String(q["name"]).validate_filename() + ".png"))
			_reply(cl, 200, "image/png", img2.save_png_to_buffer())
		"state", "cam", "look", "move", "goto", "hour", "hero":
			_reply(cl, 200, "application/json", JSON.stringify(_state()).to_utf8_buffer())
		"pick":
			_reply(cl, 200, "application/json", JSON.stringify(_pick(float(q.get("u", "0.5")), float(q.get("v", "0.5")))).to_utf8_buffer())
		"restart":
			_reply(cl, 200, "application/json", '{"restarting":true}'.to_utf8_buffer())
			await get_tree().process_frame
			get_tree().quit(3)
		_:
			_reply(cl, 404, "text/plain", "not found".to_utf8_buffer())


## Applies any camera / world parameters in q; true when the view changed.
func _apply(path: String, q: Dictionary) -> bool:
	var moved := false
	var gy := func(x: float, z: float) -> float: return game.layout.ground_y(x, z)
	if path == "goto" and q.has("x") and q.has("z"):
		var x := float(q["x"])
		var z := float(q["z"])
		pos = Vector3(x, float(gy.call(x, z)) + float(q.get("agl", "2.0")), z)
		moved = true
	elif path == "look" and q.has("v"):
		var v := String(q["v"]).split_floats(",")
		var from := Vector3(v[0], v[1] + float(gy.call(v[0], v[2])), v[2])
		var to := Vector3(v[3], v[4] + float(gy.call(v[3], v[5])), v[5])
		pos = from
		var d := (to - from).normalized()
		yaw = rad_to_deg(atan2(-d.x, -d.z))
		pitch = rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
		moved = true
	else:
		for k in ["x", "y", "z"]:
			if q.has(k):
				pos[["x", "y", "z"].find(k)] = float(q[k])
				moved = true
		if q.has("agl"):
			pos.y = float(gy.call(pos.x, pos.z)) + float(q["agl"])
			moved = true
	for k in ["yaw", "pitch", "fov"]:
		if q.has(k):
			set(k, float(q[k]))
			moved = true
	if q.has("dyaw") or q.has("dpitch"):
		yaw += float(q.get("dyaw", "0"))
		pitch = clampf(pitch + float(q.get("dpitch", "0")), -89.0, 89.0)
		moved = true
	if q.has("f") or q.has("r") or q.has("u"):
		var fwd := Vector3(-sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw)))
		var right := Vector3(cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))
		pos += fwd * float(q.get("f", "0")) + right * float(q.get("r", "0")) + Vector3.UP * float(q.get("u", "0"))
		moved = true
	if q.has("h"):
		game.empire.minute = fposmod(float(q["h"]), 24.0) * 60.0
		_freeze = game.empire.minute if q.get("freeze", "0") == "1" else -1.0
		moved = true
	if q.has("mode") and geo:
		mode = String(q["mode"])
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if mode == "wire" else Viewport.DEBUG_DRAW_DISABLED
		moved = true
	if path == "hero" and q.has("show"):
		game.player.visible = q["show"] == "1"
		moved = true
	return moved


## Keeps the (hidden) hero under the camera, so the city streams in round
## wherever the camera goes (and Skyport / venues load near it).
func _follow() -> void:
	var hp := game.player.global_position
	if Vector2(hp.x - pos.x, hp.z - pos.z).length() > FOLLOW:
		var g := game.layout.ground_y(pos.x, pos.z)
		game._teleport(Vector3(pos.x, g + 1.0, pos.z), 0.0)


## The current frame as an image. Geometry mode draws exactly one frame now
## (the render loop is off); otherwise the next normally drawn frame.
func _frame() -> Image:
	if geo:
		_geo_scan(game)
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.global_transform = _xf()
			cam.fov = fov
			cam.far = 6000.0
		# (the camera's new transform and freshly streamed chunks only reach
		# the renderer at the next main-loop iteration: drawing now showed the
		# previous view)
		await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		# (twice: the viewport texture read back holds the frame drawn before
		# the last swap - one draw alone returned the previous camera)
		RenderingServer.force_draw(true, 0.0)
		RenderingServer.force_draw(true, 0.0)
		_draw_ms = (Time.get_ticks_usec() - t0) / 1000.0
	else:
		for i in 3:
			await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# ------------------------------------------------------------------ geometry mode
## Category colours (the real meshes and transforms, flat materials).
const COL := {
	"building": Color(0.86, 0.8, 0.68), "ground": Color(0.42, 0.43, 0.46), "island": Color(0.5, 0.56, 0.44),
	"water": Color(0.25, 0.45, 0.75), "terrain": Color(0.52, 0.58, 0.42), "bridge": Color(0.95, 0.55, 0.15),
	"rail": Color(0.62, 0.42, 0.8), "vehicle": Color(0.9, 0.2, 0.2), "tree": Color(0.25, 0.6, 0.25),
	"furniture": Color(0.3, 0.3, 0.32), "coast": Color(0.85, 0.78, 0.55), "other": Color(0.75, 0.75, 0.78),
}
const HIDE := ["VehicleFx", "Traffic", "Walkers", "Crowd", "ShadowProxy", "Rain", "Clouds", "Birds", "Flare", "Glow", "Beam", "Smoke"]


func _geo_setup() -> void:
	get_tree().paused = true          # no AI, physics, animation, weather, clock
	var at := game.atmosphere
	if at:
		if at.sun:
			at.sun.shadow_enabled = false
			at.sun.light_energy = 1.0
			at.sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
		if at.env:
			var e := at.env
			e.background_mode = Environment.BG_COLOR
			e.background_color = Color(0.62, 0.72, 0.82)
			e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			e.ambient_light_color = Color(0.55, 0.55, 0.58)
			e.ambient_light_energy = 1.0
			e.fog_enabled = false
			e.volumetric_fog_enabled = false
			e.glow_enabled = false
			e.ssao_enabled = false
			e.ssr_enabled = false
			e.sdfgi_enabled = false
			e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			e.adjustment_enabled = false
	_geo_scan(game)
	print("DEVSERVER geometry mode: %d instances recoloured" % _geo_done.size())


func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.disable_receive_shadows = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED   # (show open / inverted faces instead of hiding them)
		_mats[c] = m
	return _mats[c]


## Skyport's ground: one mesh, roads / paving / grass as vertex colours
## (flat island colour hid every road on the island).
func _vc_mat() -> StandardMaterial3D:
	if not _mats.has("vc"):
		var m := _mat(Color.WHITE).duplicate() as StandardMaterial3D
		m.vertex_color_use_as_albedo = true
		_mats["vc"] = m
	return _mats["vc"]


func _cat_of(n: Node, mat: Material) -> String:
	var p := String(n.get_path())
	for k in ["Bridge", "Harbour", "Westbank", "Truss", "Pylon"]:
		if p.contains(k):
			return "bridge"
	if p.contains("Rail") or p.contains("Viaduct") or p.contains("Train"):
		return "rail"
	if n.get_parent() is Car or p.contains("/Car_") or p.contains("Wheel") or (n is Node3D and _under_car(n)):
		return "vehicle"
	if p.contains("tree") or p.contains("Tree") or p.contains("Copse") or p.contains("Hedge"):
		return "tree"
	if p.contains("Props_") or p.contains("Furniture") or p.contains("Street"):
		return "furniture"
	if p.contains("Coast") or p.contains("Shore") or p.contains("Beach") or p.contains("Seabed"):
		return "coast"
	var sp := ""
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		sp = (mat as ShaderMaterial).shader.resource_path
	if sp.contains("building") or p.contains("Detail") or p.contains("Low"):
		return "building"
	if sp.contains("island_ground"):
		return "island"
	if sp.contains("ground") or p.contains("Road") or p.contains("Ground"):
		return "ground"
	if sp.contains("water") or p.contains("Water"):
		return "water"
	if sp.contains("hinterland") or p.contains("Hinterland") or p.contains("Mountain") or p.contains("Landform"):
		return "terrain"
	return "other"


func _under_car(n: Node) -> bool:
	var q := n.get_parent()
	for i in 4:
		if q == null:
			return false
		if q is Car:
			return true
		q = q.get_parent()
	return false


## Recolours every geometry instance not seen yet (new chunks stream in as
## the camera moves); hides moving crowds / GPU traffic / effects.
func _geo_scan(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var id := n.get_instance_id()
		if _geo_done.has(id):
			continue
		_geo_done[id] = true
		var gi := n as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var path := String(n.get_path())
		var hide := false
		for h in HIDE:
			if path.contains(h):
				hide = true
		if hide or n is GPUParticles3D or n is CPUParticles3D or n is Label3D or n is Sprite3D:
			gi.visible = false
			continue
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
		var src: Material = gi.material_override
		if src == null and mesh and mesh.get_surface_count() > 0:
			src = mesh.surface_get_material(0)
		var cat := _cat_of(n, src)
		gi.material_override = _mat(COL[cat]) if cat != "island" else _vc_mat()


## What lies under a screen point (u, v in 0..1): every instance whose
## bounds the view ray crosses within 600 m, with its geometry category.
func _pick(u: float, v: float) -> Array:
	var cam := get_viewport().get_camera_3d()
	cam.global_transform = _xf()
	cam.fov = fov
	var sz := get_viewport().get_visible_rect().size
	var o := cam.project_ray_origin(Vector2(u, v) * sz)
	var d := cam.project_ray_normal(Vector2(u, v) * sz)
	var out: Array = []
	for id in RenderingServer.instances_cull_ray(o, o + d * 600.0, cam.get_world_3d().scenario):
		var n := instance_from_id(id)
		if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
			var mat: Material = (n as GeometryInstance3D).material_override
			var cat := "?"
			for k in COL:
				if mat == _mats.get(COL[k]):
					cat = k
			var gi := n as GeometryInstance3D
			var bb: AABB = gi.global_transform * gi.get_aabb()
			var hit = bb.intersects_ray(o, d)
			var dist := 0.0 if bb.has_point(o) else (o.distance_to(hit) if hit != null else 9999.0)
			out.append({"node": String((n as Node).get_path()), "cat": cat, "dist": snappedf(dist, 0.1)})
	out.sort_custom(func(a, b): return a["dist"] < b["dist"])
	return out


func _state() -> Dictionary:
	return {"x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01), "z": snappedf(pos.z, 0.01), "yaw": snappedf(yaw, 0.1),
		"pitch": snappedf(pitch, 0.1), "fov": fov, "hour": snappedf(game.empire.minute / 60.0, 0.01), "frozen": _freeze >= 0.0,
		"hero": [snappedf(game.player.global_position.x, 0.1), snappedf(game.player.global_position.z, 0.1)],
		"fps": Engine.get_frames_per_second(), "frame_ms": snappedf(_frame_ms, 0.1), "geo": geo, "mode": mode,
		"draw_ms": snappedf(_draw_ms, 0.1),
		"mem_mb": int(OS.get_static_memory_usage() / 1048576)}


func _reply(cl: Dictionary, code: int, ctype: String, body: PackedByteArray) -> void:
	var c: StreamPeerTCP = cl["c"]
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [
		code, "OK" if code == 200 else "Not Found", ctype, body.size()]
	c.put_data(head.to_utf8_buffer())
	c.put_data(body)
	c.disconnect_from_host()
	_clients.erase(cl)


# Live view: relative URLs (works under the /citydev/ proxy prefix). Frames
# are fetched one after another (no stream): on a CPU-rendered VPS a frame
# costs ~0.3-1 s, so this is the honest frame rate with no buffering lag.
const PAGE := """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>City Empire dev view</title>
<style>
:root{color-scheme:dark}body{margin:0;background:#111;color:#ddd;font:14px system-ui,sans-serif}
#v{display:block;width:100%;max-width:1280px;margin:0 auto;cursor:grab;user-select:none}
#bar{display:flex;flex-wrap:wrap;gap:6px;padding:8px;max-width:1280px;margin:0 auto;align-items:center}
button,input{background:#222;color:#ddd;border:1px solid #444;border-radius:6px;padding:6px 10px;font:inherit}
input{width:80px}#st{font:12px monospace;opacity:.8}
</style></head><body>
<img id="v" alt="live frame">
<div id="bar">
<button onclick="go('move?u=5')">Up</button><button onclick="go('move?u=-5')">Down</button>
<button onclick="go('move?dpitch=-10')">Tilt down</button><button onclick="go('move?dpitch=10')">Tilt up</button>
x <input id="gx"> z <input id="gz"> <button onclick="go('goto?x='+gx.value+'&z='+gz.value+'&agl=3')">Go</button>
hour <input id="hr" value="13"> <button onclick="go('hour?h='+hr.value+'&freeze=1')">Set</button>
<button onclick="go('cam?mode=flat')">Flat</button><button onclick="go('cam?mode=wire')">Wire</button>
<button onclick="snap()">Screenshot</button>
<span id="st"></span></div>
<p style="max-width:1280px;margin:0 auto;padding:0 8px;opacity:.7">Keys: W/S forward/back, A/D strafe, Q/E down/up, arrows turn/tilt, Shift = 5x. Drag the view to look around.</p>
<script>
const v=document.getElementById('v'),st=document.getElementById('st');let busy=false,queued=null;
function frame(){v.src='frame.jpg?t='+Date.now();}
v.onload=v.onerror=()=>{setTimeout(frame,50);};
async function go(u){try{const r=await fetch(u);const j=await r.json();st.textContent=`x ${j.x} y ${j.y} z ${j.z} yaw ${j.yaw} pitch ${j.pitch} h ${j.hour} ${j.fps} fps`;}catch(e){st.textContent='offline: '+e;}}
function snap(){const n='dev_'+Date.now();window.open('shot.png?name='+n,'_blank');}
const step={w:'f=4',s:'f=-4',a:'r=-4',d:'r=4',q:'u=-2',e:'u=2',arrowleft:'dyaw=12',arrowright:'dyaw=-12',arrowup:'dpitch=6',arrowdown:'dpitch=-6'};
document.addEventListener('keydown',ev=>{if(ev.target.tagName==='INPUT')return;const k=step[ev.key.toLowerCase()];if(!k)return;ev.preventDefault();
 let u='move?'+k;if(ev.shiftKey)u=u.replace(/=(-?[0-9.]+)/,(m,n)=>'='+n*5);go(u+'&settle=0');});
let drag=null;v.addEventListener('mousedown',e=>{drag=[e.clientX,e.clientY];e.preventDefault();});
window.addEventListener('mouseup',e=>{if(!drag)return;const dx=e.clientX-drag[0],dy=e.clientY-drag[1];drag=null;
 if(Math.abs(dx)+Math.abs(dy)>3)go(`move?dyaw=${(-dx*0.15).toFixed(1)}&dpitch=${(-dy*0.15).toFixed(1)}&settle=0`);});
go('state');frame();
</script></body></html>"""
