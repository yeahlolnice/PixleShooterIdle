class_name CheatBase
extends Resource
## One cheat (or mod-menu upgrade such as Server Slots), built from an entry of
## data/cheats.json by CheatBase.from_def(). Holds no per-player state: the
## owned level and on/off switch live in GameState and are passed in.
##
## Effects (data, see docs/DATA.md) are evaluated per level by value_at():
##   number: "from" at level 1 -> "to" at max_level, "linear" or "exp" curve
##   bool:   true from level "from_level" upwards
## Effect targets decide what the default apply()/remove() touch:
##   player - player.set_stat_mod(key, value) / clear_stat_mod(key)
##   weapon - weapon.set_modifier(key, value) / set_modifier(key, neutral)
##   cheat  - nothing; gameplay code reads CheatSystem.effect(id, key)
##   game   - nothing; global systems read CheatSystem.effect(id, key) (Server Slots)
## A cheat that needs custom behaviour names a subclass in its "script" field and
## overrides apply()/remove(), calling super() to keep the modifier effects.
## Each player/weapon modifier key must belong to exactly one cheat, so remove()
## can restore the neutral value without stacking rules.

@export var id: String = ""
@export var display_name: String = ""
@export var tab: String = ""
@export var order: int = 0
@export var base_cost: float = 0.0
@export var cost_growth: float = 1.0
@export var max_level: int = 1
## Lifetime kills needed to unlock (-1 = not a kill unlock).
@export var unlock_kills: int = -1
## Bans (prestige count) needed to unlock (-1 = not a prestige unlock).
@export var unlock_prestige: int = -1
@export var resets_on_prestige: bool = false
## Raw effect dictionaries from cheats.json.
@export var effects: Array = []


## Builds a cheat from a validated cheats.json entry. `default_growth` is the
## file-level cost_growth, used when the entry has none of its own.
static func from_def(def: Dictionary, default_growth: float) -> CheatBase:
	var cheat: CheatBase
	if def.has("script"):
		cheat = load(def["script"]).new()
	else:
		cheat = CheatBase.new()
	cheat.id = def["id"]
	cheat.display_name = def["name"]
	cheat.tab = def["tab"]
	cheat.order = int(def["order"])
	cheat.base_cost = float(def["base_cost"])
	cheat.cost_growth = float(def.get("cost_growth", default_growth))
	cheat.max_level = int(def["max_level"])
	var unlock: Dictionary = def["unlock"]
	cheat.unlock_kills = int(unlock.get("kills", -1))
	cheat.unlock_prestige = int(unlock.get("prestige", -1))
	cheat.resets_on_prestige = bool(def.get("resets_on_prestige", false))
	cheat.effects = def["effects"].duplicate(true)
	return cheat


# --- Pricing and unlocks -----------------------------------------------------------

## Price of the next level when `level` levels are owned (0 = first purchase).
func cost(level: int) -> float:
	return Economy.cost(base_cost, cost_growth, level)


func is_maxed(level: int) -> bool:
	return level >= max_level


func is_unlocked_for(lifetime_kills: int, prestige_count: int) -> bool:
	if unlock_prestige >= 0:
		return prestige_count >= unlock_prestige
	return lifetime_kills >= maxi(unlock_kills, 0)


## Short requirement text for locked rows, e.g. "400 kills" or "Ban 2".
## The mod menu may format its own; this keeps the rule in one place.
func unlock_requirement() -> Dictionary:
	if unlock_prestige >= 0:
		return {"prestige": unlock_prestige}
	return {"kills": maxi(unlock_kills, 0)}


# --- Effects ------------------------------------------------------------------------

func effect_def(key: String) -> Dictionary:
	for e in effects:
		if e["key"] == key:
			return e
	return {}


## Value of effect `key` at `level`. Level 0 (not owned) gives the neutral value.
func value_at(key: String, level: int) -> Variant:
	var e := effect_def(key)
	if e.is_empty():
		return null
	if level <= 0:
		return neutral_value(e)
	if e["type"] == "bool":
		return level >= int(e["from_level"])
	var a := float(e["from"])
	var b := float(e["to"])
	var lvl := mini(level, max_level)
	var t := 1.0 if max_level <= 1 else float(lvl - 1) / float(max_level - 1)
	if e["curve"] == "exp":
		return a * pow(b / a, t)
	return lerpf(a, b, t)


## All effect values at `level`, key -> value.
func values_at(level: int) -> Dictionary:
	var out := {}
	for e in effects:
		out[e["key"]] = value_at(e["key"], level)
	return out


## What an effect is when the cheat is off: false for flags, 1 for player/weapon
## multipliers, 0 for cheat/game values (no aimbot FOV, no extra bots).
static func neutral_value(e: Dictionary) -> Variant:
	if e["type"] == "bool":
		return false
	if e["target"] == "player" or e["target"] == "weapon":
		return 1.0
	return 0.0


## Turns the cheat on at `level` for `player`. Must be idempotent: CheatSystem
## calls it again on respawn, gun change and upgrade.
func apply(player: Object, level: int) -> void:
	if player == null:
		return
	var weapon := weapon_of(player)
	for e in effects:
		var value: Variant = value_at(e["key"], level)
		match e["target"]:
			"player":
				if player.has_method("set_stat_mod"):
					player.set_stat_mod(StringName(e["key"]), float(value))
			"weapon":
				if weapon:
					weapon.set_modifier(e["key"], value)


## Turns the cheat off, restoring the neutral modifier values exactly.
func remove(player: Object) -> void:
	if player == null:
		return
	var weapon := weapon_of(player)
	for e in effects:
		match e["target"]:
			"player":
				if player.has_method("clear_stat_mod"):
					player.clear_stat_mod(StringName(e["key"]))
			"weapon":
				if weapon:
					weapon.set_modifier(e["key"], neutral_value(e))


## The player's current Weapon: `get_weapon()` if the player has it (test
## doubles), else the WeaponManager child's weapon. Null when unarmed.
static func weapon_of(player: Object) -> Object:
	if player.has_method("get_weapon"):
		return player.get_weapon()
	if player is Node:
		var manager: Node = player.get_node_or_null("WeaponManager")
		if manager and "weapon" in manager:
			return manager.weapon
	return null
