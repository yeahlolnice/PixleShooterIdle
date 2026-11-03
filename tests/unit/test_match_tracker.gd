extends GutTest
## MatchTracker: kill cash from Economy/data, streaks, death penalty.

var _saved: Dictionary
var t: MatchTracker


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	t = MatchTracker.new()
	add_child_autofree(t)
	t.start_round(1)


func after_each() -> void:
	GameState.from_dict(_saved)


func _rules() -> Dictionary:
	return DataRegistry.economy()["kill_reward"]


func test_kill_credits_economy_cash() -> void:
	var r := _rules()
	var cash := t.record_kill(false)
	assert_eq(cash, Economy.cash_per_kill(r["base_cash"], false, 0, r))
	assert_eq(GameState.cash, cash)
	assert_eq(GameState.kills, 1)


func test_headshot_and_streak_bonus() -> void:
	var r := _rules()
	t.record_kill(false)
	var before := GameState.cash
	var paid := t.record_kill(true)
	assert_eq(paid, Economy.cash_per_kill(r["base_cash"], true, 1, r))
	assert_gt(paid, float(r["base_cash"]))
	assert_eq(GameState.cash, before + paid)


func test_scripted_sequence_and_death() -> void:
	t.record_kill(false)
	t.record_kill(true)
	t.record_kill(false)
	var cash := GameState.cash
	GameState.add_owned_gun("pistol_twin_zapper")
	GameState.equipped_gun_id = "pistol_twin_zapper"
	t.record_death()
	assert_eq(t.streak, 0)
	assert_eq(GameState.cash, cash, "death keeps cash")
	assert_eq(GameState.kills, 3, "death keeps kill totals")
	assert_eq(GameState.equipped_gun_id, DataRegistry.starter_gun_id())
	assert_false(GameState.owns_gun("pistol_twin_zapper"))
	t.record_kill(false)
	var s := t.end_round()
	assert_eq(s["kills"], 4)
	assert_eq(s["headshots"], 1)
	assert_eq(s["best_streak"], 3)
	assert_eq(s["deaths"], 1)
	assert_almost_eq(float(s["cash"]), GameState.cash, 0.001)


func test_bus_events_drive_tracker() -> void:
	EventBus.bot_killed.emit(null, {"headshot": true, "bot_type": "grunt"})
	assert_eq(t.kills, 1)
	assert_eq(t.headshots, 1)
	EventBus.player_died.emit({})
	assert_eq(t.streak, 0)


func test_time_only_counts_when_ticked() -> void:
	t.tick(2.5)
	assert_eq(t.end_round()["duration_s"], 2.5)
	t.tick(1.0)
	assert_eq(t.time_s, 2.5)
