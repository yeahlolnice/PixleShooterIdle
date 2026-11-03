class_name MatchTracker
extends Node
## Records per-round stats (kills, headshots, streak, time, cash) and applies the
## kill/death rules to GameState. Cash maths comes from Economy with values from
## data/economy.json; nothing is tuned here.
##
## Wire-up: add as a node; it listens to EventBus.bot_killed / player_died itself.
## Tests call record_kill / record_death directly.

## Arena whose cash_mult applies; set by Main / RoundController.
var arena_id := ""
var streak := 0
var round_number := 0
var kills := 0
var headshots := 0
var best_streak := 0
var cash_earned := 0.0
var deaths := 0
var time_s := 0.0
var _running := false


func _ready() -> void:
	EventBus.bot_killed.connect(_on_bot_killed)
	EventBus.player_died.connect(_on_player_died)


func start_round(number: int) -> void:
	round_number = number
	kills = 0
	headshots = 0
	best_streak = streak  # streak survives rounds; only death resets it
	cash_earned = 0.0
	deaths = 0
	time_s = 0.0
	_running = true


func tick(delta: float) -> void:
	if _running:
		time_s += delta


## Stops the clock and returns the summary for the HUD.
func end_round() -> Dictionary:
	_running = false
	return summary()


func summary() -> Dictionary:
	return {
		"round": round_number,
		"kills": kills,
		"headshots": headshots,
		"best_streak": best_streak,
		"cash": cash_earned,
		"duration_s": time_s,
		"deaths": deaths,
	}


## Cash for a kill at the current streak (streak = kills before this one).
func kill_value(headshot: bool, bot_type := "") -> float:
	var rules: Dictionary = DataRegistry.economy()["kill_reward"]
	var mults := rules.duplicate()
	var arena := DataRegistry.arena(arena_id) if arena_id != "" else {}
	mults["global_mult"] = float(arena.get("cash_mult", 1.0))
	var base := float(rules["base_cash"])
	if bot_type != "":
		base *= float(DataRegistry.bot(bot_type).get("cash_mult", 1.0))
	return Economy.cash_per_kill(base, headshot, streak, mults)


## Credits cash and kill counters, then extends the streak. Returns cash paid.
func record_kill(headshot: bool, bot_type := "") -> float:
	var cash := kill_value(headshot, bot_type)
	GameState.add_cash(cash)
	GameState.add_kill()
	streak += 1
	kills += 1
	best_streak = maxi(best_streak, streak)
	if headshot:
		headshots += 1
	cash_earned += cash
	return cash


## Death penalty: streak and gun only. Cash and kill totals are untouched.
func record_death() -> void:
	streak = 0
	deaths += 1
	GameState.clear_loadout()
	var starter := DataRegistry.starter_gun_id()
	GameState.equipped_gun_id = starter
	EventBus.gun_equipped.emit(starter)


func _on_bot_killed(_bot: Node, info: Dictionary) -> void:
	record_kill(bool(info.get("headshot", false)), String(info.get("bot_type", "")))


func _on_player_died(_info: Dictionary) -> void:
	record_death()
