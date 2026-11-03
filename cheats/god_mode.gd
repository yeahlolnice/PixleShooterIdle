class_name GodMode
extends CheatBase
## God Mode (Rage, unlocks after ban 1): every kill makes the player
## invulnerable for `invuln_after_kill_s` (2 s at level 1 -> 20 s at max), and
## from `permanent` (max level) no damage lands at all. Falling out of the map
## still kills. The rule lives in Player (set_god_mode / take_damage); this cheat
## only hands it the level's values and turns it off again in remove().


func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	if player != null and player.has_method("set_god_mode"):
		player.set_god_mode(float(value_at("invuln_after_kill_s", level)), bool(value_at("permanent", level)))


func remove(player: Object) -> void:
	super.remove(player)
	if player != null and player.has_method("set_god_mode"):
		player.set_god_mode(0.0, false)
