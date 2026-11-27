class_name LoadPacer
extends RefCounted
## Keeps the splash animating while the world builds (2026-11-27).
##
## Building the city is ~15 s of work on the VPS CPU (a few seconds on a
## phone) and used to run in one go inside EmpireGame._ready: no frame was
## drawn meanwhile, so the splash froze on a dark screen. Now the build is a
## coroutine that hands a frame back whenever it has worked for budget_us,
## and node-free work (the city's layout) runs on a worker thread while
## frames keep coming. (Mesh merging can't: it reads and writes arrays
## through the RenderingServer, which a worker waits on frame by frame.)
##
## Off by default: tests, tools and captures build synchronously exactly as
## before (every helper here then runs inline and never suspends). The boot
## screen switches it on for the launch.

static var active := false


## Loading timings in the log (LOAD_T / LOAD_GAP / ENTER_T): --load-timing,
## and always on iOS for now (2026-11-27: a TestFlight build showed only navy
## on an iPad; the log in Files → WORLDSTATE → logs says where it stops).
static func timing() -> bool:
	return OS.get_cmdline_user_args().has("--load-timing") or OS.has_feature("ios")
## Main-thread work between two frames (µs). A phone waits for vsync
## (16.7 ms) on every frame handed back, so the budget fills most of one:
## 14 ms of building + the splash's ~1 ms frame keeps 60 fps and wastes
## little of the build's time (12 ms idled ~28 %).
static var budget_us := 14000
## 0..1: how far the build has got (the boot screen's hairline).
static var progress := 0.0
static var stage := ""
static var _since := 0


## Call often in long main-thread work: yields a frame once the budget is
## spent (never when inactive).
static func pace(tree: SceneTree) -> void:
	if not active:
		return
	if Time.get_ticks_usec() - _since < budget_us:
		return
	await tree.process_frame
	_since = Time.get_ticks_usec()


## A checkpoint: records progress (0..1) and paces.
static func step(tree: SceneTree, p: float) -> void:
	if not active:
		return
	progress = maxf(progress, clampf(p, 0.0, 1.0))
	await pace(tree)


## fn() on a worker thread while frames keep coming; returns its result.
## Inactive: called inline.
static func run(tree: SceneTree, fn: Callable) -> Variant:
	if not active:
		return fn.call()
	var out := [null]
	var tid := WorkerThreadPool.add_task(func(): out[0] = fn.call(), false, "load")
	while not WorkerThreadPool.is_task_completed(tid):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(tid)
	_since = Time.get_ticks_usec()
	return out[0]
