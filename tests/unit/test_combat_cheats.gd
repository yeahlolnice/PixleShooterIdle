extends GutTest
## Aimbot, Triggerbot, Spinbot and Hitbox Expander on a real Player and real
## bots: data wiring, FOV gate, snapping, firing through WeaponManager, and
## head hitbox scaling. Expected values come from data/cheats.json.

const PlayerScene := preload("res://shooter/player/player.tscn")
const BotScene := preload("res://shooter/bots/bot.tscn")
const DT := 1.0 / 60.0

var _world: Node3D
var _player: Player


func before_each() -> void:
	_world = add_child_autofree(Node3D.new())
	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.set_physics_process(false)  # stays at the origin facing -Z


func after_each() -> void:
	Bot.head_hitbox_scale = 1.0


func _cheat(id: String) -> CheatBase:
	return CheatSystem.get_cheat(id)


func _spawn_bot(pos: Vector3, bot_type := "grunt") -> Bot:
	var bot: Bot = BotScene.instantiate()
	bot.configure(bot_type, DataRegistry.first_arena_id())
	_world.add_child(bot)
	bot.global_position = pos
	bot.set_physics_process(false)
	return bot


## Degrees between the camera's aim and `bot`'s head.
func _aim_error_deg(bot: Bot) -> float:
	var cam := _player.camera
	return rad_to_deg((-cam.global_transform.basis.z).angle_to(CheatTargeting.head_of(bot) - cam.global_position))


## Degrees between the camera's aim and `bot`'s head, ignoring height (recoil).
func _yaw_error_deg(bot: Bot) -> float:
	var cam := _player.camera
	var fwd := -cam.global_transform.basis.z
	var to := CheatTargeting.head_of(bot) - cam.global_position
	return rad_to_deg(absf(Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))))


func _weapon() -> Weapon:
	return CheatBase.weapon_of(_player) as Weapon


func test_cheats_use_their_scripts() -> void:
	assert_true(_cheat("aimbot") is Aimbot)
	assert_true(_cheat("triggerbot") is Triggerbot)
	assert_true(_cheat("spinbot") is Spinbot)
	assert_true(_cheat("hitbox_expander") is HitboxExpander)


# --- Aimbot ------------------------------------------------------------------------

func test_aimbot_locks_heads_inside_fov_only() -> void:
	var bot := _spawn_bot(Vector3(4, 0, -6))
	await wait_physics_frames(2)
	var c := _cheat("aimbot") as Aimbot
	var start := _aim_error_deg(bot)
	c.apply(_player, 1)
	assert_lt(float(c.value_at("fov_deg", 1)), start, "bot starts outside the level 1 FOV")
	c.get_driver(_player).tick(DT)
	assert_almost_eq(_aim_error_deg(bot), start, 0.001, "outside FOV: aim untouched")
	c.apply(_player, c.max_level)
	var driver := c.get_driver(_player)
	for i in 10:
		driver.tick(DT)
	assert_lt(_aim_error_deg(bot), 0.5, "max level locks on")
	assert_eq(_weapon().modifiers["force_headshot"], bool(c.value_at("instant_headshot", c.max_level)))
	c.remove(_player)
	assert_null(c.get_driver(_player), "driver removed")
	assert_false(_weapon().modifiers["force_headshot"])


func test_aimbot_ignores_bots_behind_walls() -> void:
	var bot := _spawn_bot(Vector3(2, 0, -8))
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 10, 0.5)
	shape.shape = box
	wall.add_child(shape)
	_world.add_child(wall)
	wall.global_position = Vector3(0, 0, -4)
	await wait_physics_frames(2)
	var c := _cheat("aimbot") as Aimbot
	var start := _aim_error_deg(bot)
	c.apply(_player, c.max_level)
	c.get_driver(_player).tick(DT)
	assert_almost_eq(_aim_error_deg(bot), start, 0.001)
	c.remove(_player)


