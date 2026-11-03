extends GutTest
## Wallhack: range per level (from data/cheats.json), range selection for given
## positions, health-bar level gate, and outline/bar on real bots in a scene.

const BotScene := preload("res://shooter/bots/bot.tscn")


class FakeBot:
	extends Node3D
	var dead := false

	func is_dead() -> bool:
		return dead


var _wh: Wallhack
var _def: Dictionary


func before_each() -> void:
	_def = DataRegistry.cheat("wallhack")
	_wh = CheatBase.from_def(_def, DataRegistry.cheat_cost_growth()) as Wallhack


func _effect(key: String) -> Dictionary:
	for e in _def["effects"]:
		if e["key"] == key:
			return e
	return {}


func _max_level() -> int:
	return int(_def["max_level"])


func _whole_map_level() -> int:
	return int(_effect("whole_map")["from_level"])


func _bars_level() -> int:
	return int(_effect("health_bars")["from_level"])


# --- Data / wiring ----------------------------------------------------------------

func test_cheats_json_builds_wallhack_subclass() -> void:
	assert_not_null(_wh, "cheats.json 'script' makes wallhack a Wallhack")
	assert_true(CheatSystem.get_cheat("wallhack") is Wallhack)


func test_range_level_1_is_data_value() -> void:
	assert_almost_eq(_wh.range_at(1), float(_effect("radius_m")["from"]), 0.001)


func test_range_not_owned_is_zero() -> void:
	assert_eq(_wh.range_at(0), 0.0)


func test_range_grows_each_level_then_whole_map() -> void:
	var prev := 0.0
	for lvl in range(1, _whole_map_level()):
		var r := _wh.range_at(lvl)
		assert_gt(r, prev, "range grows at level %d" % lvl)
		assert_false(is_inf(r))
		prev = r
	assert_true(is_inf(_wh.range_at(_whole_map_level())), "whole map from its data level")
	assert_true(is_inf(_wh.range_at(_max_level())), "whole map at max level")


func test_health_bars_only_from_data_level() -> void:
	assert_false(_wh.health_bars_at(0))
	assert_false(_wh.health_bars_at(_bars_level() - 1))
	assert_true(_wh.health_bars_at(_bars_level()))
	assert_true(_wh.health_bars_at(_max_level()))


# --- Range selection ------------------------------------------------------------

func test_select_in_range_level_1() -> void:
	var r := _wh.range_at(1)
	var origin := Vector3(2, 0, -3)
	var positions := [
		origin + Vector3(r * 0.5, 0, 0),          # in
		origin + Vector3(0, 0, -(r - 0.01)),      # just in
		origin + Vector3(r + 0.01, 0, 0),         # just out
		origin + Vector3(0, 1.0, r * 3.0),        # far out
		origin,                                   # on top of the player
	]
	assert_eq(Wallhack.select_in_range(origin, positions, r), PackedInt32Array([0, 1, 4]))


func test_select_in_range_uses_3d_distance() -> void:
	var positions := [Vector3(6, 6, 6), Vector3(5, 5, 0)]
	# |(6,6,6)| = 10.39, |(5,5,0)| = 7.07
	assert_eq(Wallhack.select_in_range(Vector3.ZERO, positions, 10.0), PackedInt32Array([1]))


func test_select_in_range_whole_map_picks_everything() -> void:
	var positions := [Vector3(1e5, 0, 0), Vector3(-3, 0, 2), Vector3(0, -500, 0)]
	var r := _wh.range_at(_max_level())
	assert_eq(Wallhack.select_in_range(Vector3.ZERO, positions, r), PackedInt32Array([0, 1, 2]))


func test_select_in_range_zero_radius_picks_nothing() -> void:
	assert_eq(Wallhack.select_in_range(Vector3.ZERO, [Vector3.ZERO, Vector3.ONE], 0.0).size(), 0)


func test_mid_level_range_selection() -> void:
	var lvl := 5
	var r := _wh.range_at(lvl)
	assert_gt(r, _wh.range_at(1))
	var positions := [Vector3(_wh.range_at(1) + 1.0, 0, 0), Vector3(r - 0.5, 0, 0), Vector3(r + 0.5, 0, 0)]
	assert_eq(Wallhack.select_in_range(Vector3.ZERO, positions, r), PackedInt32Array([0, 1]),
		"level %d (%.1f m) reaches past the level-1 range" % [lvl, r])


