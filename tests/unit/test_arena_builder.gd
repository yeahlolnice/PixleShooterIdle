extends GutTest

const ArenaScene := preload("res://shooter/arenas/arena.tscn")


func test_builds_blocks_and_spawns_from_data() -> void:
	var arena_def := DataRegistry.arena("arena_1")
	var arena: Node3D = add_child_autofree(ArenaScene.instantiate())
	arena.build(arena_def)
	assert_eq(arena.block_count(), arena_def["blocks"].size())
	assert_eq(arena.get_node("Collision").get_child_count(), arena_def["blocks"].size())
	assert_eq(arena.player_spawns.size(), arena_def["player_spawns"].size())
	assert_eq(arena.bot_spawns.size(), arena_def["bot_spawns"].size())
	assert_eq(arena.get_node("Collision").collision_layer, Layers.WORLD)
