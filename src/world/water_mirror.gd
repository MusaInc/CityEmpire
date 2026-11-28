class_name WaterMirror
extends Node
## Planar reflections for the sea, strait, rivers and marinas (reflection
## overhaul 2026-11-26): a second camera mirrored in the water plane renders
## the real scene – towers, bridges, boats, the sun's and moon's paths, lit
## windows and signs at night – into a small texture, and water.gdshader
## looks up each pixel by projecting its own world point with that camera
## (exact for any camera angle; the waves bend the lookup). Where the mirror
## has nothing (off screen, Low quality, web) the shader keeps its old sky +
## skyline reflection.
##
## Cost control: the mirror renders at a fraction of the screen (High 0.5,
## Medium 0.34 of its width), skips frames on Medium, uses a far clip and a
## coarse LOD, and doesn't render at all when no water is in view. The
## water itself, rain streaks and the seabed are left out (render layer
## LAYER, excluded from the mirror camera's cull mask).

const LAYER := 1 << 18          # render layer 19: things the mirror skips (20 is the hero light's)
const PLANE_Y := -1.6           # SkyportIsland.SEA_Y / CityWorld's water

var quality := 2
var on := false
## (Vector3) -> bool: is this point over water (CityLayout.is_water).
var water_fn := Callable()
var vp: SubViewport
var cam: Camera3D
var _frame := 0
var _env: Environment


func _ready() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings:
		quality = clampi(int(settings.quality), 0, 2)
	on = quality >= 1 and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mirror-dump="):
			_dump = a.get_slice("=", 1)
	RenderingServer.global_shader_parameter_set("mirror_on", 0.0)
	if not on:
		return
	vp = SubViewport.new()
	vp.name = "WaterMirrorView"
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.mesh_lod_threshold = 4.0 if quality >= 2 else 8.0
	vp.positional_shadow_atlas_size = 0
	# (The city's occluders assume an eye above the ground; the mirror's is
	# below the water.)
	vp.use_occlusion_culling = false
	vp.transparent_bg = false
	add_child(vp)
	cam = Camera3D.new()
	cam.cull_mask = 0xFFFFF & ~LAYER
	cam.near = 0.4
	cam.far = 4500.0 if quality >= 2 else 3800.0   # (the skyline across the strait is 1.5-2.5 km off)
	vp.add_child(cam)
	RenderingServer.global_shader_parameter_set("mirror_tex", vp.get_texture())
	RenderingServer.frame_pre_draw.connect(_pre_draw)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_pre_draw)


## Called after every script has moved its cameras, just before drawing.
func _pre_draw() -> void:
	if not on or not is_inside_tree():
		return
	var main := get_viewport().get_camera_3d()
	if main == null:
		RenderingServer.global_shader_parameter_set("mirror_on", 0.0)
		return
	_frame += 1
	var want := _water_in_view(main)
	if not want:
		RenderingServer.global_shader_parameter_set("mirror_on", 0.0)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# Size: a fraction of the screen, same shape.
	var scr := get_viewport().get_visible_rect().size
	var k := 0.5 if quality >= 2 else 0.34
	var w := clampi(int(scr.x * k), 160, 1024 if quality >= 2 else 640)
	var sz := Vector2i(w, maxi(90, int(w * scr.y / maxf(scr.x, 1.0))))
	var resized := vp.size != sz
	if resized:
		vp.size = sz
	# Medium: every other frame (always render on resize to avoid a black flash).
	if quality < 2 and _frame % 2 == 1 and not resized:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# The mirrored camera: position and axes reflected in y = PLANE_Y; the
	# x axis flipped back to keep a right-handed basis (the image comes out
	# mirrored, which the projection lookup in the shader accounts for).
	var t := main.global_transform
	var o := t.origin
	o.y = 2.0 * PLANE_Y - o.y
	var bx := t.basis.x * Vector3(1, -1, 1)
	var by := t.basis.y * Vector3(1, -1, 1)
	var bz := t.basis.z * Vector3(1, -1, 1)
	cam.global_transform = Transform3D(Basis(-bx, by, bz), o)
	cam.fov = main.fov
	cam.keep_aspect = main.keep_aspect
	# Its own copy of the world's environment (refreshed a few times a
	# second as the day and weather change), without the height fog: from
	# under the water the whole view lay inside the mist and the city
	# vanished from the reflection. Depth fog stays (distance haze).
	if _env == null or _frame % 12 == 0:
		var we: Environment = main.environment if main.environment else get_viewport().find_world_3d().environment
		if we:
			if _env == null:
				_env = we.duplicate()
				_env.fog_height_density = 0.0
				_env.volumetric_fog_enabled = false
				_env.ssao_enabled = false
				_env.ssil_enabled = false
				_env.sdfgi_enabled = false
			else:
				# Update persistent Environment in-place (zero per-second RID churn on iOS).
				_env.sky = we.sky
				_env.background_mode = we.background_mode
				_env.ambient_light_color = we.ambient_light_color
				_env.ambient_light_energy = we.ambient_light_energy
				_env.ambient_light_sky_contribution = we.ambient_light_sky_contribution
				_env.tonemap_exposure = we.tonemap_exposure
				_env.fog_enabled = we.fog_enabled
				_env.fog_light_color = we.fog_light_color
				_env.fog_light_energy = we.fog_light_energy
				_env.fog_density = we.fog_density
				_env.fog_depth_begin = we.fog_depth_begin
				_env.fog_depth_end = we.fog_depth_end
				_env.fog_aerial_perspective = we.fog_aerial_perspective
	cam.environment = _env
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var proj := cam.get_camera_projection()
	var view := Projection(cam.global_transform.affine_inverse())
	RenderingServer.global_shader_parameter_set("mirror_vp", proj * view)
	RenderingServer.global_shader_parameter_set("mirror_on", 1.0)
	if _dump != "" and _frame >= _dump_at:
		_dump_at = 1 << 30
		_dump_now.call_deferred()


# (Debug: --mirror-dump=<png> saves what the mirror saw ~5 s in.)
var _dump := ""
var _dump_at := 25


func _dump_now() -> void:
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(_dump)
	print("MIRROR dump ", _dump, " size ", vp.size, " seen ", _seen)


## Is any water likely on screen? The camera above the sea and the plane
## inside the view: rays through a few screen points meet it near enough.
func _water_in_view(c: Camera3D) -> bool:
	var cp := c.global_position
	if cp.y < PLANE_Y + 0.2:
		return false
	var r := get_viewport().get_visible_rect().size
	# (A 5 x 4 grid over the lower two thirds of the screen; checked a few
	# times a second, the answer held between.)
	if _frame % 6 != 0:
		return _seen
	_seen = false
	for gy in 4:
		for gx in 5:
			var d := c.project_ray_normal(r * Vector2(0.05 + 0.225 * gx, 0.4 + 0.19 * gy))
			if d.y >= -0.002:
				continue
			var hit_t := (PLANE_Y - cp.y) / d.y
			if hit_t > 3000.0:
				continue
			var hp := cp + d * hit_t
			if not water_fn.is_valid() or bool(water_fn.call(hp)):
				_seen = true
				return true
	return false


var _seen := false
