extends GutTest

const DataRegistryScript := preload("res://autoload/data_registry.gd")
const MALFORMED_DIR := "res://tests/fixtures/data_malformed"


func test_shipped_data_loads_without_errors() -> void:
	var result := DataRegistryScript.load_dir("res://data")
	assert_eq(result["errors"], PackedStringArray(), "data/ should validate cleanly")
	for stem in DataSchema.FILES:
		assert_true(result["data"].has(stem), "%s.json loaded" % stem)


func test_autoload_is_valid_and_getters_work() -> void:
	assert_true(DataRegistry.is_valid())
	assert_ne(DataRegistry.starter_gun_id(), "")
	assert_false(DataRegistry.gun(DataRegistry.starter_gun_id()).is_empty())
	assert_gte(DataRegistry.guns().size(), 3, "starter + 2 buyable pistols")
	assert_false(DataRegistry.bot("grunt").is_empty())
	assert_eq(DataRegistry.first_arena_id(), "arena_1")
	assert_true(DataRegistry.economy().has("kill_reward"))
	assert_true(DataRegistry.player().has("move_speed"))
	assert_eq(DataRegistry.gun("does_not_exist"), {})


func test_ints_and_vectors_are_normalised() -> void:
	var gun := DataRegistry.gun(DataRegistry.starter_gun_id())
	assert_eq(typeof(gun["mag_size"]), TYPE_INT)
	var arena := DataRegistry.arena("arena_1")
	assert_eq(typeof(arena["player_spawns"][0]), TYPE_VECTOR3)
	assert_eq(typeof(arena["blocks"][0]["size"]), TYPE_VECTOR3)


func test_palette_colors() -> void:
	assert_eq(DataRegistry.color("cash"), Color.html(DataRegistry.palette()["cash"]))


func test_malformed_fixture_is_rejected_with_file_and_key() -> void:
	var errors := PackedStringArray()
	var value: Variant = DataRegistryScript.load_file(MALFORMED_DIR + "/guns.json", DataSchema.FILES["guns"], errors)
	assert_null(value, "malformed file must not load")
	var joined := "\n".join(errors)
	assert_string_contains(joined, "guns.json")
	assert_string_contains(joined, "guns[1].damage: expected number")
	assert_string_contains(joined, "guns[0].mag_size: missing required key")
	assert_string_contains(joined, "guns[2].mag_size: expected integer")


func test_invalid_json_reports_file_and_line() -> void:
	var errors := PackedStringArray()
	var value: Variant = DataRegistryScript.load_file(MALFORMED_DIR + "/economy.json", DataSchema.FILES["economy"], errors)
	assert_null(value)
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "economy.json: invalid JSON at line")


func test_missing_files_are_reported() -> void:
	var result := DataRegistryScript.load_dir(MALFORMED_DIR)
	var joined := "\n".join(result["errors"])
	assert_string_contains(joined, "palette.json: file missing")


func test_cross_references_are_checked() -> void:
	var result := DataRegistryScript.load_dir("res://data")
	var data: Dictionary = result["data"].duplicate(true)
	data["guns"]["starter_gun"] = "nope"
	data["arenas"]["arenas"][0]["bot_types"] = ["ghost"]
	data["arenas"]["arenas"][0]["blocks"][0]["color"] = "not_a_colour"
	var errors := PackedStringArray()
	DataRegistryScript.cross_validate(data, errors)
	var joined := "\n".join(errors)
	assert_string_contains(joined, "starter_gun: 'nope'")
	assert_string_contains(joined, "bot_types: 'ghost'")
	assert_string_contains(joined, "blocks[0].color: 'not_a_colour'")


func test_bot_stats_apply_arena_multipliers() -> void:
	var bot_def := {"health": 100.0, "move_speed": 2.0, "fire_rate": 1.0, "damage": 5.0, "reaction_time_s": 1.0, "aim_error_deg": 10.0}
	var arena_def := {"bot_mults": {"health": 2.0, "move_speed": 1.5, "fire_rate": 1.0, "damage": 3.0, "reaction_time": 0.5, "aim_error": 0.25}}
	var stats := DataRegistryScript.resolve_bot_stats(bot_def, arena_def)
	assert_eq(stats["health"], 200.0)
	assert_eq(stats["move_speed"], 3.0)
	assert_eq(stats["damage"], 15.0)
	assert_eq(stats["reaction_time_s"], 0.5)
	assert_eq(stats["aim_error_deg"], 2.5)
