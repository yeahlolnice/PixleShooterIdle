extends GutTest
## Sentry.exe (fun pack, D66): upgrades in data, deployment on arena spots, the
## turret aiming and shooting only what it can see, and the 50% sentry payout.

const BotScene := preload("res://shooter/bots/bot.tscn")
const DT := 1.0 / 60.0

var _world: Node3D
var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	_world = add_child_autofree(Node3D.new())


func after_each() -> void:
	GameState.from_dict(_saved)


func _bot(pos: Vector3, type := "grunt") -> Bot:
	var b: Bot = BotScene.instantiate()
	b.configure(type, DataRegistry.first_arena_id())
	_world.add_child(b)
	b.global_position = pos
	b.set_physics_process(false)
	return b


func _sentry(pos: Vector3) -> Sentry:
	var s := Sentry.new()
	_world.add_child(s)
	s.global_position = pos
	return s


func _run(s: Sentry, seconds: float) -> void:
	for i in int(seconds / DT):
		s.tick(DT)


func test_upgrades_live_on_the_sentries_tab() -> void:
	assert_true(DataRegistry.cheat_tabs().has("Sentries"))
	for id in [SentryManager.COUNT_UPGRADE, SentryManager.DAMAGE_UPGRADE, SentryManager.RATE_UPGRADE]:
		assert_true(CheatSystem.is_upgrade(id), id)
		assert_eq(CheatSystem.get_cheat(id).tab, "Sentries")


func test_manager_deploys_one_per_level_on_arena_spots() -> void:
	var m: SentryManager = add_child_autofree(SentryManager.new())
	var id := DataRegistry.first_arena_id()
	var spots: Array = DataRegistry.arena(id)["sentry_spots"]
	m.rebuild(id)
	assert_eq(m.sentries().size(), 0, "none until bought")
	GameState.cheat_levels[SentryManager.COUNT_UPGRADE] = 3
	m.sync()
	assert_eq(m.sentries().size(), roundi(float(CheatSystem.get_cheat(SentryManager.COUNT_UPGRADE).value_at("count", 3))))
	for i in m.sentries().size():
		assert_eq(m.sentries()[i].global_position, spots[i], "on spot %d" % i)
	GameState.cheat_levels[SentryManager.DAMAGE_UPGRADE] = 2
	m.sync()
	assert_gt(m.sentries()[0].damage_mult, 1.0, "damage upgrade pushed in")
	var second := DataRegistry.arenas()[1]["id"] as String
	m.rebuild(second)
	assert_eq(m.sentries()[0].global_position, DataRegistry.arena(second)["sentry_spots"][0], "moved to the new arena")


func test_sentry_turns_and_shoots_what_it_sees() -> void:
	var bot := _bot(Vector3(6, 0, 0))
	var s := _sentry(Vector3.ZERO)
	await wait_physics_frames(2)
	var hp := bot.health
	_run(s, 1.0)
	assert_eq(s.target, bot, "locked on")
	assert_lt(bot.health, hp, "shot it")


func test_sentry_ignores_bots_behind_walls_and_out_of_range() -> void:
	var range_m := float(DataRegistry.economy()["sentries"]["range_m"])
	var far := _bot(Vector3(0, 0, -(range_m + 5.0)))
	var hidden := _bot(Vector3(6, 0, 0))
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 10, 10)
	shape.shape = box
	wall.add_child(shape)
	_world.add_child(wall)
	wall.global_position = Vector3(3, 0, 0)
	var s := _sentry(Vector3.ZERO)
	await wait_physics_frames(2)
	_run(s, 1.0)
	assert_null(s.target)
	assert_eq(far.health, float(far.stats["health"]))
	assert_eq(hidden.health, float(hidden.stats["health"]))


func test_sentry_kills_pay_half_and_skip_the_streak() -> void:
	var t: MatchTracker = add_child_autofree(MatchTracker.new())
	t.arena_id = DataRegistry.first_arena_id()
	t.streak = 4
	var full := t.kill_value(false, "grunt")
	t.streak = 0
	var plain := t.kill_value(false, "grunt")
	t.streak = 4
	var before := GameState.cash
	EventBus.bot_killed.emit(null, {"bot_type": "grunt", "gun_id": Sentry.GUN_ID})
	var paid := GameState.cash - before
	assert_almost_eq(paid, plain * float(DataRegistry.economy()["sentries"]["cash_mult"]), 0.001)
	assert_lt(paid, full, "playing yourself pays more")
	assert_eq(t.streak, 4, "streak untouched")
	assert_eq(t.chain, 0, "no multi-kill chain")
	assert_eq(GameState.lifetime_kills, 1, "still counts toward unlocks")


func test_kill_feed_tags_sentry_kills() -> void:
	assert_string_contains(HudFeedback.feed_text(6.0, {"bot_type": "grunt", "gun_id": Sentry.GUN_ID}), "[SENTRY]")
