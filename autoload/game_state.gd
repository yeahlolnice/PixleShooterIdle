extends Node
## The single serialisable game state: everything a save file contains.
## Saved as JSON (user://save.json via SteamService) by SaveService, using
## to_dict()/from_dict() below. Persistence is off until enable_persistence()
## is called (Main does it), so tests never touch the player's real save.
##
## Mutate through the methods (they emit EventBus signals); read fields freely.
## Never put scene nodes or runtime-only state (current health, ammo) here.

const SAVE_VERSION := 1

## Spendable cash. Resets on prestige.
var cash: float = 0.0
## Kills in the current run (since the last prestige).
var kills: int = 0
## Kills ever. Drives cheat unlocks and Hax Points; never resets.
var lifetime_kills: int = 0
## Guns bought and still held (the free starter gun is never listed). Cleared on death.
var owned_guns: Array[String] = []
## Gun currently in hand; "" means the starter gun.
var equipped_gun_id: String = ""
## cheat_id -> owned level (0/absent = not owned). Filled by CheatSystem (TASK-009).
var cheat_levels: Dictionary = {}
## cheat_id -> bool, whether an owned cheat is switched on. (TASK-009)
var cheat_enabled: Dictionary = {}
## Server Slots upgrade level (cheats.json upgrades). Resets on prestige. (TASK-009)
var server_slots: int = 0
## Number of times the player got banned. (Phase 4)
var prestige_count: int = 0
## Unspent prestige currency. (Phase 4)
var hax_points: int = 0
## perk_id -> level for permanent Rootkit perks. (Phase 4)
var rootkit: Dictionary = {}
## Once-only chat triggers already fired, trigger_id -> true. (TASK-013)
var chat_flags: Dictionary = {}
## Bought gun upgrade levels, "<gun_id>:<stat>" -> level. Kept through death
## (only the gun is lost), reset on prestige. (TASK-024)
var gun_upgrades: Dictionary = {}

## True once enable_persistence() ran: autosave at round end and on quit.
var persistence_enabled := false
var _saves: SaveService = null


func _ready() -> void:
	new_game()
	EventBus.round_summary.connect(_on_round_summary)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence_enabled:
		save_game()


# --- Persistence ------------------------------------------------------------------

## Loads the save (or starts fresh) and turns on autosave. `storage` defaults to
## the SteamService autoload; tests pass a stub backend with a temp directory.
func enable_persistence(storage: Object = null) -> SaveService.LoadResult:
	_saves = SaveService.new(storage if storage != null else SteamService)
	persistence_enabled = true
	return load_game()


func disable_persistence() -> void:
	persistence_enabled = false
	_saves = null


## Writes the save now. False if persistence is off or the write failed.
func save_game() -> bool:
	if _saves == null:
		return false
	return _saves.save(self)


## Replaces the state from the save; a missing or corrupt save gives a new game.
func load_game() -> SaveService.LoadResult:
	new_game()
	var result := _saves.load_into(self) if _saves != null else SaveService.LoadResult.MISSING
	if result == SaveService.LoadResult.LOADED:
		print("[GameState] save loaded (cash %.0f, lifetime kills %d)" % [cash, lifetime_kills])
	EventBus.game_state_loaded.emit()
	return result


func _on_round_summary(_summary: Dictionary) -> void:
	if persistence_enabled:
		save_game()


## Fresh state for a brand-new player. Starting cash comes from economy.json.
func new_game() -> void:
	from_dict({})
	cash = float(DataRegistry.economy().get("starting_cash", 0.0))


# --- Mutators (emit EventBus signals) -----------------------------------------

func add_cash(amount: float) -> void:
	if amount == 0.0:
		return
	cash += amount
	EventBus.cash_changed.emit(cash, amount)


func can_afford(price: float) -> bool:
	return Economy.can_afford(cash, price)


## Spends `price` if affordable. Returns false (and changes nothing) otherwise.
func try_spend(price: float) -> bool:
	if not can_afford(price):
		return false
	cash -= price
	EventBus.cash_changed.emit(cash, -price)
	return true


## Counts one kill towards both run and lifetime totals.
func add_kill() -> void:
	kills += 1
	lifetime_kills += 1
	EventBus.kills_changed.emit(kills, lifetime_kills)


func add_owned_gun(gun_id: String) -> void:
	if gun_id != "" and not owned_guns.has(gun_id):
		owned_guns.append(gun_id)


