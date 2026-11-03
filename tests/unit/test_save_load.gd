extends GutTest
## TASK-008: GameState save/load through SaveService and the SteamService stub.
## Uses a stub backend rooted in a temp directory, never the real user://save.json.

const StubBackend := preload("res://autoload/steam_service_stub.gd")
const TEST_DIR := "user://test_save_load"

var _saved: Dictionary
var _stub: RefCounted
var _saves: SaveService


func before_each() -> void:
	_saved = GameState.to_dict()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_clear_dir()
	_stub = StubBackend.new(TEST_DIR)
	_saves = SaveService.new(_stub)
	GameState.new_game()


func after_each() -> void:
	GameState.disable_persistence()
	_clear_dir()
	GameState.from_dict(_saved)


func _clear_dir() -> void:
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(f))


func _fill_state() -> void:
	GameState.add_cash(1234.5678901234567)
	for i in 7:
		GameState.add_kill()
	GameState.lifetime_kills = 99
	GameState.add_owned_gun("pistol_hand_cannon")
	GameState.add_owned_gun("pistol_twin_zapper")
	GameState.equipped_gun_id = "pistol_hand_cannon"
	GameState.cheat_levels = {"speed_hack": 3, "infinite_ammo": 1}
	GameState.cheat_enabled = {"speed_hack": true, "infinite_ammo": false}
	GameState.server_slots = 2
	GameState.prestige_count = 3
	GameState.hax_points = 42
	GameState.rootkit = {"head_start": 2}
	GameState.chat_flags = {"first_cash": true}


func test_roundtrip_restores_identical_state_including_prestige() -> void:
	_fill_state()
	var before := GameState.to_dict()
	assert_true(_saves.save(GameState))
	assert_true(_stub.file_exists(SaveService.DEFAULT_FILE))
	GameState.new_game()
	assert_ne(GameState.to_dict(), before, "state was reset before loading")
	assert_eq(_saves.load_into(GameState), SaveService.LoadResult.LOADED)
	assert_eq(GameState.to_dict(), before)
	assert_eq(GameState.cash, 1234.5678901234567, "full float precision survives JSON")
	assert_eq(GameState.prestige_count, 3)
	assert_eq(GameState.hax_points, 42)
	assert_eq(GameState.rootkit, {"head_start": 2})
	assert_typeof(GameState.cheat_levels["speed_hack"], TYPE_INT)


func test_save_is_written_atomically_without_leftover_temp_file() -> void:
	_fill_state()
	assert_true(_saves.save(GameState))
	assert_false(FileAccess.file_exists(TEST_DIR.path_join("save.json.tmp")))
	var parsed: Variant = JSON.parse_string(_stub.load_file("save.json"))
	assert_eq(int(parsed["save_version"]), GameState.SAVE_VERSION)


func test_missing_file_starts_fresh() -> void:
	assert_eq(GameState.enable_persistence(_stub), SaveService.LoadResult.MISSING)
	assert_eq(GameState.cash, float(DataRegistry.economy()["starting_cash"]))
	assert_eq(GameState.kills, 0)


func test_corrupt_file_is_backed_up_and_game_starts_fresh() -> void:
	var garbage := "{\"cash\": 50, \"kills\": [oops"
	_stub.save_file("save.json", garbage)
	GameState.add_cash(500.0)
	assert_eq(GameState.enable_persistence(_stub), SaveService.LoadResult.CORRUPT)
	assert_eq(GameState.cash, float(DataRegistry.economy()["starting_cash"]), "fresh state, not the old in-memory one")
	assert_false(_stub.file_exists("save.json"), "corrupt file removed")
	assert_eq(_stub.load_file("save.corrupt.json"), garbage, "corrupt file backed up verbatim")
	assert_true(GameState.save_game(), "fresh game can be saved again")


