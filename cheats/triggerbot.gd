class_name Triggerbot
extends DriverCheat
## Triggerbot (Combat): fires by itself once the crosshair has rested on the same
## live bot for `delay_s` (0.3 s at level 1 -> instant at max). Shots go through
## WeaponManager.cheat_fire(), so they obey fire rate, ammo, menus and freeze time.
## Holding on a bot keeps firing at the gun's fire rate (semi-autos too).


func drive(player: Node, driver: DriverCheat.Driver, delta: float) -> void:
	var weapon: Object = weapon_of(player)
	var manager := weapon_manager_of(player)
	if weapon == null or manager == null:
		return
	var bot := CheatTargeting.bot_under_crosshair(player.camera, float(weapon.gun.get("range_m", 50.0)))
	if bot == null:
		driver.state.clear()
		return
	if driver.state.get("bot") != bot:
		driver.state = {"bot": bot, "on_target_s": 0.0}
	driver.state["on_target_s"] += delta
	if driver.state["on_target_s"] >= float(driver.settings.get("delay_s", 0.0)):
		manager.cheat_fire()
