class_name MatchTracker
extends Node
## Records per-round stats (kills, headshots, streak, time, cash) and applies the
## kill/death rules to GameState. Cash maths comes from Economy with values from
## data/economy.json; nothing is tuned here.
##
## Wire-up: add as a node; it listens to EventBus.bot_killed / player_died itself.
## Tests call record_kill / record_death directly.

## gun_id that Sentry.exe turrets report on their kills (D66).
const SENTRY_GUN_ID := "sentry"

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
## Multi-kill chain (fun pack): kills within multi_kill.window_s of the previous one.
var chain := 0
var _clock := 0.0
var _last_kill_at := -INF


func _ready() -> void:
	EventBus.bot_killed.connect(_on_bot_killed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.collateral_kill.connect(_on_collateral_kill)


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
	_clock += delta
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
	mults["global_mult"] = float(arena.get("cash_mult", 1.0)) * cheat_bonus_mult()
	var base := float(rules["base_cash"])
	if bot_type != "":
		base *= float(DataRegistry.bot(bot_type).get("cash_mult", 1.0))
	return Economy.cash_per_kill(base, headshot, streak, mults)


## 1 + per_cheat_bonus x (cheats switched on): running more cheats pays more.
static func cheat_bonus_mult() -> float:
	var per := float(DataRegistry.economy()["kill_reward"].get("per_cheat_bonus", 0.0))
	var on := 0
	for cheat in CheatSystem.cheats():
		if CheatSystem.is_enabled(cheat.id):
			on += 1
	return 1.0 + per * on


## Credits cash and kill counters, then extends the streak. `mult` scales the
## cash (multi-kill bonus). Returns cash paid.
func record_kill(headshot: bool, bot_type := "", mult := 1.0) -> float:
	var cash := kill_value(headshot, bot_type) * mult
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
	if String(info.get("gun_id", "")) == SENTRY_GUN_ID:
		EventBus.kill_rewarded.emit(record_sentry_kill(String(info.get("bot_type", ""))), info)
		return
	var mult := advance_chain()
	var cash := record_kill(bool(info.get("headshot", false)), String(info.get("bot_type", "")), mult)
	EventBus.kill_rewarded.emit(cash, info)
	if chain >= 2:
		EventBus.multi_kill.emit(chain, mult)


## Counts this kill into the multi-kill chain and returns its cash multiplier:
## 1 + (chain - 1) x step, capped (economy.json multi_kill).
func advance_chain() -> float:
	var rules: Dictionary = DataRegistry.economy().get("multi_kill", {})
	chain = chain + 1 if _clock - _last_kill_at <= float(rules.get("window_s", 0.0)) else 1
	_last_kill_at = _clock
	return minf(1.0 + (chain - 1) * float(rules.get("step", 0.0)), float(rules.get("cap", 1.0)))


## A sentry kill (D66): counts as a kill (unlocks, totals) but pays
## sentries.cash_mult of a plain no-streak kill and never touches the streak
## or the multi-kill chain, so playing yourself always pays more.
func record_sentry_kill(bot_type := "") -> float:
	var saved := streak
	streak = 0
	var cash := kill_value(false, bot_type) * float(DataRegistry.economy().get("sentries", {}).get("cash_mult", 0.0))
	streak = saved
	GameState.add_cash(cash)
	GameState.add_kill()
	kills += 1
	cash_earned += cash
	return cash


## One bullet killed `count` bots: pays collateral.bonus_cash_mult x a plain kill per bot.
func _on_collateral_kill(count: int, position: Vector3) -> void:
	var bonus := kill_value(false) * float(DataRegistry.economy().get("collateral", {}).get("bonus_cash_mult", 0.0)) * count
	if bonus <= 0.0:
		return
	GameState.add_cash(bonus)
	cash_earned += bonus
	EventBus.bonus_paid.emit("COLLATERAL x%d" % count, bonus, position)


func _on_player_died(_info: Dictionary) -> void:
	record_death()
