class_name LootDropper
extends Node
## Drops a LootPickup where a bot dies: with economy.json loot.drop_chance, worth
## loot.cash_mult x that kill's cash (MatchTracker.kill_value). This is bonus
## cash on top of the kill reward, which is still paid at once.
## Main sets `tracker` and `container` (the BotSpawner, so round-end cleanup
## frees leftover loot together with the bots).

const DROP_HEIGHT := 0.5   ## metres above the bot's feet

var tracker: MatchTracker
var container: Node
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.bot_killed.connect(func(_bot, info): drop(info))


func seed_rng(s: int) -> void:
	_rng.seed = s


## Rolls a drop for one kill (`info` = the bot_killed payload). Returns the
## pickup, or null when nothing dropped.
func drop(info: Dictionary) -> LootPickup:
	var rules: Dictionary = DataRegistry.economy()["loot"]
	if container == null or tracker == null or _rng.randf() >= float(rules["drop_chance"]):
		return null
	var cash := tracker.kill_value(bool(info.get("headshot", false)), String(info.get("bot_type", ""))) * float(rules["cash_mult"])
	if cash <= 0.0:
		return null
	var pickup := LootPickup.new()
	pickup.setup(cash, rules)
	container.add_child(pickup)
	pickup.global_position = info.get("position", Vector3.ZERO) + Vector3(0, DROP_HEIGHT, 0)
	return pickup
