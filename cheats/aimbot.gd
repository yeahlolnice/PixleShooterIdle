class_name Aimbot
extends DriverCheat
## Aimbot (Rage): every physics tick, pulls the aim toward the visible bot head
## nearest the crosshair. Effects (cheats.json), all target cheat:
##   fov_deg           only heads within this angle of the crosshair are locked
##                     (180 at max: anywhere around you)
##   snap_speed        fraction of the remaining angle turned per physics tick
##                     (1 = instant snap)
##   instant_headshot  max level: every bot hit counts as a headshot (sets the
##                     weapon's force_headshot modifier; reapplied on gun change)
## Fighting it with the mouse works at low levels; it also pulls recoil back on target.

const FORCE_HEADSHOT := "force_headshot"


func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	var weapon: Object = weapon_of(player) if player else null
	if weapon:
		weapon.set_modifier(FORCE_HEADSHOT, bool(value_at("instant_headshot", level)))


func remove(player: Object) -> void:
	super.remove(player)
	var weapon: Object = weapon_of(player) if player else null
	if weapon:
		weapon.set_modifier(FORCE_HEADSHOT, false)


func drive(player: Node, driver: DriverCheat.Driver, _delta: float) -> void:
	var target := CheatTargeting.best_target(player.camera, float(driver.settings.get("fov_deg", 0.0)))
	if not target.is_empty():
		player.aim_at(target["head"], float(driver.settings.get("snap_speed", 0.0)))
