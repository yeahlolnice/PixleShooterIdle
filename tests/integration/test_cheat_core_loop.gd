extends GutTest
## TASK-014 cheat-core loop: kills -> Speed Hack unlock -> buy via CheatSystem ->
## effect on the player -> save -> reload -> still owned/enabled, tutorial chat
## does not repeat. Also mod-menu time scale restore and first-cheat pacing.
## Saves go to a temp dir, never the real user://save.json.

const StubBackend := preload("res://autoload/steam_service_stub.gd")
const TEST_DIR := "user://test_cheat_core_loop"

var main: Node3D
var _saved_state: Dictionary
var _saved_scale := 1.0
var _saves: SaveService


func before_each() -> void:
	_saved_state = GameState.to_dict()
	_saved_scale = Engine.time_scale
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_clear_dir()
	_saves = SaveService.new(StubBackend.new(TEST_DIR))
	GameState.new_game()
	ChatSystem.configure(DataRegistry.chat())  # drop fixtures/queued lines from other tests
	ChatSystem.muted_channels = {}
	ChatSystem.history.clear()
	main = add_child_autofree(_make_main())
	await wait_physics_frames(3)


func after_each() -> void:
	Engine.time_scale = _saved_scale
	_clear_dir()
	GameState.from_dict(_saved_state)
	CheatSystem.refresh_unlocks(false)


func _make_main() -> Node3D:
	var m: Node3D = load("res://scenes/main.tscn").instantiate()
	m.use_save_file = false
	return m


func _clear_dir() -> void:
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(f))


func _kill(n: int) -> void:
	for i in n:
		main.tracker.record_kill(false, "grunt")


func _chat_texts() -> Array:
	return ChatSystem.history.map(func(l): return l["text"])


func _count_lines(fragment: String) -> int:
	return _chat_texts().filter(func(t): return String(t).contains(fragment)).size()


func test_unlock_buy_effect_save_reload() -> void:
	var player: Player = main.player
	var base_speed := player.effective(&"move_speed")
	var sh_cost := CheatSystem.next_cost("speed_hack")

	# Locked until 10 kills, even with cash.
	GameState.add_cash(sh_cost)
	_kill(9)
	GameState.cash = maxf(GameState.cash, sh_cost)
	assert_false(CheatSystem.is_unlocked("speed_hack"), "locked at 9 kills")
	assert_false(CheatSystem.purchase("speed_hack"))
	_kill(1)
	assert_eq(GameState.lifetime_kills, 10)
	assert_true(CheatSystem.is_unlocked("speed_hack"), "unlocked at 10 kills")

	# Buy (earned cash from 10 kills is already enough; top up to be deterministic).
	GameState.cash = maxf(GameState.cash, sh_cost)
	var cash_before := GameState.cash
	assert_true(CheatSystem.purchase("speed_hack"))
	assert_almost_eq(cash_before - GameState.cash, sh_cost, 0.001)
	assert_eq(CheatSystem.level("speed_hack"), 1)
	assert_true(CheatSystem.is_enabled("speed_hack"))
	var boosted := player.effective(&"move_speed")
	assert_gt(boosted, base_speed, "Speed Hack raises move speed")
	var expected_mult := float(CheatSystem.get_cheat("speed_hack").value_at("move_speed_mult", 1))
	assert_almost_eq(boosted, base_speed * expected_mult, 0.001)

	# Toggle off restores exactly; back on re-applies.
	CheatSystem.toggle("speed_hack")
	assert_almost_eq(player.effective(&"move_speed"), base_speed, 0.0001)
	CheatSystem.toggle("speed_hack")
	assert_almost_eq(player.effective(&"move_speed"), boosted, 0.0001)

	# Tutorial chat has played once; flush queued lines.
	ChatSystem.tick(60.0)
	assert_eq(_count_lines("Welcome to the server"), 1, "welcome line posted once")
	assert_eq(_count_lines("Press B to open the buy menu"), 1, "buy-menu hint posted once")
	assert_true(GameState.chat_flags.get("event:first_match", false))

	# Save, wipe, reload.
	var cash_saved := GameState.cash
	assert_true(_saves.save(GameState))
	GameState.new_game()
	assert_eq(CheatSystem.level("speed_hack"), 0, "state wiped")
	assert_eq(_saves.load_into(GameState), SaveService.LoadResult.LOADED)
	EventBus.game_state_loaded.emit()
	assert_eq(CheatSystem.level("speed_hack"), 1, "still owned")
	assert_true(CheatSystem.is_enabled("speed_hack"), "still enabled")
	assert_eq(GameState.lifetime_kills, 10)
	assert_almost_eq(GameState.cash, cash_saved, 0.001)
	assert_almost_eq(player.effective(&"move_speed"), boosted, 0.0001, "effect re-applied after load")

	# A new session on the loaded save: tutorial must not repeat.
	var lines_before := ChatSystem.history.size()
	main.queue_free()
	await wait_physics_frames(2)
	main = add_child_autofree(_make_main())
	await wait_physics_frames(3)
	ChatSystem.tick(60.0)
	assert_eq(_count_lines("Welcome to the server"), 1, "welcome not repeated after reload")
	assert_eq(_count_lines("Press B to open the buy menu"), 1, "buy-menu hint not repeated")
	assert_eq(_count_lines("Round is live. LEFT CLICK"), 0, "live hint never fired (no live round yet)")
	assert_eq(ChatSystem.history.size(), lines_before, "no new chat lines on a reloaded save")
	assert_almost_eq(main.player.effective(&"move_speed"), boosted, 0.0001, "new player gets the cheat")


