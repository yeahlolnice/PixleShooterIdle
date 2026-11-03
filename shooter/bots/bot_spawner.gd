class_name BotSpawner
extends Node3D
## Spawns a wave of bots at an arena's bot spawn points.
## Wave size = arenas.json bots_per_wave + extra_slots (the Server Slots upgrade hook).

signal wave_spawned(count: int)
signal wave_cleared

const BotScene := preload("res://shooter/bots/bot.tscn")

var target: Node3D = null    ## what bots hunt; a stub Node3D works
var extra_slots := 0         ## set by the Server Slots upgrade later
var _alive := 0


func _ready() -> void:
	EventBus.bot_killed.connect(_on_bot_killed)


## Number of bots a wave will contain for an arena.
static func wave_size(arena_def: Dictionary, p_extra_slots: int = 0) -> int:
	return maxi(0, int(arena_def.get("bots_per_wave", 0)) + p_extra_slots)


## Spawns the wave and returns the bots. `p_extra_slots` overrides the extra_slots property.
## Bots cycle through the spawn points and the arena's bot_types.
func spawn_wave(arena_id: String, p_extra_slots: int = -1) -> Array[Bot]:
	var arena_def := DataRegistry.arena(arena_id)
	var spawns: Array = arena_def.get("bot_spawns", [])
	var types: Array = arena_def.get("bot_types", [])
	var count := wave_size(arena_def, extra_slots if p_extra_slots < 0 else p_extra_slots)
	var bots: Array[Bot] = []
	if spawns.is_empty() or types.is_empty():
		return bots
	for i in count:
		var bot: Bot = BotScene.instantiate()
		bot.configure(types[i % types.size()], arena_id, target)
		add_child(bot)
		bot.global_position = spawns[i % spawns.size()]
		bots.append(bot)
	_alive += bots.size()
	wave_spawned.emit(bots.size())
	return bots


func alive_count() -> int:
	return _alive


func _on_bot_killed(bot: Node, _info: Dictionary) -> void:
	if bot.get_parent() != self:
		return
	_alive = maxi(0, _alive - 1)
	if _alive == 0:
		wave_cleared.emit()