func owns_gun(gun_id: String) -> bool:
	return owned_guns.has(gun_id)


func gun_upgrade_level(gun_id: String, stat: String) -> int:
	return int(gun_upgrades.get("%s:%s" % [gun_id, stat], 0))


func set_gun_upgrade_level(gun_id: String, stat: String, level: int) -> void:
	gun_upgrades["%s:%s" % [gun_id, stat]] = level


## Death penalty: guns are lost, back to the starter. Cash and kills are kept.
func clear_loadout() -> void:
	owned_guns.clear()
	equipped_gun_id = ""


# --- Serialisation --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"cash": cash,
		"kills": kills,
		"lifetime_kills": lifetime_kills,
		"owned_guns": owned_guns.duplicate(),
		"equipped_gun_id": equipped_gun_id,
		"cheat_levels": cheat_levels.duplicate(true),
		"cheat_enabled": cheat_enabled.duplicate(true),
		"server_slots": server_slots,
		"prestige_count": prestige_count,
		"hax_points": hax_points,
		"rootkit": rootkit.duplicate(true),
		"chat_flags": chat_flags.duplicate(true),
		"gun_upgrades": gun_upgrades.duplicate(true),
	}


## Replaces the whole state. Missing or wrongly typed keys fall back to
## defaults, so older, partial or hand-edited saves load without errors.
## Does not emit signals; load_game() emits game_state_loaded.
func from_dict(d: Dictionary) -> void:
	var data := migrate(d)
	cash = _num(data, "cash", 0.0)
	kills = int(_num(data, "kills", 0))
	lifetime_kills = int(_num(data, "lifetime_kills", 0))
	owned_guns.clear()
	for gun_id in _typed(data, "owned_guns", TYPE_ARRAY, []):
		if gun_id is String:
			add_owned_gun(gun_id)
	equipped_gun_id = str(_typed(data, "equipped_gun_id", TYPE_STRING, ""))
	cheat_levels = _int_values(_typed(data, "cheat_levels", TYPE_DICTIONARY, {}))
	cheat_enabled = _bool_values(_typed(data, "cheat_enabled", TYPE_DICTIONARY, {}))
	server_slots = int(_num(data, "server_slots", 0))
	prestige_count = int(_num(data, "prestige_count", 0))
	hax_points = int(_num(data, "hax_points", 0))
	rootkit = _int_values(_typed(data, "rootkit", TYPE_DICTIONARY, {}))
	chat_flags = _bool_values(_typed(data, "chat_flags", TYPE_DICTIONARY, {}))
	gun_upgrades = _int_values(_typed(data, "gun_upgrades", TYPE_DICTIONARY, {}))


static func _typed(d: Dictionary, key: String, type: int, default: Variant) -> Variant:
	var value: Variant = d.get(key, default)
	return value if typeof(value) == type else default


static func _num(d: Dictionary, key: String, default: float) -> float:
	var value: Variant = d.get(key, default)
	return float(value) if (value is float or value is int) else default


## JSON turns every number into a float; levels are ints. Non-numbers are dropped.
static func _int_values(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		if d[key] is float or d[key] is int:
			out[str(key)] = int(d[key])
	return out


static func _bool_values(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		if d[key] is bool:
			out[str(key)] = d[key]
	return out


## Upgrades a save dictionary from an older save_version to `target`.
## A dictionary without save_version is treated as version 0 (pre-versioned).
## Each step upgrades version N to N + 1; add a case to _migrate_step on every
## SAVE_VERSION bump. `steps` (from_version -> Callable(Dictionary) -> Dictionary)
## overrides built-in steps; tests use it to exercise future versions.
## A save from a newer game version loads its known keys with a warning.
static func migrate(d: Dictionary, target: int = SAVE_VERSION, steps: Dictionary = {}) -> Dictionary:
	var data := d.duplicate(true)
	var version := int(_num(data, "save_version", 0))
	if version > target:
		push_warning("[GameState] save_version %d is newer than supported %d; loading known fields only" % [version, target])
	while version < target:
		data = steps[version].call(data) if steps.has(version) else _migrate_step(version, data)
		version += 1
	data["save_version"] = target
	return data


static func _migrate_step(from_version: int, data: Dictionary) -> Dictionary:
	match from_version:
		0:
			pass # Unversioned (Phase 1 in-memory) dicts already use the v1 layout.
		_:
			push_warning("[GameState] no migration from save_version %d" % from_version)
	return data