# --- Triggerbot --------------------------------------------------------------------

func test_triggerbot_fires_after_delay_on_target() -> void:
	_spawn_bot(Vector3(0, 0, -6))  # camera ray at 1.6 m hits the head hitbox
	await wait_physics_frames(2)
	var c := _cheat("triggerbot") as Triggerbot
	c.apply(_player, 1)
	var delay := float(c.value_at("delay_s", 1))
	var driver := c.get_driver(_player)
	var ammo := _weapon().ammo
	if delay > DT:
		driver.tick(DT)
		assert_eq(_weapon().ammo, ammo, "waits delay_s before firing")
	driver.tick(delay + DT)
	assert_eq(_weapon().ammo, ammo - 1, "fires once the delay has passed")
	c.remove(_player)


func test_triggerbot_holds_fire_off_target() -> void:
	_spawn_bot(Vector3(5, 0, 5))
	await wait_physics_frames(2)
	var c := _cheat("triggerbot") as Triggerbot
	c.apply(_player, c.max_level)
	var ammo := _weapon().ammo
	c.get_driver(_player).tick(1.0)
	assert_eq(_weapon().ammo, ammo)
	c.remove(_player)


# --- Spinbot -----------------------------------------------------------------------

func test_spinbot_whips_around_and_fires_on_interval() -> void:
	var bot := _spawn_bot(Vector3(1, 0, 7), "rusher")  # behind the player; survives one headshot
	await wait_physics_frames(2)
	var c := _cheat("spinbot") as Spinbot
	c.apply(_player, 1)
	var driver := c.get_driver(_player)
	var ammo := _weapon().ammo
	driver.tick(DT)
	assert_lt(_yaw_error_deg(bot), 0.5, "turned to the bot behind")
	assert_eq(_weapon().ammo, ammo - 1, "fired")
	if not bool(c.value_at("constant_fire", 1)):
		_weapon().tick(10.0)  # gun ready again; only the spin interval holds it
		driver.tick(DT)
		assert_eq(_weapon().ammo, ammo - 1, "waits spin_interval_s")
		driver.tick(float(c.value_at("spin_interval_s", 1)))
		assert_eq(_weapon().ammo, ammo - 2, "fires again after the interval")
	c.remove(_player)


# --- Hitbox Expander ---------------------------------------------------------------

func test_hitbox_expander_scales_existing_and_new_heads_and_restores() -> void:
	var before := _spawn_bot(Vector3(0, 0, -6))
	var c := _cheat("hitbox_expander") as HitboxExpander
	var lvl := c.max_level
	var scale := float(c.value_at("head_scale", lvl))
	assert_gt(scale, 1.0)
	c.apply(_player, lvl)
	assert_eq(before.head_hitbox_size(), Bot.HEAD_SIZE * scale, "bot already in the scene")
	var after := _spawn_bot(Vector3(0, 0, -9))
	assert_eq(after.head_hitbox_size(), Bot.HEAD_SIZE * scale, "bot spawned later")
	c.remove(_player)
	assert_eq(before.head_hitbox_size(), Bot.HEAD_SIZE)
	assert_eq(after.head_hitbox_size(), Bot.HEAD_SIZE)


func test_force_headshot_counts_body_hits_as_heads() -> void:
	var bot := _spawn_bot(Vector3(0, 0, -6))
	_player.aim_at(bot.global_position + Vector3(0, 0.6, 0), 1.0)  # chest: body hitbox
	await wait_physics_frames(2)
	watch_signals(EventBus)
	_weapon().set_modifier("spread_mult", 0.0)
	_weapon().set_modifier("force_headshot", true)
	assert_true(_weapon().try_fire())
	var sig := "bot_killed" if bot.is_dead() else "bot_damaged"
	assert_signal_emitted(EventBus, sig)
	assert_true(get_signal_parameters(EventBus, sig)[1]["headshot"], "body hit counted as headshot")
