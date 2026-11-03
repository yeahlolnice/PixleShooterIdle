extends GutTest

const SteamServiceScript := preload("res://autoload/steam_service.gd")
const StubBackend := preload("res://autoload/steam_service_stub.gd")
const TEST_DIR := "user://test_steam_stub"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func after_each() -> void:
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(f))


func test_falls_back_to_stub_when_godotsteam_missing() -> void:
	assert_false(SteamServiceScript.godotsteam_present(), "test env has no GodotSteam")
	assert_eq(SteamServiceScript.select_backend(false).backend_name(), "stub")


func test_falls_back_to_stub_when_steam_present_but_no_backend_script() -> void:
	# Until Phase 5 adds steam_service_godotsteam.gd, even a Steam build uses the stub.
	if ResourceLoader.exists(SteamServiceScript.GODOTSTEAM_BACKEND_PATH):
		pending("GodotSteam backend exists; covered by its own tests")
		return
	assert_eq(SteamServiceScript.select_backend(true).backend_name(), "stub")


func test_autoload_selected_stub() -> void:
	assert_eq(SteamService.backend_name(), "stub")
	assert_false(SteamService.is_steam_running())


func test_stub_file_roundtrip_is_atomic() -> void:
	var stub := StubBackend.new(TEST_DIR)
	assert_false(stub.file_exists("save.json"))
	assert_eq(stub.load_file("save.json"), "")
	assert_true(stub.save_file("save.json", "{\"cash\": 5}"))
	assert_true(stub.file_exists("save.json"))
	assert_false(FileAccess.file_exists(TEST_DIR.path_join("save.json.tmp")), "temp file renamed away")
	assert_eq(stub.load_file("save.json"), "{\"cash\": 5}")
	assert_true(stub.save_file("save.json", "{\"cash\": 6}"))
	assert_eq(stub.load_file("save.json"), "{\"cash\": 6}")
	assert_true(stub.delete_file("save.json"))
	assert_false(stub.file_exists("save.json"))


func test_stub_records_achievements_and_stats() -> void:
	var stub := StubBackend.new(TEST_DIR)
	assert_true(stub.unlock_achievement("FIRST_KILL"))
	assert_true(stub.set_stat("kills", 3.0))
	assert_true(stub.achievements.has("FIRST_KILL"))
	assert_eq(stub.stats["kills"], 3.0)
