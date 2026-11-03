extends Node3D
## Composition root: builds the arena from data, places the player, and later
## hosts the round controller, bot spawner and UI layers. The only script that
## is allowed to know about every module.

## Arena to load; empty = the first arena in progression order.
@export var arena_id := ""
## Load user://save.json on start and autosave. Tests that instantiate this
## scene turn it off so they never touch the player's real save.
@export var use_save_file := true

## --dev-cash grants (debug only; not balance data): enough for the first few cheat levels and
## unlocks Speed Hack, Infinite Ammo, Auto Bhop and Wallhack.
const DEV_CASH := 50000.0
const DEV_LIFETIME_KILLS := 400

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var ui_layer: CanvasLayer = $UI

var tracker: MatchTracker
var rounds: RoundController
var spawner: BotSpawner


func _enter_tree() -> void:
	# Before children's _ready, so WeaponManager equips the saved gun.
	# --dev-cash (after `--`): QA shortcut, see DECISIONS D42. Never touches the save file.
	if use_save_file and "--dev-cash" in OS.get_cmdline_user_args():
		use_save_file = false
		GameState.new_game()
		GameState.cash = DEV_CASH
		GameState.lifetime_kills = DEV_LIFETIME_KILLS
		CheatSystem.refresh_unlocks(false)
	if use_save_file and not GameState.persistence_enabled:
		GameState.enable_persistence()


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
	var loot := LootDropper.new()
	loot.name = "LootDropper"
	loot.tracker = tracker
	loot.container = spawner   # _clear_bots frees leftover loot with the bots
	add_child(loot)
	ui_layer.add_child(load("res://ui/hud/hud.tscn").instantiate())
	var buy_menu: BuyMenu = load("res://ui/buy_menu/buy_menu.tscn").instantiate()
	buy_menu.weapon_manager = player.get_node_or_null("WeaponManager")
	ui_layer.add_child(buy_menu)
	ui_layer.add_child(load("res://ui/chat/chat_box.tscn").instantiate())
	ui_layer.add_child(load("res://ui/mod_menu/mod_menu.tscn").instantiate())
	rounds.start(id)


func _respawn_player() -> void:
	if not arena.player_spawns.is_empty():
		player.global_position = arena.player_spawns[randi() % arena.player_spawns.size()]
	EventBus.player_spawned.emit(player)


func _spawn_wave(count: int, _bot_types: Array) -> void:
	# Spawner sizes the wave from arenas.json + extra slots; keep it in step with the controller.
	spawner.spawn_wave(rounds.arena_id, count - int(DataRegistry.arena(rounds.arena_id).get("bots_per_wave", 0)))


## Frees bots, tracers, pop debris and leftover loot (all parented to the spawner).
func _clear_bots() -> void:
	for bot in spawner.get_children():
		bot.queue_free()
	spawner.reset_alive()
