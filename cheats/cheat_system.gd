extends Node
## Autoload "CheatSystem": owns the 12 cheats and the mod-menu upgrades (Server
## Slots) built from data/cheats.json, and is the only code that changes
## GameState.cheat_levels / cheat_enabled / server_slots.
##
## UI (mod menu) usage:
##   for c in CheatSystem.cheats(): row(c.id, c.display_name, c.tab, CheatSystem.level(c.id), ...)
##   CheatSystem.is_unlocked(id) / CheatSystem.next_cost(id) / CheatSystem.can_purchase(id)
##   CheatSystem.purchase(id)        # buy level 1 or upgrade; false if locked, maxed or too poor
##   CheatSystem.toggle(id)          # owned cheats only
## Gameplay usage (cheats with "cheat"/"game" effects):
##   CheatSystem.effect("aimbot", "fov_deg")   # neutral (0/false) unless owned and enabled
##   CheatSystem.any_cheat_active()            # legit-mode bonus check
##
## Signals (EventBus): cheat_purchased(id, level) on every buy/upgrade;
## cheat_toggled(id, enabled) on every switch, including the automatic switch-on
## at first purchase; cheat_unlocked(id) when a kill/prestige threshold is crossed.
##
## Owned and enabled cheats are applied to the player on player_spawned, again
## on gun_equipped (a new Weapon starts with neutral modifiers) and after a save
## is loaded. Unlocks use lifetime kills, so a ban never re-locks a kill cheat.

## The upgrade whose level is stored in GameState.server_slots.
const SERVER_SLOTS_ID := "server_slots"
## GameState.chat_flags key: the free trial already ran for this save.
const FREE_TRIAL_FLAG := "free_trial_used"

var _cheats: Array[CheatBase] = []
var _upgrades: Array[CheatBase] = []
var _by_id: Dictionary = {}
var _unlocked: Dictionary = {}
var _player: Object = null
## Free trials (fun pack, D64): cheat_id -> {"level": int, "left": seconds}. Not saved.
var _trials: Dictionary = {}


func _ready() -> void:
	load_from_data()
	EventBus.player_spawned.connect(set_player)
	EventBus.gun_equipped.connect(func(_gun_id): reapply())
	EventBus.kills_changed.connect(func(_kills, _lifetime): refresh_unlocks())
	EventBus.game_state_loaded.connect(_on_game_state_loaded)
	EventBus.round_state_changed.connect(_on_round_state)


## (Re)builds every cheat from DataRegistry. Unlock state is recomputed silently.
func load_from_data() -> void:
	_cheats.clear()
	_upgrades.clear()
	_by_id.clear()
	var growth := DataRegistry.cheat_cost_growth()
	for def in DataRegistry.cheats():
		var cheat := CheatBase.from_def(def, growth)
		_cheats.append(cheat)
		_by_id[cheat.id] = cheat
	for def in DataRegistry.cheat_upgrades():
		var upgrade := CheatBase.from_def(def, growth)
		_upgrades.append(upgrade)
		_by_id[upgrade.id] = upgrade
	refresh_unlocks(false)


# --- Queries ---------------------------------------------------------------------

## The 12 cheats in ladder order.
func cheats() -> Array[CheatBase]:
	return _cheats


## Mod-menu upgrades (Server Slots) in order.
func upgrades() -> Array[CheatBase]:
	return _upgrades


## Cheat or upgrade by id, or null.
func get_cheat(id: String) -> CheatBase:
	return _by_id.get(id)


func is_upgrade(id: String) -> bool:
	return _upgrades.has(get_cheat(id))


func level(id: String) -> int:
	if id == SERVER_SLOTS_ID:
		return GameState.server_slots
	return int(GameState.cheat_levels.get(id, 0))


func is_owned(id: String) -> bool:
	return level(id) > 0


## Upgrades are always "on" once owned; cheats follow their switch. A running
## free trial counts as on.
func is_enabled(id: String) -> bool:
	if trial_left(id) > 0.0:
		return true
	if not is_owned(id):
		return false
	if is_upgrade(id):
		return true
	return bool(GameState.cheat_enabled.get(id, true))


func is_unlocked(id: String) -> bool:
	var cheat := get_cheat(id)
	return cheat != null and cheat.is_unlocked_for(GameState.lifetime_kills, GameState.prestige_count)


func is_maxed(id: String) -> bool:
	var cheat := get_cheat(id)
	return cheat != null and cheat.is_maxed(level(id))


## Price of the next level (first purchase when not owned).
func next_cost(id: String) -> float:
	var cheat := get_cheat(id)
	return cheat.cost(level(id)) if cheat else INF


func can_purchase(id: String) -> bool:
	return get_cheat(id) != null and is_unlocked(id) and not is_maxed(id) and GameState.can_afford(next_cost(id))


## True while at least one owned cheat is switched on (upgrades do not count).
func any_cheat_active() -> bool:
	for cheat in _cheats:
		if is_enabled(cheat.id):
			return true
	return false


## Current value of an effect: the owned level's value while enabled, otherwise neutral.
func effect(id: String, key: String) -> Variant:
	var cheat := get_cheat(id)
	if cheat == null:
		return null
	return cheat.value_at(key, effective_level(id) if is_enabled(id) else 0)


## Extra bots per wave from the Server Slots upgrade.
func extra_bots() -> int:
	var value: Variant = effect(SERVER_SLOTS_ID, "extra_bots")
	return roundi(float(value)) if value != null else 0


