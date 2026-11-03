class_name Economy
extends RefCounted
## Pure economy maths. No state, no node access, no file IO, no tuning numbers:
## every value comes in as a parameter, normally read from data/economy.json by
## the caller (see docs/DATA.md). The only literals allowed here are 0 and 1.
##
## Example (RoundController / MatchTracker):
##   var rules: Dictionary = DataRegistry.economy()["kill_reward"]
##   var mults := rules.duplicate()
##   mults["global_mult"] = DataRegistry.arena(arena_id)["cash_mult"]
##   var cash := Economy.cash_per_kill(rules["base_cash"], headshot, streak, mults)


## Price of the next purchase when `level` levels are already owned.
## cost(base, growth, 0) == base (first purchase).  cost(n) = base * growth^n.
static func cost(base: float, growth: float, level: int) -> float:
	if level <= 0:
		return base
	return base * pow(growth, level)


## Total price of buying `count` consecutive levels starting from `level`.
static func cost_range(base: float, growth: float, level: int, count: int) -> float:
	var total := 0.0
	for i in range(count):
		total += cost(base, growth, level + i)
	return total


## Cash paid for one kill.
##   base     - base cash per kill (economy.json kill_reward.base_cash, times bot cash_mult)
##   headshot - whether the killing shot hit the head
##   streak   - kills already in the current streak before this kill (0 = first kill)
##   multipliers - optional keys, missing keys are neutral:
##       headshot_mult (float, default 1) applied on headshots
##       streak_step   (float, default 0) bonus fraction per streak kill
##       streak_cap    (float, default 0) maximum total streak bonus fraction
##       global_mult   (float, default 1) arena x prestige x rootkit product
## Result = base * (headshot ? headshot_mult : 1) * (1 + min(streak*step, cap)) * global_mult
static func cash_per_kill(base: float, headshot: bool, streak: int, multipliers: Dictionary = {}) -> float:
	var value := base
	if headshot:
		value *= float(multipliers.get("headshot_mult", 1.0))
	value *= streak_multiplier(streak, float(multipliers.get("streak_step", 0.0)), float(multipliers.get("streak_cap", 0.0)))
	value *= float(multipliers.get("global_mult", 1.0))
	return value


## 1 + min(streak * step, cap); never below 1.
static func streak_multiplier(streak: int, step: float, cap: float) -> float:
	var bonus := minf(maxf(streak, 0) * step, cap)
	return 1.0 + maxf(bonus, 0.0)


static func can_afford(cash: float, price: float) -> bool:
	return price <= cash


## Hax Points from lifetime kills: floor(sqrt(lifetime_kills / divisor)).
## divisor comes from economy.json hax_points.kills_divisor.
static func hax_points(lifetime_kills: int, divisor: float) -> int:
	if divisor <= 0.0 or lifetime_kills <= 0:
		return 0
	return int(floor(sqrt(lifetime_kills / divisor)))
