extends GutTest
## God Mode, Noclip and Loot Magnet (plus the loot drops it pulls) on a real
## Player. Expected values come from data/cheats.json and economy.json.

const PlayerScene := preload("res://shooter/player/player.tscn")
const DT := 1.0 / 60.0

var _world: Node3D
var _player: Player
var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	_world = add_child_autofree(Node3D.new())
	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.set_physics_process(false)


func after_each() -> void:
	GameState.from_dict(_saved)


func _cheat(id: String) -> CheatBase:
	return CheatSystem.get_cheat(id)


func _loot_rules() -> Dictionary:
	return DataRegistry.economy()["loot"]


## A wall on the world layer spanning x/y, `thickness` deep, starting at z = -near.
func _wall(near: float, thickness: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 40, thickness)
	shape.shape = box
	wall.add_child(shape)
	_world.add_child(wall)
	wall.global_position = Vector3(0, 0, -near - thickness * 0.5)
	return wall


func test_cheats_use_their_scripts() -> void:
	assert_true(_cheat("god_mode") is GodMode)
	assert_true(_cheat("noclip") is Noclip)
	assert_true(_cheat("loot_magnet") is LootMagnet)


# --- God Mode ----------------------------------------------------------------------

func test_god_mode_invulnerable_after_kill_then_expires() -> void:
	var c := _cheat("god_mode")
	c.apply(_player, 1)
	var hp := _player.health
	_player.take_damage(10.0, null)
	assert_eq(_player.health, hp - 10.0, "no kill yet: damage lands")
	EventBus.bot_killed.emit(null, {})
	assert_almost_eq(_player.invuln_left, float(c.value_at("invuln_after_kill_s", 1)), 0.0001)
	_player.take_damage(10.0, null)
	assert_eq(_player.health, hp - 10.0, "invulnerable after a kill")
	_player._physics_process(DT)
	assert_almost_eq(_player.invuln_left, float(c.value_at("invuln_after_kill_s", 1)) - DT, 0.0001, "counts down")
	_player.invuln_left = 0.0
	_player.take_damage(10.0, null)
	assert_eq(_player.health, hp - 20.0, "expired")
	c.remove(_player)


func test_god_mode_permanent_at_max_and_removed_cleanly() -> void:
	var c := _cheat("god_mode")
	c.apply(_player, c.max_level)
	assert_true(bool(c.value_at("permanent", c.max_level)))
	var hp := _player.health
	_player.take_damage(1000.0, null)
	assert_eq(_player.health, hp)
	assert_false(_player.is_dead)
	c.remove(_player)
	assert_false(_player.is_invulnerable())
	_player.take_damage(10.0, null)
	assert_eq(_player.health, hp - 10.0)


func test_falling_out_of_the_map_kills_through_god_mode() -> void:
	_cheat("god_mode").apply(_player, _cheat("god_mode").max_level)
	_player.global_position = Vector3(0, float(_player.tuning["fall_kill_y"]) - 5.0, 0)
	_player._physics_process(DT)
	assert_true(_player.is_dead)
	_cheat("god_mode").remove(_player)


# --- Noclip --------------------------------------------------------------------------

## Flies forward (-Z) for up to `seconds`; returns the final z.
func _fly_forward(seconds: float) -> float:
	for i in int(seconds / DT):
		_player.step_noclip(DT, Vector3.FORWARD)
	return _player.global_position.z


func test_noclip_passes_thin_walls_and_is_blocked_by_thick_ones() -> void:
	var c := _cheat("noclip") as Noclip
	c.apply(_player, 1)
	var max_wall := float(c.value_at("max_wall_thickness_m", 1))
	_wall(3.0, max_wall * 0.5)
	_wall(12.0, max_wall + 4.0)
	await wait_physics_frames(2)
	assert_true(_player.toggle_noclip(), "flight starts")
	assert_eq(_player.collision_mask, 0, "no world collision while flying")
	_fly_forward(minf(float(c.value_at("burst_s", 1)), 4.0))
	var z := _player.global_position.z
	assert_lt(z, -3.0 - max_wall * 0.5, "through the thin wall")
	assert_gt(z, -12.0 - (max_wall + 4.0), "stopped inside the thick wall, not through it")
	c.remove(_player)


