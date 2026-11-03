extends RefCounted
## Interface every SteamService backend implements. The default bodies are a
## no-Steam implementation, so a backend only overrides what it supports.
## Backends: steam_service_stub.gd (always), steam_service_godotsteam.gd (Phase 5).


## Short id used in logs and tests: "stub" or "godotsteam".
func backend_name() -> String:
	return "base"


## Called once by SteamService._ready(). Returns false if init failed.
func initialize() -> bool:
	return true


## Called every frame by SteamService (GodotSteam needs run_callbacks()).
func poll() -> void:
	pass


func is_steam_running() -> bool:
	return false


func get_player_name() -> String:
	return "Player"


## Returns true if the achievement was set (or already set).
func unlock_achievement(_achievement_id: String) -> bool:
	return false


func set_stat(_stat_name: String, _value: float) -> bool:
	return false


## Writes a whole file (save games). Steam backend uses Steam Cloud.
func save_file(_file_name: String, _text: String) -> bool:
	return false


## Returns the file text, or "" if missing/unreadable (check file_exists first).
func load_file(_file_name: String) -> String:
	return ""


func file_exists(_file_name: String) -> bool:
	return false


func delete_file(_file_name: String) -> bool:
	return false
