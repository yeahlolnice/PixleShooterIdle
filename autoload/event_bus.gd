extends Node
## Global signal hub. Systems never call each other's UI; they emit here and
## whoever cares connects. Emitters own the meaning of a signal; listeners must
## not assume who emitted it. Every signal is documented in docs/ARCHITECTURE.md.
##
## Usage:
##   EventBus.bot_killed.connect(_on_bot_killed)
##   EventBus.bot_killed.emit(bot, {"headshot": true, "gun_id": "pistol_starter", "position": pos})

# --- Round states (values of round_state_changed.state) ---------------------
const ROUND_FREEZE := &"freeze"   ## Buy time; player cannot shoot, bots not spawned.
const ROUND_LIVE := &"live"       ## Bots spawned, shooting allowed.
const ROUND_SUMMARY := &"summary" ## Round over; summary panel visible.

# --- Combat -------------------------------------------------------------------
## A bot took damage but survived (hit markers, damage numbers).
## info: {amount: float, headshot: bool, gun_id: String, position: Vector3, health_left: float}
signal bot_damaged(bot: Node, info: Dictionary)
## A bot died. Emitted exactly once per bot by the bot itself.
## info: {headshot: bool, gun_id: String, position: Vector3, bot_type: String}
signal bot_killed(bot: Node, info: Dictionary)
## The player spawned or respawned and is ready to be modified (cheats re-apply here).
signal player_spawned(player: Node)
## The player lost health. source may be null (fall damage, debug).
signal player_damaged(amount: float, health_left: float, source: Node)
## The player died. info: {position: Vector3, killer: Node or null}
signal player_died(info: Dictionary)
## Weapon fired one shot (audio, recoil UI, triggerbot bookkeeping).
signal weapon_fired(gun_id: String)
## Magazine changed. mag_size <= 0 means "infinite" (Infinite Ammo max level).
signal ammo_changed(in_mag: int, mag_size: int)
## A gun became the active weapon (buy, death fallback to starter, round start).
signal gun_equipped(gun_id: String)

# --- Round flow ---------------------------------------------------------------
## Round state machine moved. state is one of ROUND_*.
## info: {round: int, duration: float (seconds, 0 if open-ended)}
signal round_state_changed(state: StringName, info: Dictionary)
## A round ended. summary: MatchTracker.end_round() dictionary
## {round, kills, headshots, best_streak, cash, duration_s, deaths}.
signal round_summary(summary: Dictionary)

# --- Economy / progression ----------------------------------------------------
## GameState cash changed. delta is negative for spending.
signal cash_changed(total: float, delta: float)
## GameState kill counters changed.
signal kills_changed(kills: int, lifetime_kills: int)
## A cheat became purchasable (kill or prestige threshold reached).
signal cheat_unlocked(cheat_id: String)
## A cheat was bought or upgraded; level is the new level (1 = first purchase).
signal cheat_purchased(cheat_id: String, level: int)
## An owned cheat was switched on or off.
signal cheat_toggled(cheat_id: String, enabled: bool)

# --- UI coordination ----------------------------------------------------------
## A full-screen or modal menu opened/closed. menu_id: "buy_menu", "mod_menu", "chat", "pause".
## The player stops mouse-look and firing while any menu is open.
signal menu_toggled(menu_id: StringName, open: bool)

# --- Chat ---------------------------------------------------------------------
## A gameplay moment the ChatSystem may react to (first_match, first_cash,
## cheat_first_use, mod_spawned, prestige, ...). payload is free-form but
## documented per event name in docs/ARCHITECTURE.md.
signal chat_event(event_name: StringName, payload: Dictionary)
## The ChatSystem posted a line; the chat UI renders it.
## channel: "system" | "seller" | "bot"
signal chat_message_posted(channel: StringName, sender: String, text: String)

# --- Persistence --------------------------------------------------------------
## GameState was replaced from a save (UI should refresh everything).
signal game_state_loaded()


## Convenience wrapper so callers do not build payloads inline everywhere.
func emit_chat_event(event_name: StringName, payload: Dictionary = {}) -> void:
	chat_event.emit(event_name, payload)
