class_name SentryManager
extends Node3D
## Keeps one Sentry per owned sentry_count level standing on the arena's
## arenas.json "sentry_spots" (fun pack, D66), and pushes the sentry_damage /
## sentry_rate upgrade multipliers into them. Main calls rebuild() when an arena
## is built; purchases and loads re-sync on their own.

const COUNT_UPGRADE := "sentry_count"
const DAMAGE_UPGRADE := "sentry_damage"
const RATE_UPGRADE := "sentry_rate"

var arena_id := ""


func _ready() -> void:
	EventBus.cheat_purchased.connect(_on_cheat_purchased)
	EventBus.game_state_loaded.connect(sync)


func _on_cheat_purchased(id: String, _level: int) -> void:
	if id.begins_with("sentry_"):
		sync()


## Sentries wanted now: the count upgrade's value, capped by the arena's spots.
func wanted() -> int:
	var spots: Array = DataRegistry.arena(arena_id).get("sentry_spots", [])
	return mini(roundi(float(CheatSystem.effect(COUNT_UPGRADE, "count"))), spots.size())


func sentries() -> Array:
	return get_children().filter(func(c): return c is Sentry and not c.is_queued_for_deletion())


## Clears every sentry and deploys again on `id`'s spots.
func rebuild(id: String) -> void:
	arena_id = id
	for s in sentries():
		remove_child(s)
		s.queue_free()
	sync()


## Adds or removes sentries to match wanted(), then updates every multiplier.
func sync() -> void:
	var spots: Array = DataRegistry.arena(arena_id).get("sentry_spots", [])
	var have := sentries()
	while have.size() > wanted():
		var s: Node = have.pop_back()
		remove_child(s)
		s.queue_free()
	while have.size() < wanted():
		var s := Sentry.new()
		add_child(s)
		s.global_position = spots[have.size()]
		have.append(s)
	var dmg := maxf(float(CheatSystem.effect(DAMAGE_UPGRADE, "damage_mult")), 1.0)
	var rate := maxf(float(CheatSystem.effect(RATE_UPGRADE, "fire_rate_mult")), 1.0)
	for s in have:
		s.damage_mult = dmg
		s.fire_rate_mult = rate
