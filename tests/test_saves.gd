extends RefCounted
## SafeSave (shared persistence envelope) + WORLDSTATE's save schema (SH-03, WS-07).

const P := "user://test_safesave.json"


func _clean() -> void:
	for s in ["", ".bak", ".bak2", ".bak3", ".tmp", ".broken"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(P + s))


func _raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _good(day := 3) -> Dictionary:
	return {"empire": {"day": day, "minute": 600.0, "personal_cash": 650.0, "company_cash": 0.0,
		"businesses": [], "vehicles": [{"id": "v1"}], "flags": {}}, "player": [0, 1, 0, 0]}


func test_round_trip_and_backup(t) -> void:
	_clean()
	t.check(SafeSave.write(P, _good(3)) == "", "first save written")
	t.check(SafeSave.write(P, _good(4)) == "", "second save written")
	var d = SafeSave.read(P, EmpireGame.save_problem)
	t.check(d is Dictionary and int(d["empire"]["day"]) == 4 and SafeSave.last_source == "primary", "reads the newest save")
	var b = JSON.parse_string(FileAccess.get_file_as_string(P + ".bak"))
	t.check(b is Dictionary and int(b["empire"]["day"]) == 3, "the previous save is the backup")
	t.check(not FileAccess.file_exists(P + ".tmp"), "no temp file left behind")
	_clean()


func test_truncated_primary_falls_back_to_backup(t) -> void:
	_clean()
	SafeSave.write(P, _good(3))
	SafeSave.write(P, _good(4))
	_raw(P, JSON.stringify(_good(5)).left(40))  # cut off mid-write
	var d = SafeSave.read(P, EmpireGame.save_problem)
	t.check(d is Dictionary and int(d["empire"]["day"]) == 3 and SafeSave.last_source == "backup", "truncated save -> backup")
	_clean()


func test_wrong_types_are_rejected(t) -> void:
	_clean()
	SafeSave.write(P, _good(3))
	SafeSave.write(P, _good(4))
	var bad := _good(9)
	bad["empire"]["personal_cash"] = "lots"
	bad["empire"]["businesses"] = 7
	_raw(P, JSON.stringify(bad))
	var d = SafeSave.read(P, EmpireGame.save_problem)
	t.check(d is Dictionary and int(d["empire"]["day"]) == 3, "valid JSON with wrong types -> backup (%s)" % SafeSave.last_source)
	t.check(EmpireGame.save_problem(bad) != "", "schema check names a problem: %s" % EmpireGame.save_problem(bad))
	t.check(EmpireGame.save_problem({"empire": {}}) != "", "empty economy rejected")
	t.check(EmpireGame.save_problem(_good()) == "", "a real-shaped save passes")
	t.check(EmpireGame.save_problem({"empire": {"day": 1, "personal_cash": 650}}) == "", "an older save without newer fields still loads")
	_clean()


func test_corrupt_primary_never_replaces_good_backup(t) -> void:
	_clean()
	SafeSave.write(P, _good(3))
	SafeSave.write(P, _good(4))          # .bak = day 3
	_raw(P, "{not json")                  # primary corrupted on disk
	t.check(SafeSave.write(P, _good(5)) == "", "next save still succeeds")
	var b = JSON.parse_string(FileAccess.get_file_as_string(P + ".bak"))
	t.check(b is Dictionary and int(b["empire"]["day"]) == 3, "corrupt file was not promoted to backup")
	_clean()


func test_nothing_usable_reports_why(t) -> void:
	_clean()
	_raw(P, "garbage")
	_raw(P + ".bak", "[]")
	var d = SafeSave.read(P, EmpireGame.save_problem)
	t.check(d == null and SafeSave.last_error.contains("not valid JSON"), "both unusable -> null with a reason (%s)" % SafeSave.last_error)
	_clean()


func test_unwritable_location_reports_failure(t) -> void:
	var err := SafeSave.write("user://no_such_dir/deeper/save.json", _good())
	t.check(err != "", "a failed write is reported, not claimed (%s)" % err)


func test_old_app_folder_is_copied_not_moved(t) -> void:
	var cur := OS.get_user_data_dir()
	var old := cur.get_base_dir().path_join("SafeSaveOldName")
	DirAccess.make_dir_recursive_absolute(old)
	_raw(old.path_join("ss_migrate.json"), JSON.stringify(_good(7)))
	DirAccess.remove_absolute(cur.path_join("ss_migrate.json"))
	var n := SafeSave.migrate_dir(["SafeSaveOldName"], ["ss_migrate.json"])
	t.check(n == 1 and FileAccess.file_exists(cur.path_join("ss_migrate.json")), "old save copied into the new folder")
	t.check(FileAccess.file_exists(old.path_join("ss_migrate.json")), "old copy left in place")
	_raw(cur.path_join("ss_migrate.json"), JSON.stringify(_good(8)))
	t.check(SafeSave.migrate_dir(["SafeSaveOldName"], ["ss_migrate.json"]) == 0, "never overwrites a newer save")
	DirAccess.remove_absolute(cur.path_join("ss_migrate.json"))
	DirAccess.remove_absolute(old.path_join("ss_migrate.json"))
	DirAccess.remove_absolute(old)


## Older backups (2026-11-26): a good .bak steps down to .bak2, and a load
## with the primary and .bak both unusable still finds the older one.
func test_backup_history_rotates_and_rescues(t) -> void:
	_clean()
	t.check(SafeSave.write(P, _good()) == "" and SafeSave.write(P, _good()) == "", "two saves written")
	t.check(FileAccess.file_exists(P + ".bak2"), "the backup stepped down to .bak2")
	_raw(P, "garbage")
	_raw(P + ".bak", "[]")
	var d = SafeSave.read(P, EmpireGame.save_problem)
	t.check(d is Dictionary and SafeSave.last_source == "backup", "loaded the older backup when both newer ones were broken")
	_clean()
