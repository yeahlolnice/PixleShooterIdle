class_name LootMagnet
extends DriverCheat
## Loot Magnet (Visuals): every physics tick, loot within `radius_m` (3 m at
## level 1 -> 500 m at max) flies toward the player at economy.json
## loot.magnet_speed_m_s, and pays out on arrival (LootPickup's own pickup check).


func drive(player: Node, driver: DriverCheat.Driver, delta: float) -> void:
	var radius := float(driver.settings.get("radius_m", 0.0))
	if radius <= 0.0:
		return
	var step := float(DataRegistry.economy()["loot"]["magnet_speed_m_s"]) * delta
	var origin: Vector3 = (player as Node3D).global_position
	for loot in player.get_tree().get_nodes_in_group(LootPickup.GROUP):
		if loot is LootPickup and not loot.is_queued_for_deletion() and loot.global_position.distance_to(origin) <= radius:
			loot.pull_toward(player, step)
