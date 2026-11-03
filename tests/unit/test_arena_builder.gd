extends GutTest

const ArenaScene := preload("res://shooter/arenas/arena.tscn")

const FIXTURE := {
	"id": "fixture",
	"blocks": [
		{"pos": Vector3(0, -0.5, 0), "size": Vector3(10, 1, 10), "color": "floor"},
		{"pos": Vector3(2, 1, 2), "size": Vector3(2, 2, 2), "color": "crate"},
		{"pos": Vector3(-2, 1, -2), "size": Vector3(2, 2, 2), "color": "crate"},
	],
	"player_spawns": [Vector3(0, 1, 4)],
	"bot_spawns": [Vector3(3, 1, -3), Vector3(-3, 1, 3)],
}


func test_builds_expected_counts_from_fixture() -> void:
	var arena: Node3D = add_child_autofree(ArenaScene.instantiate())
	arena.build(FIXTURE)
	assert_eq(arena.block_count(), 3)
	assert_eq(arena.get_node("Collision").get_child_count(), 3)
	assert_eq(arena.get_node("Blocks").get_child_count(), 2, "meshes merged per colour")
	assert_eq(arena.player_spawns.size(), 1)
	assert_eq(arena.bot_spawns.size(), 2)
	assert_eq(arena.get_node("Collision").collision_layer, Layers.WORLD)


func test_builds_from_arenas_json() -> void:
	var arena_def := DataRegistry.arena("arena_1")
	var arena: Node3D = add_child_autofree(ArenaScene.instantiate())
	arena.build(arena_def)
	assert_eq(arena.block_count(), arena_def["blocks"].size())
	assert_eq(arena.player_spawns.size(), arena_def["player_spawns"].size())
	assert_eq(arena.bot_spawns.size(), arena_def["bot_spawns"].size())


func test_navmesh_is_baked() -> void:
	var arena: Node3D = add_child_autofree(ArenaScene.instantiate())
	arena.build(DataRegistry.arena("arena_1"))
	assert_gt(arena.nav_polygon_count(), 0)


func test_rebuild_replaces_layout() -> void:
	var arena: Node3D = add_child_autofree(ArenaScene.instantiate())
	arena.build(DataRegistry.arena("arena_1"))
	arena.build(FIXTURE)
	assert_eq(arena.block_count(), 3)
	assert_eq(arena.bot_spawns.size(), 2)
