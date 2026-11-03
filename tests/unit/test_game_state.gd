extends GutTest
## Phase 1 GameState: mutators and to_dict/from_dict shape. Save/load to disk is TASK-008.

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


func test_new_game_uses_starting_cash_from_data() -> void:
	assert_eq(GameState.cash, float(DataRegistry.economy()["starting_cash"]))
	assert_eq(GameState.kills, 0)


func test_cash_and_kills_emit_events() -> void:
	watch_signals(EventBus)
	GameState.add_cash(25.0)
	assert_signal_emitted_with_parameters(EventBus, "cash_changed", [GameState.cash, 25.0])
	assert_false(GameState.try_spend(GameState.cash + 1.0))
	assert_true(GameState.try_spend(5.0))
	assert_signal_emitted_with_parameters(EventBus, "cash_changed", [GameState.cash, -5.0])
	GameState.add_kill()
	assert_signal_emitted_with_parameters(EventBus, "kills_changed", [1, 1])


func test_clear_loadout_keeps_progress() -> void:
	GameState.add_cash(100.0)
	GameState.add_kill()
	GameState.add_owned_gun("pistol_hand_cannon")
	GameState.equipped_gun_id = "pistol_hand_cannon"
	GameState.clear_loadout()
	assert_eq(GameState.owned_guns.size(), 0)
	assert_eq(GameState.equipped_gun_id, "")
	assert_eq(GameState.kills, 1)
	assert_gt(GameState.cash, 0.0)


func test_dict_roundtrip() -> void:
	GameState.add_cash(42.0)
	GameState.add_kill()
	GameState.add_owned_gun("pistol_twin_zapper")
	GameState.cheat_levels["speed_hack"] = 3
	var d := GameState.to_dict()
	assert_eq(d["save_version"], GameState.SAVE_VERSION)
	GameState.new_game()
	GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(GameState.to_dict(), d)


func test_from_dict_tolerates_missing_keys() -> void:
	GameState.from_dict({"cash": 7})
	assert_eq(GameState.cash, 7.0)
	assert_eq(GameState.lifetime_kills, 0)
	assert_eq(GameState.owned_guns.size(), 0)
