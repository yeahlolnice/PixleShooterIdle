extends Node3D
## Composition root: builds the arena from data, places the player, and later
## hosts the round controller, bot spawner and UI layers. The only script that
## is allowed to know about every module.

## Arena to load; empty = the first arena in progression order.
@export var arena_id := ""
## Load user://save.json on start and autosave. Tests that instantiate this
## scene turn it off so they never touch the player's real save.
@export var use_save_file := true

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var ui_layer: CanvasLayer = $UI

var tracker: MatchTracker
var rounds: RoundController
var spawner: BotSpawner


func _enter_tree() -> void:
	# Before children's _ready, so WeaponManager equips the saved gun.
	# --dev-cash / --dev-unlock-all (after `--`, dev tools only): QA shortcuts, see
	# core/dev_flags.gd and DECISIONS D42/D50/D52. Never touch the save file.
	if use_save_file and DevFlags.apply(OS.get_cmdline_user_args(), DevFlags.dev_tools_enabled()):
		use_save_file = false
	if use_save_file and not GameState.persistence_enabled:
		GameState.enable_persistence()


func _ready() -> void:
	if not DataRegistry.is_valid():
		push_error("[Main] data errors, see log above; the game may misbehave")
	var id := arena_id if arena_id != "" else ArenaService.selected_id()
	_build_arena(id)

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
	rounds.spawn_bots_requested.connect(func(n): spawner.spawn_more(rounds.arena_id, n))
	rounds.clear_bots_requested.connect(_clear_bots)
	var loot := LootDropper.new()
	loot.name = "LootDropper"
	loot.tracker = tracker
	loot.container = spawner   # _clear_bots frees leftover loot with the bots
	add_child(loot)
	var fx := HitFx.new()
	fx.name = "HitFx"
	add_child(fx)
	var sfx := SfxPlayer.new()
	sfx.name = "Sfx"
	add_child(sfx)
	ui_layer.add_child(load("res://ui/hud/hud.tscn").instantiate())
	# Chat before the menus so open menus draw on top of it.
	ui_layer.add_child(load("res://ui/chat/chat_box.tscn").instantiate())
	var buy_menu: BuyMenu = load("res://ui/buy_menu/buy_menu.tscn").instantiate()
	buy_menu.weapon_manager = player.get_node_or_null("WeaponManager")
	ui_layer.add_child(buy_menu)
	ui_layer.add_child(load("res://ui/mod_menu/mod_menu.tscn").instantiate())
	ui_layer.add_child(load("res://ui/pause_menu/pause_menu.tscn").instantiate())
	EventBus.arena_selected.connect(switch_arena)
	EventBus.kills_changed.connect(_on_kills_changed)
	rounds.start(id)


## Builds `id`'s blocks, sky and navmesh and puts the player on its first spawn.
func _build_arena(id: String) -> void:
	var arena_def := DataRegistry.arena(id)
	arena.build(arena_def)
	world_env.environment.background_color = DataRegistry.color(arena_def.get("sky_color", "sky"))
	if not arena.player_spawns.is_empty():
		player.spawn_points = arena.player_spawns
		player.global_position = arena.player_spawns[0]
		player.velocity = Vector3.ZERO
	print("[Main] arena '%s' built: %d blocks, %d bot spawns, %d navmesh polygons" % [id, arena.block_count(), arena.bot_spawns.size(), arena.nav_polygon_count()])
	EventBus.player_spawned.emit(player)


## ArenaService picked another arena: clear the wave, rebuild, restart at freeze time.
func switch_arena(id: String) -> void:
	if rounds == null or id == rounds.arena_id or DataRegistry.arena(id).is_empty():
		return
	_clear_bots()
	_build_arena(id)
	rounds.start(id)


## Tells chat when this kill crossed an arena's unlock threshold.
func _on_kills_changed(_kills: int, lifetime: int) -> void:
	for id in ArenaService.unlocked_at(lifetime):
		var a := DataRegistry.arena(id)
		EventBus.emit_chat_event(&"arena_unlocked", {"arena_id": id, "arena_name": a.get("name", id), "cash_mult": a.get("cash_mult", 1)})


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
