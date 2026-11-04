class_name RoundController
extends Node
## Round state machine: freeze -> live -> summary -> freeze. Durations come from
## economy.json "round". Time is injected through advance(delta) so tests can
## drive it; _process forwards the real frame delta.
##
## Bots are not owned here: the controller asks for a wave at live start via
## spawn_wave_requested, then one replacement per kill via spawn_bots_requested
## (trickle, D62); the composition root (Main) does the spawning.

signal spawn_wave_requested(count: int, bot_types: Array)
## Trickle (D62): a killed bot is replaced after round.respawn_delay_s.
signal spawn_bots_requested(count: int)
signal clear_bots_requested()
## Player should be placed at a spawn point and re-enabled.
signal respawn_requested()

var tracker: MatchTracker
var arena_id := ""
var state: StringName = &""
var round_number := 0
var time_left := 0.0
var bots_alive := 0
var wave_size := 0
var wave_types: Array = []
var _respawn_in := -1.0
## Seconds left on each pending bot replacement (trickle).
var _replacements: Array[float] = []
var running := false


func _ready() -> void:
	EventBus.bot_killed.connect(_on_bot_killed)
	EventBus.player_died.connect(_on_player_died)


func start(arena: String = "") -> void:
	arena_id = arena if arena != "" else DataRegistry.first_arena_id()
	var def := DataRegistry.arena(arena_id)
	wave_size = _current_wave_size()
	wave_types = def.get("bot_types", [])
	if tracker:
		tracker.arena_id = arena_id
	round_number = 0
	running = true
	_enter(EventBus.ROUND_FREEZE)


func _process(delta: float) -> void:
	if running:
		advance(delta)


func advance(delta: float) -> void:
	if not running:
		return
	if _respawn_in >= 0.0:
		_respawn_in -= delta
		if _respawn_in < 0.0:
			respawn_requested.emit()
	if tracker:
		tracker.tick(delta if state == EventBus.ROUND_LIVE else 0.0)
	if state == EventBus.ROUND_LIVE:
		_tick_trickle(delta)
	time_left -= delta
	if time_left > 0.0:
		return
	match state:
		EventBus.ROUND_FREEZE:
			_enter(EventBus.ROUND_LIVE)
		EventBus.ROUND_LIVE:
			_enter(EventBus.ROUND_SUMMARY)
		EventBus.ROUND_SUMMARY:
			_enter(EventBus.ROUND_FREEZE)


func is_freeze() -> bool:
	return state == EventBus.ROUND_FREEZE


func is_live() -> bool:
	return state == EventBus.ROUND_LIVE


func _duration_for(s: StringName) -> float:
	var r: Dictionary = DataRegistry.economy()["round"]
	match s:
		EventBus.ROUND_FREEZE: return float(r["freeze_time_s"])
		EventBus.ROUND_LIVE: return float(r["live_time_s"])
	return float(r["summary_time_s"])


func _enter(s: StringName) -> void:
	state = s
	time_left = _duration_for(s)
	match s:
		EventBus.ROUND_FREEZE:
			round_number += 1
			bots_alive = 0
			clear_bots_requested.emit()
			if tracker:
				tracker.start_round(round_number)
		EventBus.ROUND_LIVE:
			_spawn_wave()
		EventBus.ROUND_SUMMARY:
			clear_bots_requested.emit()
			bots_alive = 0
			if tracker:
				EventBus.round_summary.emit(tracker.end_round())
	EventBus.round_state_changed.emit(s, {"round": round_number, "duration": time_left})


## Re-read every wave so Server Slots bought mid-game count from the next wave on.
func _current_wave_size() -> int:
	return int(DataRegistry.arena(arena_id).get("bots_per_wave", 0)) + CheatSystem.extra_bots()


func _spawn_wave() -> void:
	wave_size = _current_wave_size()
	bots_alive = wave_size
	spawn_wave_requested.emit(wave_size, wave_types)


func _on_bot_killed(_bot: Node, _info: Dictionary) -> void:
	if state != EventBus.ROUND_LIVE:
		return
	bots_alive = maxi(bots_alive - 1, 0)
	_replacements.append(float(DataRegistry.economy()["round"].get("respawn_delay_s", 0.0)))


## Counts down replacements and tops the arena back up to the wave size (also
## when Server Slots grow it mid-round). Live state only.
func _tick_trickle(delta: float) -> void:
	var due := 0
	for i in range(_replacements.size() - 1, -1, -1):
		_replacements[i] -= delta
		if _replacements[i] <= 0.0:
			_replacements.remove_at(i)
			due += 1
	wave_size = _current_wave_size()
	due += maxi(0, wave_size - bots_alive - due - _replacements.size())
	if due > 0:
		bots_alive += due
		spawn_bots_requested.emit(due)


func _on_player_died(_info: Dictionary) -> void:
	_respawn_in = float(DataRegistry.player().get("respawn_delay_s", 0.0))
