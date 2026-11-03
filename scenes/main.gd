extends Node3D
## Composition root: builds the arena from data, places the player, and later
## hosts the round controller, bot spawner and UI layers. The only script that
## is allowed to know about every module.

## Arena to load; empty = the first arena in progression order.
@export var arena_id := ""

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var world_env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	if not DataRegistry.is_valid():
		push_error("[Main] data errors, see log above; the game may misbehave")
	var id := arena_id if arena_id != "" else DataRegistry.first_arena_id()
	var arena_def := DataRegistry.arena(id)
	arena.build(arena_def)
	world_env.environment.background_color = DataRegistry.color(arena_def.get("sky_color", "sky"))
	if not arena.player_spawns.is_empty():
		player.spawn_points = arena.player_spawns
		player.global_position = arena.player_spawns[0]
	print("[Main] arena '%s' built: %d blocks, %d bot spawns, %d navmesh polygons" % [id, arena.block_count(), arena.bot_spawns.size(), arena.nav_polygon_count()])
	EventBus.player_spawned.emit(player)