func test_select_bots_skips_dead_and_freed() -> void:
	var near := FakeBot.new()
	var dead := FakeBot.new()
	var far := FakeBot.new()
	for b in [near, dead, far]:
		add_child_autofree(b)
	near.global_position = Vector3(3, 0, 0)
	dead.global_position = Vector3(2, 0, 0)
	dead.dead = true
	far.global_position = Vector3(50, 0, 0)
	var gone := FakeBot.new()
	gone.free()
	assert_eq(_wh.select_bots(Vector3.ZERO, [near, dead, far, gone], 1), [near])


# --- In scene ---------------------------------------------------------------------

func _outlined(bot: Node) -> bool:
	var meshes := bot.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0)
	for mi in meshes:
		var mat: Material = (mi as MeshInstance3D).material_override
		if mat == null or mat.next_pass == null:
			return false
		if (mat.next_pass as ShaderMaterial).shader.resource_path != "res://shaders/wallhack_outline.gdshader":
			return false
	return true


func _spawn_bot(world: Node3D, pos: Vector3) -> Bot:
	var bot: Bot = BotScene.instantiate()
	bot.configure("grunt", DataRegistry.first_arena_id())
	world.add_child(bot)
	bot.global_position = pos
	bot.set_physics_process(false)   # keep them still; range is what is tested
	return bot


func test_scene_outline_in_range_only_and_removed_on_toggle_off() -> void:
	var world: Node3D = add_child_autofree(Node3D.new())
	var player := Node3D.new()
	world.add_child(player)
	var r := _wh.range_at(1)
	var near := _spawn_bot(world, Vector3(0, 0, -r * 0.5))
	var far := _spawn_bot(world, Vector3(0, 0, -r * 2.0))
	_wh.apply(player, 1)
	var scanner := player.get_node(Wallhack.SCANNER_NAME)
	assert_not_null(scanner)
	assert_true(_outlined(near), "bot in range is outlined")
	assert_false(_outlined(far), "bot out of range is not")
	assert_null(near.get_node_or_null(Wallhack.HEALTH_BAR_NAME), "no bars at level 1")

	# Bot walks into range: picked up on the next timer scan.
	far.global_position = Vector3(0, 0, -r * 0.9)
	await wait_seconds(Wallhack.SCAN_INTERVAL_S * 2.0)
	assert_true(_outlined(far), "outline added by the timer scan")

	# Upgrading reuses the scanner.
	_wh.apply(player, _bars_level())
	assert_eq(player.get_children().filter(func(c): return c.name == Wallhack.SCANNER_NAME).size(), 1)
	assert_not_null(near.get_node_or_null(Wallhack.HEALTH_BAR_NAME), "bars from the data level")

	_wh.remove(player)
	assert_null(player.get_node_or_null(Wallhack.SCANNER_NAME))
	assert_false(_outlined(near))
	assert_false(_outlined(far))
	assert_null(near.get_node_or_null(Wallhack.HEALTH_BAR_NAME), "bars removed with the cheat")


# Round end frees every bot while the scanner still remembers them; the next
# timer scan used to hit "assign invalid previously freed instance" and crash.
func test_scan_after_outlined_bots_are_freed() -> void:
	var world: Node3D = add_child_autofree(Node3D.new())
	var player := Node3D.new()
	world.add_child(player)
	var gone := _spawn_bot(world, Vector3(0, 0, -1))
	var dying := _spawn_bot(world, Vector3(0, 0, 1))
	_wh.apply(player, 1)
	var scanner: Wallhack.Scanner = player.get_node(Wallhack.SCANNER_NAME)
	assert_eq(scanner.outlined_bots().size(), 2)
	gone.free()
	dying.queue_free()
	scanner.scan()
	assert_eq(scanner.outlined_bots().size(), 0, "freed and queued-for-deletion bots dropped")
	_wh.remove(player)


func test_scene_health_bar_tracks_damage() -> void:
	var world: Node3D = add_child_autofree(Node3D.new())
	var player := Node3D.new()
	world.add_child(player)
	var bot := _spawn_bot(world, Vector3(3, 0, 0))
	_wh.apply(player, _bars_level())
	var fill: Sprite3D = bot.get_node(Wallhack.HEALTH_BAR_NAME + "/Fill")
	var full_w := fill.region_rect.size.x
	bot.take_hit("body", bot.health * 0.5)
	assert_almost_eq(fill.region_rect.size.x, full_w * 0.5, 0.01, "bar halves with health")
	_wh.remove(player)
