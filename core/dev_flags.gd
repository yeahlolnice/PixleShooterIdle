class_name DevFlags
extends RefCounted
## QA command-line flags (pass after `--`, e.g. `godot --path . -- --dev-unlock-all`).
## Debug builds only (running from source or a debug export); release exports ignore them.
## Each starts a fresh in-memory game and the caller turns the save file off, so a
## real save is never read or overwritten. Grants are QA shortcuts, not balance data.
##   --dev-cash        50,000 cash, 400 lifetime kills (first four cheats unlocked; D42)
##   --dev-unlock-all  every cheat unlocked (huge lifetime kills + 3 bans) and 1e9 cash (D50)

const CASH_FLAG := "--dev-cash"
const UNLOCK_ALL_FLAG := "--dev-unlock-all"

const DEV_CASH := 50000.0
const DEV_LIFETIME_KILLS := 400
const ALL_CASH := 1.0e9
const ALL_LIFETIME_KILLS := 1000000
const ALL_BANS := 3


## True if `args` hold a dev flag and `debug_build` allows it.
static func wants_dev_game(args: PackedStringArray, debug_build: bool) -> bool:
	return debug_build and (CASH_FLAG in args or UNLOCK_ALL_FLAG in args)


## Starts the dev game for `args` when allowed. Returns true if it did (the
## caller must then keep the save file off).
static func apply(args: PackedStringArray, debug_build: bool) -> bool:
	if not wants_dev_game(args, debug_build):
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
	print("[DevFlags] ", note)
	# Deferred: Main applies flags in _enter_tree, before the chat box exists.
	ChatSystem.post.call_deferred(&"system", "SYSTEM", note)
	return true
