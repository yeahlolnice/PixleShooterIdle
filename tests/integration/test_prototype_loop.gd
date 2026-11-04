extends GutTest
## Phase 1 loop: freeze -> live -> shoot a bot in the head -> cash -> die -> gun reset.

var main: Node3D


func before_each() -> void:
	GameState.new_game()
	main = add_child_autofree(_make_main())
	await wait_physics_frames(3)


func _go_live() -> void:
	var rounds: RoundController = main.rounds
	assert_true(rounds.is_freeze(), "main starts in freeze time")
	rounds.advance(rounds.time_left + 0.01)
	assert_true(rounds.is_live())


func test_kill_pays_expected_cash_then_death_resets_gun() -> void:
	_go_live()
	var spawner: BotSpawner = main.spawner
	spawner.flush_queue()   # entrance bots walk in over time; let them all in now
	assert_gt(spawner.get_child_count(), 0, "live round spawned bots")
	var player: Player = main.player
	var wm: WeaponManager = player.get_node("WeaponManager")
	var weapon: Weapon = wm.weapon
	weapon.set_modifier("spread_mult", 0.0)
	weapon.set_modifier("recoil_mult", 0.0)

	var bot: Bot = spawner.get_child(0)
	bot.set_physics_process(false)
	var cam: Camera3D = player.get_node("Head/Camera3D")
	cam.make_current()
	var head: Node3D = bot.get_node("Head")
	bot.global_position = cam.global_position + Vector3(0, 0, -6) - Vector3(0, 1.45, 0)
	cam.look_at(head.global_position)
	await wait_physics_frames(2)

	var cash_before: float = GameState.cash
	var expected: float = main.tracker.kill_value(true, bot.bot_id)
	var shots := 0
	while not bot.is_dead() and shots < 20:
		weapon.tick(5.0)
		weapon.ammo = weapon.mag_size()
		weapon.try_fire()
		shots += 1
	assert_true(bot.is_dead(), "bot died from head shots (%d shots)" % shots)
	assert_almost_eq(GameState.cash - cash_before, expected, 0.001, "cash rose by Economy amount")
	assert_eq(GameState.kills, 1)
	assert_eq(main.tracker.streak, 1)

	# Buy a better gun, then die: gun and streak reset, cash stays.
	var better: String = ""
	for g in DataRegistry.guns():
		if g["id"] != DataRegistry.starter_gun_id():
			better = g["id"]
			break
	if better != "":
		wm.equip(better)
		GameState.equipped_gun_id = better
	var cash_after: float = GameState.cash
	player.die(null)
	await wait_physics_frames(1)
	assert_eq(wm.weapon.gun_id(), DataRegistry.starter_gun_id(), "gun reset to starter")
	assert_eq(GameState.equipped_gun_id, DataRegistry.starter_gun_id())
	assert_eq(main.tracker.streak, 0)
	assert_almost_eq(GameState.cash, cash_after, 0.001, "death keeps cash")


func _make_main() -> Node3D:
	var m: Node3D = load("res://scenes/main.tscn").instantiate()
	m.use_save_file = false
	return m
