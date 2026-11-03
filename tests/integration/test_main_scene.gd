extends GutTest
## Smoke: the main scene loads, builds the arena and places the player.

func test_main_scene_boots() -> void:
	var main: Node3D = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(5)
	var arena: Node3D = main.get_node("Arena")
	assert_gt(arena.block_count(), 0)
	var player: Node3D = main.get_node("Player")
	var spawn: Vector3 = arena.player_spawns[0]
	assert_almost_eq(player.global_position.x, spawn.x, 0.01)
	assert_almost_eq(player.global_position.z, spawn.z, 0.01)
	assert_gt(arena.nav_polygon_count(), 0)
	assert_not_null(player.get_node("Head/Camera3D/WeaponMount"))
