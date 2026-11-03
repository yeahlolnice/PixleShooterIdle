class_name DevFlags
extends RefCounted
## QA shortcuts. Available while dev_tools_enabled(): in debug builds (running
## from source or a debug export), or while project setting
## `application/config/dev_tools` is true (on until launch; TASK-048 turns it off).
## Grants are QA shortcuts, not balance data. Dev sessions are never saved.
##
## Command line (pass after `--`, e.g. `godot --path . -- --dev-unlock-all`):
## a fresh in-memory game; the caller turns the save file off.
##   --dev-cash        50,000 cash, 400 lifetime kills (first four cheats unlocked; D42)
##   --dev-unlock-all  every cheat unlocked (huge lifetime kills + 3 bans) and 1e9 cash (D50)
## In game: the pause menu's DEV button calls unlock_all_in_session() (D52).

const CASH_FLAG := "--dev-cash"
const UNLOCK_ALL_FLAG := "--dev-unlock-all"
const DEV_TOOLS_SETTING := "application/config/dev_tools"

const DEV_CASH := 50000.0
const DEV_LIFETIME_KILLS := 400
const ALL_CASH := 1.0e9
const ALL_LIFETIME_KILLS := 1000000
const ALL_BANS := 3


## True in debug builds, or while the dev_tools project setting is on.
static func dev_tools_enabled() -> bool:
	return OS.is_debug_build() or bool(ProjectSettings.get_setting(DEV_TOOLS_SETTING, false))


## True if `args` hold a dev flag and `allowed` (normally dev_tools_enabled()).
static func wants_dev_game(args: PackedStringArray, allowed: bool) -> bool:
	return allowed and (CASH_FLAG in args or UNLOCK_ALL_FLAG in args)


## Starts the dev game for `args` when allowed. Returns true if it did (the
## caller must then keep the save file off).
static func apply(args: PackedStringArray, allowed: bool) -> bool:
	if not wants_dev_game(args, allowed):
		return false
	GameState.new_game()
	var note: String
	if UNLOCK_ALL_FLAG in args:
		GameState.cash = ALL_CASH
		GameState.lifetime_kills = ALL_LIFETIME_KILLS
		GameState.prestige_count = ALL_BANS
		note = "DEV MODE (--dev-unlock-all): every cheat unlocked, $1B cash. Press INSERT to buy. Not saved."
	else:
		GameState.cash = DEV_CASH
		GameState.lifetime_kills = DEV_LIFETIME_KILLS
		note = "DEV MODE (--dev-cash): $50K cash, first four cheats unlocked. Press INSERT to buy. Not saved."
	CheatSystem.refresh_unlocks(false)
	_announce(note, true)
	return true


## Pause-menu DEV button: unlocks every cheat and upgrade in the running game,
## adds 1e9 cash, and turns saving off for the rest of the session so the real
## save keeps its progress. Owned cheats and levels are kept.
static func unlock_all_in_session() -> void:
	GameState.disable_persistence()
	GameState.lifetime_kills = maxi(GameState.lifetime_kills, ALL_LIFETIME_KILLS)
	GameState.prestige_count = maxi(GameState.prestige_count, ALL_BANS)
	CheatSystem.refresh_unlocks(false)
	GameState.add_cash(ALL_CASH)
	EventBus.game_state_loaded.emit()   # menus, HUD and cheats re-read everything
	_announce("DEV MODE: every cheat unlocked, +$1B. Press INSERT to buy. This session will NOT be saved.", false)


## Console + SYSTEM chat line. `deferred` when called before the chat box exists.
static func _announce(note: String, deferred: bool) -> void:
	print("[DevFlags] ", note)
	if deferred:
		ChatSystem.post.call_deferred(&"system", "SYSTEM", note)
	else:
		ChatSystem.post(&"system", "SYSTEM", note)
