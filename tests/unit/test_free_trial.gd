extends GutTest
## Free trial (fun pack, D64): temporary cheat levels without ownership, expiry,
## the once-per-save round-1 trigger, and the HUD countdown.

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	CheatSystem.set_player(null)


func after_each() -> void:
	CheatSystem.tick_trials(10000.0)   # no trial leaks into other tests
	GameState.from_dict(_saved)
	CheatSystem.refresh_unlocks(false)


func test_trial_runs_a_cheat_without_owning_it() -> void:
	var cost := CheatSystem.next_cost("aimbot")
	CheatSystem.start_trial({"aimbot": 10}, 30.0)
	assert_true(CheatSystem.is_enabled("aimbot"))
	assert_eq(CheatSystem.effective_level("aimbot"), 10)
	assert_eq(CheatSystem.level("aimbot"), 0, "not owned")
	assert_almost_eq(float(CheatSystem.effect("aimbot", "fov_deg")), float(CheatSystem.get_cheat("aimbot").value_at("fov_deg", 10)), 0.0001)
	assert_eq(CheatSystem.next_cost("aimbot"), cost, "buying is priced as if no trial")
	assert_eq(GameState.cheat_levels.get("aimbot", 0), 0, "nothing saved")


func test_trial_expires_back_to_the_owned_state() -> void:
	watch_signals(EventBus)
	CheatSystem.start_trial({"aimbot": 10}, 30.0)
	assert_signal_emitted_with_parameters(EventBus, "cheat_toggled", ["aimbot", true])
	CheatSystem.tick_trials(29.0)
	assert_true(CheatSystem.is_enabled("aimbot"))
	assert_almost_eq(CheatSystem.trial_left("aimbot"), 1.0, 0.001)
	CheatSystem.tick_trials(2.0)
	assert_false(CheatSystem.is_enabled("aimbot"))
	assert_eq(CheatSystem.effective_level("aimbot"), 0)
	assert_signal_emitted_with_parameters(EventBus, "cheat_toggled", ["aimbot", false])
	assert_signal_emitted_with_parameters(EventBus, "chat_event", [&"free_trial_end", {}])


func test_owned_level_wins_over_a_lower_trial() -> void:
	GameState.cheat_levels["wallhack"] = 8
	GameState.cheat_enabled["wallhack"] = true
	CheatSystem.start_trial({"wallhack": 3}, 10.0)
	assert_eq(CheatSystem.effective_level("wallhack"), 8)
	CheatSystem.tick_trials(20.0)
	assert_true(CheatSystem.is_enabled("wallhack"), "still owned after the trial")


func test_round_one_starts_the_data_trial_once_per_save() -> void:
	var rules: Dictionary = DataRegistry.economy()["free_trial"]
	EventBus.round_state_changed.emit(EventBus.ROUND_LIVE, {"round": int(rules["round"]) + 1})
	for id in rules["cheats"]:
		assert_false(CheatSystem.is_enabled(id), "not on other rounds")
	EventBus.round_state_changed.emit(EventBus.ROUND_LIVE, {"round": int(rules["round"])})
	for id in rules["cheats"]:
		assert_eq(CheatSystem.effective_level(id), int(rules["cheats"][id]), id)
		assert_almost_eq(CheatSystem.trial_left(id), float(rules["seconds"]), 0.001)
	assert_true(GameState.chat_flags.get(CheatSystem.FREE_TRIAL_FLAG, false), "remembered in the save")
	CheatSystem.tick_trials(5.0)
	EventBus.round_state_changed.emit(EventBus.ROUND_LIVE, {"round": int(rules["round"])})
	for id in rules["cheats"]:
		assert_almost_eq(CheatSystem.trial_left(id), float(rules["seconds"]) - 5.0, 0.001, "not restarted")


func test_strip_shows_the_trial_countdown() -> void:
	var strip: CheatStrip = add_child_autofree(CheatStrip.new())
	CheatSystem.start_trial({"aimbot": 10}, 12.0)
	strip._process(0.0)
	assert_eq(strip.shown_ids(), ["aimbot"])
	assert_string_contains(strip.text_for("aimbot"), "L10")
	assert_string_contains(strip.text_for("aimbot"), "TRIAL 12s")
