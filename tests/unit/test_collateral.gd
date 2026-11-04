extends GutTest
## Fun pack: collateral (bullets pierce lined-up bots, walls stop them, bonus
## cash) and multi-kill chains (bonus multiplier, announcer).

const PlayerScene := preload("res://shooter/player/player.tscn")
const BotScene := preload("res://shooter/bots/bot.tscn")

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


## Grunts straight ahead (-Z) at these distances; the camera ray at 1.6 m hits their heads.
func _line(distances: Array) -> Array:
	var out := []
	for d in distances:
		var b: Bot = BotScene.instantiate()
		b.configure("grunt", DataRegistry.first_arena_id())
		_world.add_child(b)
		b.global_position = Vector3(0, 0, -float(d))
		b.set_physics_process(false)
		out.append(b)
	return out


func _gun(id: String) -> Weapon:
	var wm: WeaponManager = _player.get_node("WeaponManager")
	wm.equip(id)
	wm.weapon.set_modifier("spread_mult", 0.0)
	wm.weapon.set_modifier("recoil_mult", 0.0)
	return wm.weapon


func _fire(w: Weapon) -> Dictionary:
	watch_signals(w)
	assert_true(w.try_fire())
	return get_signal_parameters(w, "shot_fired")[0]


func test_pierce_comes_from_data() -> void:
	var col: Dictionary = DataRegistry.economy()["collateral"]
	var w := _gun(DataRegistry.starter_gun_id())
	assert_eq(w.pierce(), int(col["pierce"]), "default pierce")
	for g in DataRegistry.guns():
		if g.has("pierce"):
			assert_eq(_gun(g["id"]).pierce(), int(g["pierce"]), "%s override" % g["id"])


func test_bullet_passes_through_a_column_losing_damage() -> void:
	var bots := _line([4, 5.5, 7, 8.5])
	await wait_physics_frames(2)
	var w := _gun(DataRegistry.starter_gun_id())
	var hp := float(bots[0].health)
	var hit := _fire(w)
	assert_eq(hit["bots_hit"], w.pierce() + 1, "one bot plus pierce() more")
	assert_lt(bots[0].health, hp)
	assert_lt(bots[1].health, hp, "second in line hit too")
	assert_eq(bots[3].health, hp, "past the pierce limit")
	var lost0 := hp - float(bots[0].health)
	var lost1 := hp - float(bots[1].health)
	assert_almost_eq(lost1, lost0 * float(DataRegistry.economy()["collateral"]["damage_falloff"]), 0.01, "falloff")


func test_walls_stop_the_bullet() -> void:
	var bots := _line([4, 8])
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 10, 0.5)
	shape.shape = box
	wall.add_child(shape)
	_world.add_child(wall)
	wall.global_position = Vector3(0, 0, -6)
	await wait_physics_frames(2)
	var hit := _fire(_gun(DataRegistry.starter_gun_id()))
	assert_eq(hit["bots_hit"], 1)
	assert_eq(bots[1].health, float(bots[1].stats["health"]), "behind the wall: untouched")


func test_collateral_kill_pays_a_bonus() -> void:
	var t: MatchTracker = add_child_autofree(MatchTracker.new())
	t.arena_id = DataRegistry.first_arena_id()
	_line([4, 5.5, 7])
	await wait_physics_frames(2)
	var w := _gun("pistol_hand_cannon")
	watch_signals(EventBus)
	var hit := _fire(w)
	assert_eq(hit["kills"], 3, "one big bullet, three kills")
	assert_signal_emitted_with_parameters(EventBus, "collateral_kill", [3, Vector3(0, 0, -7)])
	assert_signal_emitted(EventBus, "bonus_paid")
	var p: Array = get_signal_parameters(EventBus, "bonus_paid")
	assert_eq(p[0], "COLLATERAL x3")
	assert_gt(float(p[1]), 0.0)


func test_multi_kill_chain_multiplies_cash_and_resets() -> void:
	var rules: Dictionary = DataRegistry.economy()["multi_kill"]
	var t: MatchTracker = add_child_autofree(MatchTracker.new())
	t.arena_id = DataRegistry.first_arena_id()
	watch_signals(EventBus)
	EventBus.bot_killed.emit(null, {"bot_type": "grunt"})
	assert_signal_not_emitted(EventBus, "multi_kill", "one kill is not a chain")
	var plain := t.kill_value(false, "grunt")
	var before := GameState.cash
	EventBus.bot_killed.emit(null, {"bot_type": "grunt"})
	var mult := 1.0 + float(rules["step"])
	assert_almost_eq(GameState.cash - before, plain * mult, 0.01, "double kill pays more")
	assert_signal_emitted_with_parameters(EventBus, "multi_kill", [2, mult])
	t.tick(float(rules["window_s"]) + 0.1)
	EventBus.bot_killed.emit(null, {"bot_type": "grunt"})
	assert_eq(t.chain, 1, "chain broke after the window")
	for i in 20:
		EventBus.bot_killed.emit(null, {"bot_type": "grunt"})
	assert_almost_eq(t.advance_chain(), float(rules["cap"]), 0.0001, "capped")


func test_announcer_lines() -> void:
	var fb: HudFeedback = add_child_autofree(HudFeedback.new())
	EventBus.multi_kill.emit(2, 1.5)
	assert_eq(fb.announcement(), "DOUBLE KILL  x1.5")
	EventBus.multi_kill.emit(7, 3.0)
	assert_eq(fb.announcement(), "RAMPAGE x7  x3.0")
	EventBus.bonus_paid.emit("COLLATERAL x3", 45.0, Vector3.ZERO)
	assert_eq(fb.announcement(), "COLLATERAL x3  +$45")
	fb._process(5.0)
	assert_eq(fb.announcement(), "", "fades out")