func test_noclip_fuel_ends_flight_only_when_clear_and_refills_at_freeze() -> void:
	var c := _cheat("noclip") as Noclip
	c.apply(_player, 1)
	var burst := float(c.value_at("burst_s", 1))
	assert_false(bool(c.value_at("unlimited_flight", 1)))
	var mask := _player.collision_mask
	await wait_physics_frames(2)
	_player.toggle_noclip()
	for i in int(burst / DT) + 2:
		_player.step_noclip(DT, Vector3.ZERO)
	assert_false(_player.noclipping, "out of fuel in open air: lands")
	assert_eq(_player.collision_mask, mask, "collision restored")
	assert_false(_player.toggle_noclip(), "no fuel left this round")
	EventBus.round_state_changed.emit(EventBus.ROUND_FREEZE, {})
	assert_almost_eq(_player.noclip_fuel, burst, 0.0001, "refilled at freeze time")
	c.remove(_player)


func test_noclip_unlimited_at_max_and_clear_on_remove() -> void:
	var c := _cheat("noclip") as Noclip
	c.apply(_player, c.max_level)
	assert_true(bool(c.value_at("unlimited_flight", c.max_level)))
	_player.toggle_noclip()
	for i in 600:
		_player.step_noclip(DT, Vector3.ZERO)
	assert_true(_player.noclipping, "no time limit")
	c.remove(_player)
	assert_false(_player.noclipping)
	assert_false(_player.has_noclip())


# --- Loot drops and Loot Magnet ----------------------------------------------------

func _tracker() -> MatchTracker:
	var t: MatchTracker = add_child_autofree(MatchTracker.new())
	t.arena_id = DataRegistry.first_arena_id()
	return t


func test_kills_drop_bonus_loot_worth_share_of_kill_cash() -> void:
	assert_gt(float(_loot_rules()["drop_chance"]), 0.0)
	var dropper: LootDropper = add_child_autofree(LootDropper.new())
	dropper.tracker = _tracker()
	dropper.container = _world
	dropper.seed_rng(1)
	var info := {"headshot": false, "bot_type": "grunt", "position": Vector3(5, 0, 5)}
	var pickup: LootPickup = null
	for i in 100:
		pickup = dropper.drop(info)
		if pickup:
			break
	assert_not_null(pickup, "drops at drop_chance")
	assert_almost_eq(pickup.value, dropper.tracker.kill_value(false, "grunt") * float(_loot_rules()["cash_mult"]), 0.0001)
	assert_true(pickup.is_in_group(LootPickup.GROUP))


func _pickup_at(pos: Vector3, value: float = 7.0) -> LootPickup:
	var p := LootPickup.new()
	p.setup(value, _loot_rules())
	_world.add_child(p)
	p.global_position = pos
	return p


func test_loot_pays_out_when_reached_and_expires() -> void:
	var cash := GameState.cash
	var near := _pickup_at(LootPickup.PLAYER_CENTER + Vector3(0.5, 0, 0))
	near.tick(DT)
	assert_eq(GameState.cash, cash + 7.0)
	assert_true(near.is_queued_for_deletion())
	var far := _pickup_at(Vector3(30, 0, 0))
	far.tick(float(_loot_rules()["lifetime_s"]) + 0.1)
	assert_true(far.is_queued_for_deletion(), "expired")
	assert_eq(GameState.cash, cash + 7.0, "expired loot pays nothing")


func test_loot_magnet_pulls_only_inside_radius() -> void:
	var c := _cheat("loot_magnet") as LootMagnet
	c.apply(_player, 1)
	var radius := float(c.value_at("radius_m", 1))
	var inside := _pickup_at(Vector3(radius * 0.8, 0, 0))
	var outside := _pickup_at(Vector3(radius * 3.0, 0, 0))
	var center := _player.global_position + LootPickup.PLAYER_CENTER
	var d_in := inside.global_position.distance_to(center)
	var d_out := outside.global_position.distance_to(center)
	c.get_driver(_player).tick(DT)
	var step := float(_loot_rules()["magnet_speed_m_s"]) * DT
	assert_almost_eq(inside.global_position.distance_to(center), maxf(d_in - step, 0.0), 0.001, "pulled in")
	assert_almost_eq(outside.global_position.distance_to(center), d_out, 0.0001, "out of range")
	c.remove(_player)
	assert_null(c.get_driver(_player))
