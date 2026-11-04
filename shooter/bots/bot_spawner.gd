class_name BotSpawner
extends Node3D
## Spawns bots for an arena. Wave size = arenas.json bots_per_wave + extra_slots
## (Server Slots). Types cycle through the arena's bot_types across the whole
## round (waves and trickle replacements share the rotation).
##
## Where a bot appears (fun pack, D62):
##   - snipers, or arenas without "entrances": at bot_spawns (cycling), at once
##   - everyone else: queued at an arenas.json entrance (round-robin) and let in
##     one at a time per entrance every column_gap_s, marching toward the player
##     on the navmesh, so they arrive in columns you can line up.

signal wave_spawned(count: int)
signal wave_cleared

const BotScene := preload("res://shooter/bots/bot.tscn")
const DEFAULT_COLUMN_GAP_S := 0.6

var target: Node3D = null    ## what bots hunt; a stub Node3D works
var extra_slots := 0         ## set by the Server Slots upgrade later
var _alive := 0
var _arena_id := ""
var _type_index := 0
var _spawn_index := 0
var _entrance_index := 0
## Bots waiting at an entrance: [{"type": String, "entrance": int}]
var _queue: Array = []
var _gap_left: Dictionary = {}   ## entrance index -> seconds until the next one may enter


func _ready() -> void:
	EventBus.bot_killed.connect(_on_bot_killed)


## Number of bots a wave will contain for an arena.
static func wave_size(arena_def: Dictionary, p_extra_slots: int = 0) -> int:
	return maxi(0, int(arena_def.get("bots_per_wave", 0)) + p_extra_slots)


## Starts a wave. Returns the bots spawned right away (snipers / no-entrance
## arenas); the rest arrive through entrances (see pending_count()).
## `p_extra_slots` overrides the extra_slots property.
func spawn_wave(arena_id: String, p_extra_slots: int = -1) -> Array[Bot]:
	var arena_def := DataRegistry.arena(arena_id)
	var count := wave_size(arena_def, extra_slots if p_extra_slots < 0 else p_extra_slots)
	var bots := spawn_more(arena_id, count)
	wave_spawned.emit(count)
	return bots


## Adds `count` bots (trickle replacements use this). Returns those spawned now.
func spawn_more(arena_id: String, count: int) -> Array[Bot]:
	var arena_def := DataRegistry.arena(arena_id)
	var types: Array = arena_def.get("bot_types", [])
	var bots: Array[Bot] = []
	if types.is_empty():
		return bots
	_arena_id = arena_id
	var entrances: Array = arena_def.get("entrances", [])
	for i in count:
		var type: String = types[_type_index % types.size()]
		_type_index += 1
		if entrances.is_empty() or DataRegistry.bot(type).get("behaviour", "grunt") == "sniper":
			var bot := _spawn_at_spawn_point(arena_def, type)
			if bot:
				bots.append(bot)
		else:
			_queue.append({"type": type, "entrance": _entrance_index % entrances.size()})
			_entrance_index += 1
	return bots


## Bots still waiting at entrances.
func pending_count() -> int:
	return _queue.size()


## Lets every queued bot in at once (tests, or callers that cannot wait).
func flush_queue() -> Array[Bot]:
	var out: Array[Bot] = []
	while not _queue.is_empty():
		out.append(_admit(_queue.pop_front()))
	return out


func _process(delta: float) -> void:
	tick(delta)


## Lets in at most one queued bot per entrance per column_gap_s. Split out for tests.
func tick(delta: float) -> void:
	for e in _gap_left:
		_gap_left[e] = float(_gap_left[e]) - delta
	if _queue.is_empty():
		return
	var gap := float(DataRegistry.arena(_arena_id).get("column_gap_s", DEFAULT_COLUMN_GAP_S))
	var used := {}
	var i := 0
	while i < _queue.size():
		var entry: Dictionary = _queue[i]
		var e := int(entry["entrance"])
		if used.has(e) or float(_gap_left.get(e, 0.0)) > 0.0:
			i += 1
			continue
		_queue.remove_at(i)
		used[e] = true
		_gap_left[e] = gap
		_admit(entry)


func _admit(entry: Dictionary) -> Bot:
	var entrances: Array = DataRegistry.arena(_arena_id).get("entrances", [])
	var pos: Vector3 = entrances[int(entry["entrance"]) % entrances.size()]
	var bot := _make(String(entry["type"]), pos)
	bot.marching = true
	return bot


func _spawn_at_spawn_point(arena_def: Dictionary, type: String) -> Bot:
	var spawns: Array = arena_def.get("bot_spawns", [])
	if spawns.is_empty():
		return null
	var pos: Vector3 = spawns[_spawn_index % spawns.size()]
	_spawn_index += 1
	return _make(type, pos)


func _make(type: String, pos: Vector3) -> Bot:
	var bot: Bot = BotScene.instantiate()
	bot.configure(type, _arena_id, target)
	add_child(bot)
	bot.global_position = pos
	bot._home = bot.global_position  # _ready ran at the spawner origin
	_alive += 1
	return bot


func alive_count() -> int:
	return _alive


func _on_bot_killed(bot: Node, _info: Dictionary) -> void:
	if bot == null or bot.get_parent() != self:
		return
	_alive = maxi(0, _alive - 1)
	if _alive == 0 and _queue.is_empty():
		wave_cleared.emit()


## Forget remaining bots and the entrance queue (the caller frees the bots), e.g. at round end.
func reset_alive() -> void:
	_alive = 0
	_queue.clear()
	_gap_left.clear()