func test_non_object_and_empty_files_count_as_corrupt() -> void:
	for text in ["", "[1, 2, 3]", "42"]:
		_stub.save_file("save.json", text)
		assert_eq(_saves.load_into(GameState), SaveService.LoadResult.CORRUPT, "text %s" % text)


func test_wrong_field_types_fall_back_to_defaults() -> void:
	_stub.save_file("save.json", JSON.stringify({
		"save_version": 1, "cash": "lots", "kills": 4, "owned_guns": 5,
		"cheat_levels": {"speed_hack": "x", "wallhack": 2}, "rootkit": [], "cheat_enabled": {"a": 1},
	}))
	assert_eq(_saves.load_into(GameState), SaveService.LoadResult.LOADED)
	assert_eq(GameState.cash, 0.0)
	assert_eq(GameState.kills, 4)
	assert_eq(GameState.owned_guns.size(), 0)
	assert_eq(GameState.cheat_levels, {"wallhack": 2})
	assert_eq(GameState.rootkit, {})
	assert_eq(GameState.cheat_enabled, {})


func test_unversioned_save_passes_through_migration() -> void:
	_stub.save_file("save.json", JSON.stringify({"cash": 12, "prestige_count": 1}))
	assert_eq(_saves.load_into(GameState), SaveService.LoadResult.LOADED)
	assert_eq(GameState.cash, 12.0)
	assert_eq(GameState.prestige_count, 1)
	assert_eq(GameState.to_dict()["save_version"], GameState.SAVE_VERSION)


func test_migration_hook_runs_each_step_in_order() -> void:
	# Simulate a future SAVE_VERSION 3 with steps 1->2 (rename) and 2->3 (new field).
	var calls: Array = []
	var steps := {
		1: func(d: Dictionary) -> Dictionary:
			calls.append(1)
			d["hax_points"] = d.get("haxpoints", 0)
			d.erase("haxpoints")
			return d,
		2: func(d: Dictionary) -> Dictionary:
			calls.append(2)
			d["new_field"] = "default"
			return d,
	}
	var out := GameState.migrate({"save_version": 1, "haxpoints": 9}, 3, steps)
	assert_eq(calls, [1, 2])
	assert_eq(out["save_version"], 3)
	assert_eq(out["hax_points"], 9)
	assert_false(out.has("haxpoints"))
	assert_eq(out["new_field"], "default")


func test_current_version_skips_migration_steps() -> void:
	var called := [false]
	var steps := {GameState.SAVE_VERSION: func(d: Dictionary) -> Dictionary:
		called[0] = true
		return d}
	GameState.migrate({"save_version": GameState.SAVE_VERSION}, GameState.SAVE_VERSION, steps)
	assert_false(called[0])


func test_newer_save_version_loads_known_fields() -> void:
	var out := GameState.migrate({"save_version": GameState.SAVE_VERSION + 5, "cash": 3})
	assert_eq(out["save_version"], GameState.SAVE_VERSION)
	assert_eq(out["cash"], 3)


func test_autosaves_at_round_end() -> void:
	GameState.enable_persistence(_stub)
	GameState.add_cash(77.0)
	EventBus.round_summary.emit({"round": 1})
	var parsed: Variant = JSON.parse_string(_stub.load_file("save.json"))
	assert_eq(float(parsed["cash"]), GameState.cash)


func test_autosaves_on_quit_request() -> void:
	GameState.enable_persistence(_stub)
	GameState.add_kill()
	GameState.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	var parsed: Variant = JSON.parse_string(_stub.load_file("save.json"))
	assert_eq(int(parsed["kills"]), 1)


func test_no_autosave_without_persistence() -> void:
	EventBus.round_summary.emit({"round": 1})
	assert_false(_stub.file_exists("save.json"))
	assert_false(GameState.save_game())


func test_load_game_emits_loaded_signal() -> void:
	watch_signals(EventBus)
	GameState.enable_persistence(_stub)
	assert_signal_emitted(EventBus, "game_state_loaded")
