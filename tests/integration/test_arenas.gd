extends GutTest
## Arena progression (TASK-026): Rooftop data, unlock by lifetime kills,
## selection saved and announced, and Main rebuilding the world on switch.

const ArenaScene := preload("res://shooter/arenas/arena.tscn")

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	GameState.chat_flags[CheatSystem.FREE_TRIAL_FLAG] = true   # no round-1 trial cheats in this test


func after_each() -> void:
	GameState.from_dict(_saved)


func _second() -> Dictionary:
	return DataRegistry.arenas()[1]


func test_rooftop_is_harder_richer_and_brings_new_bots() -> void:
	var first: Dictionary = DataRegistry.arenas()[0]
	var second := _second()
	assert_eq(int(first.get("unlock_kills", 0)), 0, "first arena is open from the start")
	assert_gt(int(second["unlock_kills"]), 0)
	assert_almost_eq(float(second["cash_mult"]), float(first["cash_mult"]) * 10.0, 0.001, "plan: x10 cash per arena")
	assert_true(second["bot_types"].has("sniper"))
	assert_true(second["bot_types"].has("rusher"))
	assert_gt(float(second["bot_mults"]["health"]), float(first["bot_mults"]["health"]))


func test_rooftop_builds_with_navmesh() -> void:
	var arena: Node3D = add_child_autofree(ArenaScene.instantiate())
	arena.build(_second())
	assert_eq(arena.block_count(), _second()["blocks"].size())
	assert_gt(arena.nav_polygon_count(), 0)


func test_unlock_select_and_fallback() -> void:
	var id: String = _second()["id"]
	assert_false(ArenaService.is_unlocked(id))
	assert_false(ArenaService.select(id), "locked")
	GameState.lifetime_kills = ArenaService.unlock_kills(id)
	assert_eq(ArenaService.unlocked_at(GameState.lifetime_kills), [id])
	watch_signals(EventBus)
	assert_true(ArenaService.select(id))
	assert_signal_emitted_with_parameters(EventBus, "arena_selected", [id])
	assert_eq(GameState.current_arena_id, id, "saved")
	assert_eq(ArenaService.selected_id(), id)
	assert_false(ArenaService.select(id), "already there")
	GameState.lifetime_kills = 0
	assert_eq(ArenaService.selected_id(), DataRegistry.first_arena_id(), "locked pick falls back")


func test_main_switches_arena_and_cash_scales() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.use_save_file = false
	add_child_autofree(main)
	await wait_physics_frames(3)
	var first_id := DataRegistry.first_arena_id()
	var base_cash: float = main.tracker.kill_value(false, "grunt")
	var id: String = _second()["id"]
	GameState.lifetime_kills = ArenaService.unlock_kills(id)
	ArenaService.select(id)
	await wait_physics_frames(3)
	assert_eq(main.arena.arena_id, id, "world rebuilt")
	assert_eq(main.rounds.arena_id, id, "rounds restarted there")
	assert_eq(main.rounds.state, EventBus.ROUND_FREEZE, "back to buy time")
	var spawn: Vector3 = main.arena.player_spawns[0]
	assert_almost_eq(main.player.global_position.z, spawn.z, 0.5, "player moved to the new spawn")
	var ratio: float = main.tracker.kill_value(false, "grunt") / base_cash
	assert_almost_eq(ratio, float(_second()["cash_mult"]) / float(DataRegistry.arena(first_id)["cash_mult"]), 0.001)
