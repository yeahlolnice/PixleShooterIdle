extends GutTest
## RoundController transitions with injected time.

var rc: RoundController
var tracker: MatchTracker
var _round: Dictionary


func before_each() -> void:
	GameState.new_game()
	tracker = MatchTracker.new()
	add_child_autofree(tracker)
	rc = RoundController.new()
	rc.tracker = tracker
	add_child_autofree(rc)
	rc.set_process(false)
	_round = DataRegistry.economy()["round"]


func test_cycle_uses_data_durations() -> void:
	watch_signals(EventBus)
	rc.start()
	assert_eq(rc.state, EventBus.ROUND_FREEZE)
	assert_eq(rc.time_left, float(_round["freeze_time_s"]))
	rc.advance(float(_round["freeze_time_s"]) - 0.1)
	assert_eq(rc.state, EventBus.ROUND_FREEZE)
	rc.advance(0.2)
	assert_eq(rc.state, EventBus.ROUND_LIVE)
	assert_eq(rc.time_left, float(_round["live_time_s"]))
	rc.advance(float(_round["live_time_s"]) + 0.1)
	assert_eq(rc.state, EventBus.ROUND_SUMMARY)
	assert_signal_emitted(EventBus, "round_summary")
	rc.advance(float(_round["summary_time_s"]) + 0.1)
	assert_eq(rc.state, EventBus.ROUND_FREEZE)
	assert_eq(rc.round_number, 2)
	assert_signal_emit_count(EventBus, "round_state_changed", 4)


func test_wave_spawns_on_live_and_respawns_when_cleared() -> void:
	watch_signals(rc)
	rc.start()
	rc.advance(float(_round["freeze_time_s"]) + 0.1)
	assert_signal_emit_count(rc, "spawn_wave_requested", 1)
	var n := rc.bots_alive
	assert_gt(n, 0)
	for i in range(n):
		EventBus.bot_killed.emit(null, {})
	assert_signal_emit_count(rc, "spawn_wave_requested", 2)


func test_server_slots_bought_after_start_grow_next_wave() -> void:
	rc.start()
	var base := int(DataRegistry.arena(rc.arena_id)["bots_per_wave"])
	GameState.server_slots = 3  # bought during freeze, after start()
	rc.advance(float(_round["freeze_time_s"]) + 0.1)
	assert_gt(CheatSystem.extra_bots(), 0)
	assert_eq(rc.bots_alive, base + CheatSystem.extra_bots())


func test_death_requests_respawn_after_delay() -> void:
	watch_signals(rc)
	rc.start()
	EventBus.player_died.emit({})
	rc.advance(float(DataRegistry.player()["respawn_delay_s"]) + 0.1)
	assert_signal_emitted(rc, "respawn_requested")
