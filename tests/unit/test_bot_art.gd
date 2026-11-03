extends GutTest
## Art pass v1 (TASK-029): faces, per-type accessories and silhouettes with
## matching hitboxes, and the coin + confetti death burst.

const BotScene := preload("res://shooter/bots/bot.tscn")

var _world: Node3D


func before_each() -> void:
	_world = add_child_autofree(Node3D.new())


func _bot(id: String) -> Bot:
	var bot: Bot = BotScene.instantiate()
	bot.configure(id, DataRegistry.first_arena_id())
	_world.add_child(bot)
	bot.set_physics_process(false)
	return bot


func test_every_bot_has_a_face() -> void:
	for id in ["grunt", "sniper", "rusher"]:
		var bot := _bot(id)
		for part in ["EyeL", "EyeR", "Mouth"]:
			assert_not_null(bot.get_node_or_null(part), "%s %s" % [id, part])


func test_accessories_per_behaviour() -> void:
	assert_not_null(_bot("sniper").get_node_or_null("Cap"))
	assert_not_null(_bot("rusher").get_node_or_null("Headband"))
	var grunt := _bot("grunt")
	assert_null(grunt.get_node_or_null("Cap"))
	assert_null(grunt.get_node_or_null("Headband"))


func test_silhouette_and_hitbox_follow_body_size() -> void:
	var sniper := _bot("sniper")
	var size: Vector3 = DataRegistry.bot("sniper")["body_size"]
	var hitbox: Area3D = sniper.get_node("BodyHitbox")
	var shape: BoxShape3D = (hitbox.get_child(0) as CollisionShape3D).shape
	assert_eq(shape.size, size, "hitbox matches the mesh")
	assert_almost_eq(sniper.get_node("Head").position.y, size.y + Bot.HEAD_SIZE.y * 0.5, 0.0001, "head sits on the body")
	var rusher := _bot("rusher")
	assert_lt(rusher.get_node("Head").position.y, sniper.get_node("Head").position.y, "rushers are shorter")


func test_death_bursts_into_coins_and_confetti() -> void:
	var bot := _bot("grunt")
	bot.take_hit("head", 100000.0)
	var coins := _world.get_children().filter(func(n): return n.get_meta("pop", "") == "coin")
	var confetti := _world.get_children().filter(func(n): return n.get_meta("pop", "") == "confetti")
	assert_eq(coins.size(), Bot.POP_PARTICLES)
	assert_eq(confetti.size(), Bot.CONFETTI)
	assert_eq((coins[0] as MeshInstance3D).material_override.albedo_color, DataRegistry.color("cash"))
