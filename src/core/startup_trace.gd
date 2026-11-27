class_name StartupTrace
extends RefCounted
## Release-visible breadcrumbs. Keep each line on disk even if startup stalls.

static var _file: FileAccess
static var _enabled := OS.has_feature("ios") or OS.get_cmdline_user_args().has("--load-timing")


static func begin() -> void:
	if not OS.has_feature("ios"):
		return
	const LOG := "user://logs/startup.log"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG.get_base_dir()))
	if FileAccess.file_exists(LOG):
		DirAccess.copy_absolute(LOG, "user://logs/startup.previous.log")
	_file = FileAccess.open(LOG, FileAccess.WRITE)


static func mark(stage: String) -> void:
	if not _enabled:
		return
	var engine_mb := "%.1f" % (OS.get_static_memory_usage() / 1048576.0) if OS.is_debug_build() else "unavailable"
	var line := "STARTUP wall=%.3f t=%dms %s | render=%.1f MiB tracked=%s MiB nodes=%d" % [
		Time.get_unix_time_from_system(), Time.get_ticks_msec(), stage,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		engine_mb, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
	print(line)
	if _file:
		_file.store_line(line)
		_file.flush()
