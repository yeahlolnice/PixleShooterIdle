class_name AutoBhop
extends CheatBase
## Auto Bhop (ladder #3): hold jump to hop on every landing tick, and from level 2
## auto-strafe in the air. Effects (cheats.json), all target cheat:
##   autostrafe          fraction (0..1) of the best possible air-strafe gain the
##                       cheat strafes for you (0 at level 1: timing only)
##   max_hop_speed_mult  auto-strafe speed cap as a multiple of the player's
##                       effective move speed (so Speed Hack raises it too)
##   uncapped            from max level: no cap at all
## The movement itself lives in Player.step_movement; this cheat only hands the
## current level's values to Player.set_bhop() and takes them back with
## clear_bhop(), so removing it restores plain jumping exactly.


func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	if player == null or not player.has_method("set_bhop"):
		return
	player.set_bhop(settings_at(level))


func remove(player: Object) -> void:
	super.remove(player)
	if player != null and player.has_method("clear_bhop"):
		player.clear_bhop()


## The dictionary Player.set_bhop() expects for `level`.
func settings_at(level: int) -> Dictionary:
	return {
		"autostrafe": float(value_at("autostrafe", level)),
		"max_hop_speed_mult": float(value_at("max_hop_speed_mult", level)),
		"uncapped": bool(value_at("uncapped", level)),
	}
