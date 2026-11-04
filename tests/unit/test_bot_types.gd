extends GutTest
## Bot types (TASK-025): snipers engage from long range and keep their
## distance, rushers strafe while shooting. Values come from data/bots.json.

const BotScene := preload("res://shooter/bots/bot.tscn")
const DT := 1.0 / 60.0

var _world: Node3D
var _target: Node3D


func before_each() -> void:
	_world = add_child_autofree(Node3D.new())
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	shape.shape = box
	floor_body.add_child(shape)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	_target = Node3D.new()
	_world.add_child(_target)


func _bot(id: String, target_pos: Vector3) -> Bot:
	_target.global_position = target_pos
	var bot: Bot = BotScene.instantiate()
	bot.configure(id, DataRegistry.first_arena_id(), _target)
	_world.add_child(bot)
	bot.global_position = Vector3(0, 0.05, 0)
	bot.set_physics_process(false)
	return bot


func _run(bot: Bot, seconds: float) -> void:
	for i in int(seconds / DT):
		bot._physics_process(DT)


func _flat_distance(bot: Bot) -> float:
	return Vector2(bot.global_position.x - _target.global_position.x, bot.global_position.z - _target.global_position.z).length()


func test_types_and_behaviours_in_data() -> void:
	assert_eq(DataRegistry.bot("sniper")["behaviour"], "sniper")
	assert_eq(DataRegistry.bot("rusher")["behaviour"], "rusher")
	assert_gt(float(DataRegistry.bot("sniper")["sight_range_m"]), float(DataRegistry.bot("grunt")["sight_range_m"]))
	assert_gt(float(DataRegistry.bot("rusher")["move_speed"]), float(DataRegistry.bot("grunt")["move_speed"]))


func test_sniper_shoots_from_range_a_grunt_cannot_see() -> void:
	var far := (float(DataRegistry.bot("grunt")["sight_range_m"]) + float(DataRegistry.bot("sniper")["sight_range_m"])) * 0.5
	await wait_physics_frames(2)
	var sniper := _bot("sniper", Vector3(0, 0, -far))
	_run(sniper, float(sniper.stats["reaction_time_s"]) + 0.5)
	assert_eq(sniper.state, Bot.State.SHOOT, "engages at %.0f m" % far)
	var grunt := _bot("grunt", Vector3(0, 0, -far))
	_run(grunt, float(grunt.stats["reaction_time_s"]) + 0.5)
	assert_eq(grunt.state, Bot.State.WANDER, "grunt cannot see that far")


func test_sniper_backs_off_when_rushed() -> void:
	var keep := float(DataRegistry.bot("sniper")["keep_distance_m"])
	await wait_physics_frames(2)
	var sniper := _bot("sniper", Vector3(0, 0, -keep * 0.4))
	_run(sniper, float(sniper.stats["reaction_time_s"]) + 0.1)
	var before := _flat_distance(sniper)
	_run(sniper, 1.0)
	assert_eq(sniper.state, Bot.State.SHOOT)
	assert_gt(_flat_distance(sniper), before + 0.5, "retreats while shooting")


func test_rusher_strafes_while_shooting() -> void:
	var r := DataRegistry.bot("rusher")
	var close := float(r["sight_range_m"]) * float(r["shoot_range_ratio"]) * 0.8
	await wait_physics_frames(2)
	var rusher := _bot("rusher", Vector3(0, 0, -close))
	_run(rusher, float(rusher.stats["reaction_time_s"]) + 0.1)
	assert_eq(rusher.state, Bot.State.SHOOT)
	var x0 := rusher.global_position.x
	_run(rusher, 0.4)
	assert_gt(absf(rusher.global_position.x - x0), 0.5, "moves sideways")
	assert_almost_eq(_flat_distance(rusher), close, 1.5, "keeps about the same range")


func test_grunt_still_stops_to_shoot() -> void:
	var g := DataRegistry.bot("grunt")
	await wait_physics_frames(2)
	var grunt := _bot("grunt", Vector3(0, 0, -float(g["sight_range_m"]) * 0.5))
	_run(grunt, float(grunt.stats["reaction_time_s"]) + 0.1)
	assert_eq(grunt.state, Bot.State.SHOOT)
	var p0 := grunt.global_position
	_run(grunt, 0.5)
	assert_almost_eq(grunt.global_position.x, p0.x, 0.01)
	assert_almost_eq(grunt.global_position.z, p0.z, 0.01)


func test_entrance_bots_march_on_the_player_out_of_sight() -> void:
	var far := float(DataRegistry.bot("grunt")["sight_range_m"]) * 2.0
	await wait_physics_frames(2)
	var grunt := _bot("grunt", Vector3(0, 0, -far))
	grunt.marching = true
	var before := _flat_distance(grunt)
	_run(grunt, 1.0)
	assert_eq(grunt.state, Bot.State.WANDER, "cannot see yet")
	assert_lt(_flat_distance(grunt), before - 1.0, "but closes in")
	var idle := _bot("grunt", Vector3(0, 0, -far))
	var idle_start := idle.global_position
	_run(idle, 1.0)
	assert_lt(idle.global_position.distance_to(idle_start), 8.5, "non-marching bots just wander near home")
