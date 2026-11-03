class_name Noclip
extends CheatBase
## Noclip (Movement, unlocks after ban 3): the noclip action (V) toggles flight
## through walls. Effects (cheats.json), all target cheat:
##   burst_s               seconds of flight per round (refilled at freeze time)
##   max_wall_thickness_m  deepest solid geometry one pass may go through
##   unlimited_flight      max level: no time limit
## Flight itself lives in Player (step_noclip); this cheat only hands the
## level's values to Player.set_noclip() and takes them back with clear_noclip().


func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	if player != null and player.has_method("set_noclip"):
		player.set_noclip(settings_at(level))


func remove(player: Object) -> void:
	super.remove(player)
	if player != null and player.has_method("clear_noclip"):
		player.clear_noclip()


## The dictionary Player.set_noclip() expects for `level`.
func settings_at(level: int) -> Dictionary:
	return {
		"burst_s": float(value_at("burst_s", level)),
		"max_wall_thickness_m": float(value_at("max_wall_thickness_m", level)),
		"unlimited": bool(value_at("unlimited_flight", level)),
	}
