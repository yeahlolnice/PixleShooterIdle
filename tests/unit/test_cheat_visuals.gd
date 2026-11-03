extends GutTest
## Cheat visuals (TASK-030): aimbot FOV circle maths and laser, god-mode
## shimmer, triggerbot flash / spinbot streak, loot ESP price tags.

const PlayerScene := preload("res://shooter/player/player.tscn")
const BotScene := preload("res://shooter/bots/bot.tscn")
const DT := 1.0 / 60.0


class FakePlayer:
	extends RefCounted
	var invulnerable := false

	func is_invulnerable() -> bool:
		return invulnerable


var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


func test_fov_circle_grows_with_the_cone_and_covers_the_screen_at_max() -> void:
	var screen := Vector2(1280, 720)
	var small := CheatFx.fov_radius_px(3.0, 80.0, 720.0, screen)
	var mid := CheatFx.fov_radius_px(20.0, 80.0, 720.0, screen)
	assert_gt(small, 0.0)
	assert_lt(small, 60.0, "level 1 is a small circle")
	assert_gt(mid, small)
	assert_gte(CheatFx.fov_radius_px(180.0, 80.0, 720.0, screen), screen.length(), "max covers the screen")
	assert_eq(CheatFx.fov_radius_px(0.0, 80.0, 720.0, screen), 0.0, "no aimbot, no circle")


func test_triggerbot_flash_spinbot_streak_and_god_shimmer() -> void:
	var fx: CheatFx = add_child_autofree(CheatFx.new())
	EventBus.cheat_fired.emit("triggerbot")
	assert_true(fx.flash_active())
	EventBus.cheat_fired.emit("spinbot")
	assert_true(fx.streak_active())
	fx._process(1.0)
	assert_false(fx.flash_active())
	assert_false(fx.streak_active())
	var p := FakePlayer.new()
	fx.player = p
	assert_false(fx.shows_god_shimmer())
	p.invulnerable = true
	assert_true(fx.shows_god_shimmer())


func test_aimbot_laser_points_at_the_locked_head_and_hides() -> void:
	var world: Node3D = add_child_autofree(Node3D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	var bot: Bot = BotScene.instantiate()
	bot.configure("grunt", DataRegistry.first_arena_id())
	world.add_child(bot)
	bot.global_position = Vector3(2, 0, -8)
	bot.set_physics_process(false)
	await wait_physics_frames(2)
	var c := CheatSystem.get_cheat("aimbot") as Aimbot
	c.apply(player, c.max_level)
	var driver := c.get_driver(player)
	driver.tick(DT)
	var laser := Aimbot.laser_of(driver)
	assert_true(laser.visible, "laser on while locked")
	var from := player.camera.global_position + player.camera.global_transform.basis * Aimbot.LASER_ORIGIN
	assert_almost_eq(laser.scale.z, from.distance_to(CheatTargeting.head_of(bot)), 0.05, "reaches the head")
	c.idle(driver)
	assert_false(laser.visible, "hidden while the cheat cannot act")
	bot.free()
	driver.tick(DT)
	assert_false(laser.visible, "no target, no laser")
	c.remove(player)


func test_loot_price_tag_only_with_loot_magnet() -> void:
	var pickup := LootPickup.new()
	pickup.setup(12.0, DataRegistry.economy()["loot"])
	add_child_autofree(pickup)
	pickup.global_position = Vector3(50, 0, 50)
	pickup.tick(DT)
	assert_false(pickup.tag.visible)
	assert_eq(pickup.tag.text, "$12")
	GameState.cheat_levels[LootPickup.ESP_CHEAT] = 1
	GameState.cheat_enabled[LootPickup.ESP_CHEAT] = true
	pickup.tick(DT)
	assert_true(pickup.tag.visible, "ESP on")