# --- Actions ---------------------------------------------------------------------

## Buys the first level or upgrades one level. Returns false and changes nothing
## when the cheat is unknown, locked, maxed or unaffordable.
func purchase(id: String) -> bool:
	if not can_purchase(id):
		return false
	if not GameState.try_spend(next_cost(id)):
		return false
	var new_level := level(id) + 1
	var first := new_level == 1
	if id == SERVER_SLOTS_ID:
		GameState.server_slots = new_level
	else:
		GameState.cheat_levels[id] = new_level
	if first and not is_upgrade(id):
		GameState.cheat_enabled[id] = true
	EventBus.cheat_purchased.emit(id, new_level)
	if is_enabled(id):
		_apply(get_cheat(id))
	if first and not is_upgrade(id):
		EventBus.cheat_toggled.emit(id, true)
	return true


## Switches an owned cheat on or off: apply() or remove() on the current player.
## Returns false for unowned cheats and upgrades. No signal when nothing changes.
func set_enabled(id: String, on: bool) -> bool:
	if is_upgrade(id) or not is_owned(id):
		return false
	if is_enabled(id) == on:
		return true
	GameState.cheat_enabled[id] = on
	if on:
		_apply(get_cheat(id))
	else:
		_remove(get_cheat(id))
	EventBus.cheat_toggled.emit(id, on)
	return true


func toggle(id: String) -> bool:
	return set_enabled(id, not is_enabled(id))


# --- Player binding --------------------------------------------------------------

## Binds the player (normally via EventBus.player_spawned) and applies every
## owned, enabled cheat to it.
func set_player(player: Object) -> void:
	_player = player
	reapply()


func get_player() -> Object:
	return _player if is_instance_valid(_player) else null


## Applies owned+enabled cheats and removes the rest on the bound player.
func reapply() -> void:
	for cheat in _cheats:
		if is_enabled(cheat.id):
			_apply(cheat)
		else:
			_remove(cheat)


## Recomputes unlocks; emits cheat_unlocked for newly unlocked ids when `notify`.
## Call after anything that changes lifetime kills or prestige count.
func refresh_unlocks(notify: bool = true) -> void:
	for cheat in _cheats + _upgrades:
		var now := is_unlocked(cheat.id)
		if now and not _unlocked.has(cheat.id) and notify:
			EventBus.cheat_unlocked.emit(cheat.id)
		if now:
			_unlocked[cheat.id] = true
		else:
			_unlocked.erase(cheat.id)


func _on_game_state_loaded() -> void:
	refresh_unlocks(false)
	reapply()


func _apply(cheat: CheatBase) -> void:
	var player := get_player()
	if player and cheat:
		cheat.apply(player, effective_level(cheat.id))


func _remove(cheat: CheatBase) -> void:
	var player := get_player()
	if player and cheat:
		cheat.remove(player)


# --- Free trial (fun pack, D64) ---------------------------------------------------

## The level a cheat runs at: the owned level, or a higher free-trial level while
## a trial runs. level() stays the owned level (purchases, saves).
func effective_level(id: String) -> int:
	var owned := level(id)
	if trial_left(id) > 0.0:
		return maxi(owned, int(_trials[id]["level"]))
	return owned


## Seconds left on `id`'s free trial (0 = none).
func trial_left(id: String) -> float:
	return float(_trials[id]["left"]) if _trials.has(id) else 0.0


## Runs `levels` (cheat_id -> level) for `seconds` without owning them. Emits
## cheat_toggled(id, true) now and (id, false) when it ends, unless owned and on.
func start_trial(levels: Dictionary, seconds: float) -> void:
	for id in levels:
		if get_cheat(id) == null or is_upgrade(id):
			continue
		_trials[id] = {"level": int(levels[id]), "left": seconds}
		_apply(get_cheat(id))
		EventBus.cheat_toggled.emit(id, true)


func _process(delta: float) -> void:
	tick_trials(delta)


## Counts trials down; expired ones fall back to the owned state. Split out for tests.
func tick_trials(delta: float) -> void:
	if _trials.is_empty():
		return
	for id in _trials.keys():
		_trials[id]["left"] = float(_trials[id]["left"]) - delta
		if float(_trials[id]["left"]) > 0.0:
			continue
		_trials.erase(id)
		var cheat := get_cheat(id)
		if is_enabled(id):
			_apply(cheat)   # owned: back to its own level
		else:
			_remove(cheat)
		EventBus.cheat_toggled.emit(id, is_enabled(id))
		if _trials.is_empty():
			EventBus.emit_chat_event(&"free_trial_end", {})


## Starts economy.json free_trial once per save, when its round goes live.
func _on_round_state(state: StringName, info: Dictionary) -> void:
	var rules: Dictionary = DataRegistry.economy().get("free_trial", {})
	if rules.is_empty() or state != EventBus.ROUND_LIVE or int(info.get("round", 0)) != int(rules.get("round", 1)):
		return
	if GameState.chat_flags.get(FREE_TRIAL_FLAG, false):
		return
	GameState.chat_flags[FREE_TRIAL_FLAG] = true
	start_trial(rules.get("cheats", {}), float(rules.get("seconds", 0.0)))
	EventBus.emit_chat_event(&"free_trial", {"seconds": rules.get("seconds", 0)})
