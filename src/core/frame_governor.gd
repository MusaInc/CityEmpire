class_name FrameGovernor
extends Node
## Dynamic resolution: holds the frame rate on slower or hot phones by easing
## the 3D render scale down, and back up to Settings' cap when there is
## headroom. The HUD is unaffected (it always draws at native resolution).
##
## Decisions use the GPU's measured render time when the driver reports it,
## else the real frame interval. Changes are rare (each one reallocates the
## render buffers) and in ~8% steps, so the picture never visibly "breathes".

const CHECK_EVERY := 0.5      # s between samples
const MIN_GAP := 2.0          # s between scale changes
const STEP := 0.92
const FLOOR_FRACTION := 0.62  # never below 62% of the cap…
const ABS_FLOOR := 0.42       # …or 42% of native

var enabled := true
var scale := 1.0
var _cap := 1.0
var _acc := 0.0
var _frames := 0
var _since_change := 0.0
var _headroom_time := 0.0
var _vp_rid: RID
var _last_us := 0
## Frame pacing (2026-11-27): when 60 can't be held even at the lowest
## render scale (an older or hot phone), a steady 30 beats a ragged 40–55;
## the lock lifts once the GPU shows clear headroom for a while.
var pacing_locked := false
var _behind_at_floor := 0.0
var _locked_roomy := 0.0
var _menu_capped := false
const LOCK_AFTER := 8.0
const UNLOCK_AFTER := 25.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport()
	_vp_rid = vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, enabled)
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.changed.connect(_reset)
	_reset()
	_last_us = Time.get_ticks_usec()


func _reset() -> void:
	var settings := get_node_or_null("/root/Settings")
	_cap = settings.render_scale_cap() if settings else get_viewport().scaling_3d_scale
	scale = _cap
	_since_change = 0.0
	_headroom_time = 0.0
	_acc = 0.0
	_frames = 0
	_last_us = Time.get_ticks_usec()
	pacing_locked = false
	_behind_at_floor = 0.0
	_locked_roomy = 0.0
	_menu_capped = false


## The frame-rate cap the player's settings ask for.
func _target_fps() -> int:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return 60
	return 60 if (settings.fps_60 or int(settings.preset()["fps"]) == 60) else 30


func _apply_fps() -> void:
	var want := _target_fps()
	if pacing_locked or _menu_capped:
		want = mini(want, 30)
	if Engine.max_fps != want:
		Engine.max_fps = want


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := (now - _last_us) / 1e6
	_last_us = now
	# Phone panels pause the world: 30 fps there saves battery and heat.
	var paused := get_tree().paused
	if paused != _menu_capped:
		_menu_capped = paused
		_apply_fps()
	if not enabled or paused or real_dt > 0.5:
		_acc = 0.0
		_frames = 0
		_headroom_time = 0.0
		return
	_acc += real_dt
	_frames += 1
	_since_change += real_dt
	if _acc < CHECK_EVERY:
		return
	var frame_ms := _acc * 1000.0 / _frames
	_acc = 0.0
	_frames = 0
	var budget := 1000.0 / maxf(Engine.max_fps if Engine.max_fps > 0 else 60, 1)
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	var gpu_known := gpu_ms > 0.05
	var floor_scale := maxf(_cap * FLOOR_FRACTION, ABS_FLOOR)
	var behind := frame_ms > budget * 1.18
	var gpu_bound := (not gpu_known) or gpu_ms > budget * 0.8
	# Pacing: behind at the floor scale for LOCK_AFTER s → a steady 30.
	if _target_fps() == 60:
		if not pacing_locked:
			_behind_at_floor = _behind_at_floor + CHECK_EVERY if behind and scale <= floor_scale + 0.001 else 0.0
			if _behind_at_floor >= LOCK_AFTER:
				pacing_locked = true
				_locked_roomy = 0.0
				_apply_fps()
				return
		else:
			# Unlock when the 30 fps frames would fit in a 60 fps budget with room.
			var fits := (gpu_known and gpu_ms < 1000.0 / 60.0 * 0.6) or (not gpu_known and frame_ms < 1000.0 / 60.0 * 0.9)
			_locked_roomy = _locked_roomy + CHECK_EVERY if fits else 0.0
			if _locked_roomy >= UNLOCK_AFTER:
				pacing_locked = false
				_behind_at_floor = 0.0
				_apply_fps()
				return
	if behind and gpu_bound:
		_headroom_time = 0.0
		if _since_change >= MIN_GAP and scale > floor_scale + 0.001:
			_set_scale(maxf(scale * STEP, floor_scale))
		return
	# Recover only with clear headroom, measured on the GPU (without a GPU
	# timer, a vsynced frame interval can't show headroom: probe slowly).
	var roomy := (gpu_known and gpu_ms < budget * 0.62) or (not gpu_known and not behind)
	_headroom_time = _headroom_time + CHECK_EVERY if roomy else 0.0
	var wait := 4.0 if gpu_known else 12.0
	if _headroom_time >= wait and scale < _cap - 0.001 and _since_change >= MIN_GAP:
		_headroom_time = 0.0
		_set_scale(minf(scale / STEP, _cap))


func _set_scale(v: float) -> void:
	scale = v
	_since_change = 0.0
	get_viewport().scaling_3d_scale = v