func test_mod_menu_restores_time_scale() -> void:
	var menu: Node = null
	for n in main.get_node("UI").get_children():
		if n is ModMenu:
			menu = n
	assert_not_null(menu, "mod menu is in the UI layer")
	Engine.time_scale = 1.0
	menu.open_menu()
	assert_true(menu.is_open())
	assert_almost_eq(Engine.time_scale, float(DataRegistry.economy()["mod_menu_time_scale"]), 0.0001)
	menu.close_menu()
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "time scale restored on close")
	# Restores a non-default previous value too.
	Engine.time_scale = 0.5
	menu.toggle_menu()
	menu.toggle_menu()
	assert_almost_eq(Engine.time_scale, 0.5, 0.0001)
	# Freeing the menu while open must not leave the game slowed.
	Engine.time_scale = 1.0
	menu.open_menu()
	main.queue_free()
	await wait_physics_frames(2)
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "time scale restored when menu is freed")


## Pacing: how fast must the player kill to afford Speed Hack within 2 minutes?
func test_first_cheat_pacing_against_economy() -> void:
	var unlock_kills: int = CheatSystem.get_cheat("speed_hack").unlock_kills
	var cost := CheatSystem.next_cost("speed_hack")
	var live_s := float(DataRegistry.economy()["round"]["live_time_s"])
	var tracker: MatchTracker = main.tracker
	tracker.streak = 0
	var total := 0.0
	var kills_needed := 0
	# Unbroken streak, body shots; stop when both the unlock and the price are met.
	while kills_needed < unlock_kills or total < cost:
		total += tracker.kill_value(false, "grunt")
		tracker.streak += 1
		kills_needed += 1
		if kills_needed > 1000:
			break
	var rate_per_min := kills_needed / (120.0 / 60.0)
	gut.p("PACING: Speed Hack costs %.0f, unlocks at %d kills; %d unbroken-streak body kills earn %.0f cash. Need >= %.1f kills/min to buy within 2:00 (one live round is %.0fs)." % [cost, unlock_kills, kills_needed, total, rate_per_min, live_s])
	assert_lte(kills_needed, 20, "first cheat reachable within ~20 kills")
	assert_lte(float(kills_needed) / 120.0 * 60.0, 12.0, "needs no more than 12 kills/min (one kill per 5s)")
