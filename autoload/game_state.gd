extends Node
## The single serialisable game state: everything a save file contains.
## In-memory only in Phase 1; TASK-008 adds save/load through SaveService +
## SteamService.save_file/load_file, using to_dict()/from_dict() below.
##
## Mutate through the methods (they emit EventBus signals); read fields freely.
## Never put scene nodes or runtime-only state (current health, ammo) here.

const SAVE_VERSION := 1

## Spendable cash. Resets on prestige.
var cash: float = 0.0
## Kills in the current run (since the last prestige). Drives cheat unlocks.
var kills: int = 0
## Kills ever. Drives Hax Points; never resets.
var lifetime_kills: int = 0
## Guns bought and still held (the free starter gun is never listed). Cleared on death.
var owned_guns: Array[String] = []
## Gun currently in hand; "" means the starter gun.
var equipped_gun_id: String = ""
## cheat_id -> owned level (0/absent = not owned). Filled by CheatSystem (TASK-009).
var cheat_levels: Dictionary = {}
## cheat_id -> bool, whether an owned cheat is switched on. (TASK-009)
var cheat_enabled: Dictionary = {}
## Extra bots per wave bought in the mod menu. Resets on prestige. (TASK-009)
var server_slots: int = 0
## Number of times the player got banned. (Phase 4)
var prestige_count: int = 0
## Unspent prestige currency. (Phase 4)
var hax_points: int = 0
## perk_id -> level for permanent Rootkit perks. (Phase 4)
var rootkit: Dictionary = {}
## Once-only chat triggers already fired, trigger_id -> true. (TASK-013)
var chat_flags: Dictionary = {}


func _ready() -> void:
	new_game()


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
	}


## Replaces the whole state. Missing keys fall back to defaults so older or
## partial saves load. Does not emit signals; callers emit game_state_loaded.
func from_dict(d: Dictionary) -> void:
	var data := migrate(d)
	cash = float(data.get("cash", 0.0))
	kills = int(data.get("kills", 0))
	lifetime_kills = int(data.get("lifetime_kills", 0))
	owned_guns.assign(data.get("owned_guns", []))
	equipped_gun_id = str(data.get("equipped_gun_id", ""))
	cheat_levels = _int_values(data.get("cheat_levels", {}))
	cheat_enabled = data.get("cheat_enabled", {}).duplicate(true)
	server_slots = int(data.get("server_slots", 0))
	prestige_count = int(data.get("prestige_count", 0))
	hax_points = int(data.get("hax_points", 0))
	rootkit = _int_values(data.get("rootkit", {}))
	chat_flags = data.get("chat_flags", {}).duplicate(true)


## JSON turns every number into a float; levels are ints.
static func _int_values(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		out[key] = int(d[key])
	return out


## Upgrades a save dictionary from an older save_version to SAVE_VERSION.
## TASK-008 adds one step per version bump here.
static func migrate(d: Dictionary) -> Dictionary:
	var data := d.duplicate(true)
	var _version := int(data.get("save_version", SAVE_VERSION))
	# if _version < 2: data = _migrate_1_to_2(data)
	data["save_version"] = SAVE_VERSION
	return data
