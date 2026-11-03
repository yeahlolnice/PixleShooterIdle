extends "res://autoload/steam_backend.gd"
## Backend used whenever GodotSteam is not present (development, tests, web,
## DRM-free builds). Files go to user:// (or `root_dir` for tests); achievements
## and stats are remembered in memory only so callers can be tested.

var root_dir := "user://"
var achievements := {}
var stats := {}


func _init(dir: String = "user://") -> void:
	root_dir = dir


func backend_name() -> String:
	return "stub"


func get_player_name() -> String:
	return "Player"


func unlock_achievement(achievement_id: String) -> bool:
	achievements[achievement_id] = true
	return true


func set_stat(stat_name: String, value: float) -> bool:
	stats[stat_name] = value
	return true


## Atomic write: temp file, then rename over the target.
func save_file(file_name: String, text: String) -> bool:
	var path := _path(file_name)
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[SteamService/stub] cannot write %s: %s" % [tmp_path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("[SteamService/stub] cannot rename %s -> %s: %s" % [tmp_path, path, error_string(err)])
		return false
	return true


func load_file(file_name: String) -> String:
	var path := _path(file_name)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func file_exists(file_name: String) -> bool:
	return FileAccess.file_exists(_path(file_name))


func delete_file(file_name: String) -> bool:
	if not file_exists(file_name):
		return false
	return DirAccess.remove_absolute(_path(file_name)) == OK


func _path(file_name: String) -> String:
	return root_dir.path_join(file_name)
