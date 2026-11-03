extends Node
## Facade over Steam. Gameplay code only talks to this autoload, never to the
## GodotSteam "Steam" singleton, so the game runs with Steam absent.
##
## Backend selection (once, in _ready):
##   GodotSteam singleton present AND autoload/steam_service_godotsteam.gd exists -> that backend
##   otherwise -> autoload/steam_service_stub.gd
## The choice is logged exactly once: "[SteamService] backend: stub (GodotSteam not found)".

const StubBackend := preload("res://autoload/steam_service_stub.gd")
const GODOTSTEAM_SINGLETON := "Steam"
const GODOTSTEAM_BACKEND_PATH := "res://autoload/steam_service_godotsteam.gd"

var _backend: RefCounted = null


func _ready() -> void:
	var present := godotsteam_present()
	_backend = select_backend(present)
	if not _backend.initialize():
		push_warning("[SteamService] %s backend failed to initialise; using stub" % _backend.backend_name())
		_backend = StubBackend.new()
	print("[SteamService] backend: %s (GodotSteam %s)" % [_backend.backend_name(), "found" if present else "not found"])


func _process(_delta: float) -> void:
	if _backend != null:
		_backend.poll()


## True when the GodotSteam extension is loaded in this build.
static func godotsteam_present() -> bool:
	return Engine.has_singleton(GODOTSTEAM_SINGLETON) or ClassDB.class_exists(GODOTSTEAM_SINGLETON)


## Picks the backend. Pure apart from loading the backend script; unit-tested.
static func select_backend(steam_present: bool) -> RefCounted:
	if steam_present and ResourceLoader.exists(GODOTSTEAM_BACKEND_PATH):
		return load(GODOTSTEAM_BACKEND_PATH).new()
	return StubBackend.new()


## Replaces the backend (tests only).
func set_backend(backend: RefCounted) -> void:
	_backend = backend


# --- Public API (delegates to the backend) --------------------------------------

func backend_name() -> String:
	return _backend.backend_name()


func is_steam_running() -> bool:
	return _backend.is_steam_running()


func get_player_name() -> String:
	return _backend.get_player_name()


func unlock_achievement(achievement_id: String) -> bool:
	return _backend.unlock_achievement(achievement_id)


func set_stat(stat_name: String, value: float) -> bool:
	return _backend.set_stat(stat_name, value)


## Whole-file save (Steam Cloud when available, user:// otherwise). Atomic in the stub.
func save_file(file_name: String, text: String) -> bool:
	return _backend.save_file(file_name, text)


## File text, or "" if the file does not exist.
func load_file(file_name: String) -> String:
	return _backend.load_file(file_name)


func file_exists(file_name: String) -> bool:
	return _backend.file_exists(file_name)


func delete_file(file_name: String) -> bool:
	return _backend.delete_file(file_name)
