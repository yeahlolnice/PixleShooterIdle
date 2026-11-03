class_name Spinbot
extends DriverCheat
## Spinbot (Rage): 360-degree rage aim. Every `spin_interval_s` (2 s at level 1
## -> 0.1 s at max) it whips the view onto the nearest-to-crosshair visible bot
## head in any direction and fires one shot. From `constant_fire` (max level) it
## stays locked and fires whenever the gun allows. Shots go through
## WeaponManager.cheat_fire() (fire rate, ammo, menus, freeze time).

## Any direction counts, including straight behind.
const FULL_CIRCLE_DEG := 180.0


func drive(player: Node, driver: DriverCheat.Driver, delta: float) -> void:
	var manager := weapon_manager_of(player)
	if manager == null:
		return
	var constant := bool(driver.settings.get("constant_fire", false))
	driver.state["wait_s"] = float(driver.state.get("wait_s", 0.0)) - delta
	if not constant and driver.state["wait_s"] > 0.0:
		return
	var target := CheatTargeting.best_target(player.camera, FULL_CIRCLE_DEG)
	if target.is_empty():
		return
	player.aim_at(target["head"], 1.0)
	if manager.cheat_fire():
		EventBus.cheat_fired.emit(id)
		driver.state["wait_s"] = float(driver.settings.get("spin_interval_s", 0.0))
