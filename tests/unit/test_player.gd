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
