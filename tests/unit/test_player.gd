extends GutTest

const PlayerScene := preload("res://shooter/player/player.tscn")
const ArenaScene := preload("res://shooter/arenas/arena.tscn")


func _make_player() -> Player:
	return add_child_autofree(PlayerScene.instantiate())


func test_move_speed_mult_changes_effective_speed() -> void:
	var p := _make_player()
	var base := p.effective(&"move_speed")
	assert_almost_eq(base, float(DataRegistry.player()["move_speed"]), 0.0001)
	p.set_stat_mod(&"move_speed_mult", 1.5)
	assert_almost_eq(p.effective(&"move_speed"), base * 1.5, 0.0001)
	p.clear_stat_mod(&"move_speed_mult")
	assert_almost_eq(p.effective(&"move_speed"), base, 0.0001)
	assert_eq(p.tuning["move_speed"], DataRegistry.player()["move_speed"], "raw tuning untouched")


func test_pitch_is_clamped() -> void:
	var p := _make_player()
	p.look(Vector2(0, -100000))
	assert_almost_eq(p.get_pitch(), deg_to_rad(float(p.tuning["pitch_limit_deg"])), 0.0001)
	p.look(Vector2(0, 200000))
	assert_almost_eq(p.get_pitch(), -deg_to_rad(float(p.tuning["pitch_limit_deg"])), 0.0001)


func test_recoil_kick_moves_aim_and_stays() -> void:
	var p := _make_player()
	var start := p.get_pitch()
	p.add_aim_kick(2.0)
	p.add_aim_kick(2.0)
	assert_almost_eq(p.get_pitch(), start + deg_to_rad(4.0), 0.0001)
	p._physics_process(1.0)
	assert_almost_eq(p.get_pitch(), start + deg_to_rad(4.0), 0.0001, "no auto-recovery")
	p.add_aim_kick(1000.0)
	assert_almost_eq(p.get_pitch(), deg_to_rad(float(p.tuning["pitch_limit_deg"])), 0.0001)


func test_death_signal_and_respawn() -> void:
	var p := _make_player()
	p.spawn_points.assign([Vector3(1, 1, 1)])
	watch_signals(EventBus)
	p.take_damage(p.health + 1.0, null)
	assert_true(p.is_dead)
	assert_signal_emit_count(EventBus, "player_died", 1)
	p.step_movement(0.0, Vector3.ZERO, false)
	p._physics_process(float(p.tuning["respawn_delay_s"]) + 0.1)
	assert_false(p.is_dead)
	assert_eq(p.health, p.effective(&"max_health"))
	assert_eq(p.global_position, Vector3(1, 1, 1))
	assert_signal_emit_count(EventBus, "player_spawned", 1)


func test_walks_collides_and_does_not_tunnel() -> void:
	var arena: Node3D = add_child_autofree(ArenaScene.instantiate())
	arena.build(DataRegistry.arena("arena_1"))
	var p := _make_player()
	p.set_stat_mod(&"move_speed_mult", 5.0)
	p.global_position = Vector3(0, 0.5, 16)
	for i in 20:
		p.step_movement(1.0 / 60.0, Vector3.ZERO, false)
	assert_true(p.is_on_floor())
	# Run at the +Z wall (inner face at z=20) for 3 seconds at 5x speed.
	for i in 180:
		p.step_movement(1.0 / 60.0, Vector3(0, 0, 1), false)
	assert_lt(p.global_position.z, 20.0, "stopped by wall")
	# Jump leaves the floor.
	p.step_movement(1.0 / 60.0, Vector3.ZERO, true)
	assert_gt(p.velocity.y, 0.0)


# TASK-015: closing one menu must not re-enable input while another is still open.
func test_menu_state_is_tracked_per_menu_id() -> void:
	var p := _make_player()
	EventBus.menu_toggled.emit(&"buy_menu", true)
	EventBus.menu_toggled.emit(&"mod_menu", true)
	EventBus.menu_toggled.emit(&"mod_menu", false)
	assert_true(p.is_menu_open(), "buy menu still open")
	assert_false(p.input_enabled, "input stays disabled while buy menu is open")
	EventBus.menu_toggled.emit(&"buy_menu", false)
	assert_false(p.is_menu_open())
	assert_true(p.input_enabled)


func test_repeated_close_of_same_menu_is_harmless() -> void:
	var p := _make_player()
	EventBus.menu_toggled.emit(&"buy_menu", true)
	EventBus.menu_toggled.emit(&"buy_menu", true)
	EventBus.menu_toggled.emit(&"mod_menu", false)
	assert_false(p.input_enabled, "closing a menu that was never open changes nothing")
	EventBus.menu_toggled.emit(&"buy_menu", false)
	assert_true(p.input_enabled)
