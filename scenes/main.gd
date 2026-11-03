extends Node3D
## Composition root: builds the arena from data, places the player, and later
## hosts the round controller, bot spawner and UI layers. The only script that
## is allowed to know about every module.

## Arena to load; empty = the first arena in progression order.
@export var arena_id := ""

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var ui_layer: CanvasLayer = $UI

var tracker: MatchTracker
var rounds: RoundController
var spawner: BotSpawner


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

	tracker = MatchTracker.new()
	tracker.name = "MatchTracker"
	add_child(tracker)
	rounds = RoundController.new()
	rounds.name = "RoundController"
	rounds.tracker = tracker
	add_child(rounds)
	rounds.respawn_requested.connect(_respawn_player)
	spawner = BotSpawner.new()
	spawner.name = "BotSpawner"
	spawner.target = player
	add_child(spawner)
	rounds.spawn_wave_requested.connect(_spawn_wave)
	rounds.clear_bots_requested.connect(_clear_bots)
	ui_layer.add_child(load("res://ui/hud/hud.tscn").instantiate())
	var buy_menu: BuyMenu = load("res://ui/buy_menu/buy_menu.tscn").instantiate()
	buy_menu.weapon_manager = player.get_node_or_null("WeaponManager")
	ui_layer.add_child(buy_menu)
	rounds.start(id)


func _respawn_player() -> void:
	if not arena.player_spawns.is_empty():
		player.global_position = arena.player_spawns[randi() % arena.player_spawns.size()]
	EventBus.player_spawned.emit(player)


func _spawn_wave(count: int, _bot_types: Array) -> void:
	# Spawner sizes the wave from arenas.json + extra slots; keep it in step with the controller.
	spawner.spawn_wave(rounds.arena_id, count - int(DataRegistry.arena(rounds.arena_id).get("bots_per_wave", 0)))


func _clear_bots() -> void:
	for bot in spawner.get_children():
		bot.queue_free()
	spawner.reset_alive()
