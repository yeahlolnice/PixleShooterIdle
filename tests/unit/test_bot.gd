extends GutTest

const BotScene := preload("res://shooter/bots/bot.tscn")

var _killed: Array = []


func _make_bot(arena_id := "arena_1") -> Bot:
	var bot: Bot = BotScene.instantiate()
	bot.configure("grunt", arena_id)
	add_child_autofree(bot)
	return bot


func _on_killed(bot: Node, info: Dictionary) -> void:
	_killed.append([bot, info])


func before_each() -> void:
	_killed.clear()
	EventBus.bot_killed.connect(_on_killed)


func after_each() -> void:
	EventBus.bot_killed.disconnect(_on_killed)


func test_stats_resolve_from_bots_json_and_arena_multipliers() -> void:
	var base := DataRegistry.bot("grunt")
	var arena := {"bot_mults": {"health": 2.0, "move_speed": 1.5, "reaction_time": 0.5,
			"aim_error": 0.5, "fire_rate": 2.0, "damage": 3.0}}
	var s := DataRegistry.resolve_bot_stats(base, arena)
	assert_almost_eq(s["health"], base["health"] * 2.0, 0.001)
	assert_almost_eq(s["move_speed"], base["move_speed"] * 1.5, 0.001)
	assert_almost_eq(s["reaction_time_s"], base["reaction_time_s"] * 0.5, 0.001)
	assert_almost_eq(s["aim_error_deg"], base["aim_error_deg"] * 0.5, 0.001)
	assert_almost_eq(s["fire_rate"], base["fire_rate"] * 2.0, 0.001)
	assert_almost_eq(s["damage"], base["damage"] * 3.0, 0.001)


func test_arena_1_stats_equal_base_stats() -> void:
	var s := Bot.resolve_stats("grunt", "arena_1")
	assert_eq(s["health"], DataRegistry.bot("grunt")["health"])


func test_body_hit_applies_1x_and_head_hit_applies_multiplier() -> void:
	var bot := _make_bot()
	var start := bot.health
	assert_almost_eq(bot.take_hit("body", 10.0, "pistol", 2.0), 10.0, 0.001)
	assert_almost_eq(bot.health, start - 10.0, 0.001)
	assert_almost_eq(bot.take_hit("head", 10.0, "pistol", 2.5), 25.0, 0.001)
	assert_almost_eq(bot.health, start - 35.0, 0.001)
	assert_eq(_killed.size(), 0)


func test_kill_at_zero_hp_reports_headshot_once() -> void:
	var bot := _make_bot()
	bot.take_hit("head", bot.health, "pistol", 2.0)
	assert_true(bot.is_dead())
	assert_eq(bot.health, 0.0)
	assert_eq(_killed.size(), 1)
	assert_true(_killed[0][1]["headshot"])
	assert_eq(_killed[0][1]["bot_type"], "grunt")
	bot.take_hit("body", 50.0)
	assert_eq(_killed.size(), 1, "dead bots do not die twice")


func test_body_kill_is_not_headshot() -> void:
	var bot := _make_bot()
	bot.take_hit("body", bot.health + 1.0, "pistol")
	assert_eq(_killed.size(), 1)
	assert_false(_killed[0][1]["headshot"])


func test_hitboxes_tagged_head_and_body() -> void:
	var bot := _make_bot()
	assert_eq(bot.get_node("HeadHitbox").get_meta("hit_kind"), "head")
	assert_eq(bot.get_node("BodyHitbox").get_meta("hit_kind"), "body")
	assert_eq(bot.get_node("HeadHitbox").collision_layer, Layers.HITBOXES)


func test_default_hit_chance_is_low() -> void:
	# Documented in docs/DATA.md: at arena_1 stats a 0.4 m radius player is hit rarely.
	var err: float = Bot.resolve_stats("grunt", "arena_1")["aim_error_deg"]
	assert_lt(Bot.hit_probability(err, 10.0, 0.4), 0.10)
	assert_lt(Bot.hit_probability(err, 5.0, 0.4), 0.30)


func test_aimed_direction_stays_inside_cone() -> void:
	var bot := _make_bot()
	var max_deg: float = bot.stats["aim_error_deg"]
	var aim := bot.global_position + Vector3(0, Bot.EYE_HEIGHT, -10)
	var base := Vector3(0, 0, -1)
	for i in 200:
		var d := bot.aimed_direction(aim)
		assert_lte(rad_to_deg(base.angle_to(d)), max_deg + 0.01)


func test_spawner_count_from_data_plus_extra_slots() -> void:
	var arena := DataRegistry.arena("arena_1")
	assert_eq(BotSpawner.wave_size(arena), arena["bots_per_wave"])
	assert_eq(BotSpawner.wave_size(arena, 3), arena["bots_per_wave"] + 3)
	var stub := Node3D.new()
	add_child_autofree(stub)
	var spawner := BotSpawner.new()
	spawner.target = stub
	add_child_autofree(spawner)
	var bots := spawner.spawn_wave("arena_1", 2)
	assert_eq(bots.size(), arena["bots_per_wave"] + 2)
	assert_eq(spawner.alive_count(), bots.size())
	var spawns: Array = arena["bot_spawns"]
	for i in bots.size():
		assert_eq(bots[i]._home, spawns[i % spawns.size()], "home is spawn point")
	watch_signals(spawner)
	for b in bots:
		b.take_hit("body", 9999.0)
	assert_signal_emitted(spawner, "wave_cleared")
