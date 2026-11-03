class_name DriverCheat
extends CheatBase
## Base for cheats that act every physics tick (Aimbot, Triggerbot, Spinbot).
## apply() adds a Driver node under the player (or updates the one already
## there) holding the level's effect values; remove() frees it. The Driver calls
## drive() each physics tick while CheatTargeting.can_act(player) is true.
## Subclasses override drive(); per-cheat timers live in driver.state.


func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	if not (player is Node):
		return
	var driver := get_driver(player as Node)
	if driver == null:
		driver = Driver.new()
		driver.name = driver_name()
		player.add_child(driver)
	driver.cheat = self
	driver.settings = values_at(level)


func remove(player: Object) -> void:
	super.remove(player)
	if not (player is Node):
		return
	var driver := get_driver(player as Node)
	if driver:
		player.remove_child(driver)
		driver.free()


func driver_name() -> String:
	return id.to_pascal_case() + "Driver"


func get_driver(player: Node) -> Driver:
	return player.get_node_or_null(driver_name()) as Driver


## One physics tick of the cheat. `settings` = values_at(owned level).
func drive(_player: Node, _driver: Driver, _delta: float) -> void:
	pass


## Called instead of drive() on ticks where the cheat may not act (dead, menu open).
func idle(_driver: Driver) -> void:
	pass


## The player's WeaponManager (fires through the same gates as the mouse), or null.
static func weapon_manager_of(player: Node) -> Node:
	return player.get_node_or_null("WeaponManager")


class Driver:
	extends Node

	var cheat: DriverCheat
	var settings := {}
	## Free per-cheat state (timers, current target).
	var state := {}

	func _physics_process(delta: float) -> void:
		tick(delta)

	## Split out so tests can step the cheat without waiting for physics frames.
	func tick(delta: float) -> void:
		var player := get_parent()
		if cheat and CheatTargeting.can_act(player):
			cheat.drive(player, self, delta)
		elif cheat:
			cheat.idle(self)
