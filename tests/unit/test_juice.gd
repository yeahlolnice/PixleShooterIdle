extends GutTest
## Juice pack (TASK-027): kill_rewarded payout, hit marker, kill feed, death
## screen, scope overlay, world damage/cash numbers, and screen shake.

const PlayerScene := preload("res://shooter/player/player.tscn")
const BotScene := preload("res://shooter/bots/bot.tscn")

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


func test_tracker_announces_the_cash_each_kill_paid() -> void:
	var t: MatchTracker = add_child_autofree(MatchTracker.new())
	t.arena_id = DataRegistry.first_arena_id()
	var expected := t.kill_value(true, "grunt")
	watch_signals(EventBus)
	EventBus.bot_killed.emit(null, {"headshot": true, "bot_type": "grunt", "position": Vector3.ONE})
	assert_signal_emitted(EventBus, "kill_rewarded")
	var params: Array = get_signal_parameters(EventBus, "kill_rewarded")
	assert_almost_eq(float(params[0]), expected, 0.001)
	assert_eq(params[1]["position"], Vector3.ONE)


func test_hit_marker_and_kill_feed() -> void:
	var fb: HudFeedback = add_child_autofree(HudFeedback.new())
	assert_false(fb.is_marker_visible())
	EventBus.bot_damaged.emit(null, {"amount": 25.0, "headshot": false, "position": Vector3.ZERO})
	assert_true(fb.is_marker_visible(), "hit marker on damage")
	fb._process(1.0)
	assert_false(fb.is_marker_visible(), "fades")
	EventBus.kill_rewarded.emit(240.0, {"bot_type": "sniper", "headshot": true, "gun_id": "rifle_block47"})
	assert_true(fb.is_marker_visible(), "kill marker")
	assert_eq(fb.feed_lines(), [HudFeedback.feed_text(240.0, {"bot_type": "sniper", "headshot": true, "gun_id": "rifle_block47"})])
	assert_string_contains(fb.feed_lines()[0], "$240")
	assert_string_contains(fb.feed_lines()[0], "Sniper")
	assert_string_contains(fb.feed_lines()[0], "HEADSHOT")
	for i in HudFeedback.FEED_LINES + 3:
		EventBus.kill_rewarded.emit(10.0, {"bot_type": "grunt"})
	assert_eq(fb.feed_lines().size(), HudFeedback.FEED_LINES, "capped")


func test_death_screen_names_the_killer_until_respawn() -> void:
	var fb: HudFeedback = add_child_autofree(HudFeedback.new())
	var bot: Bot = BotScene.instantiate()
	bot.configure("rusher", DataRegistry.first_arena_id())
	add_child_autofree(bot)
	EventBus.player_died.emit({"position": Vector3.ZERO, "killer": bot})
	assert_true(fb.is_death_screen_visible())
	assert_string_contains(fb.death_screen_text(), "Rusher")
	EventBus.player_spawned.emit(null)
	assert_false(fb.is_death_screen_visible())


func test_scope_overlay_follows_scope_changed() -> void:
	var fb: HudFeedback = add_child_autofree(HudFeedback.new())
	EventBus.scope_changed.emit(true)
	assert_true(fb.is_scope_visible())
	EventBus.scope_changed.emit(false)
	assert_false(fb.is_scope_visible())


func test_manager_announces_scope() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var wm: WeaponManager = p.get_node("WeaponManager")
	for g in DataRegistry.guns():
		if float(g.get("zoom_fov", 0.0)) > 0.0:
			wm.equip(g["id"])
	watch_signals(EventBus)
	wm.set_aiming(true)
	assert_signal_emitted_with_parameters(EventBus, "scope_changed", [true])
	wm.equip(DataRegistry.starter_gun_id())
	assert_signal_emitted_with_parameters(EventBus, "scope_changed", [false])


func test_world_numbers_spawn_and_free_themselves() -> void:
	var fx: HitFx = add_child_autofree(HitFx.new())
	EventBus.bot_damaged.emit(null, {"amount": 25.0, "headshot": true, "position": Vector3.ZERO})
	EventBus.kill_rewarded.emit(12.0, {"position": Vector3.ZERO})
	assert_eq(fx.get_child_count(), 2)
	var texts := fx.get_children().map(func(l): return l.text)
	assert_true(texts.has("-25"))
	assert_true(texts.has("+$12"))
	await wait_seconds(HitFx.CASH_LIFE_S + 0.2)
	assert_eq(fx.get_child_count(), 0, "gone after their life")


func test_shake_on_hit_caps_and_decays() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var cfg: Dictionary = p.tuning["shake"]
	p.take_damage(1.0, null)
	assert_almost_eq(p.shake, float(cfg["on_hit"]), 0.0001)
	for i in 20:
		p.add_shake(float(cfg["on_hit"]))
	assert_almost_eq(p.shake, float(cfg["max"]), 0.0001, "capped")
	p._process(0.05)
	assert_ne(p.camera.h_offset + p.camera.v_offset, 0.0, "camera jitters")
	p._process(10.0)
	p._process(0.01)
	assert_eq(p.shake, 0.0)
	assert_eq(p.camera.h_offset, 0.0, "back to rest")
