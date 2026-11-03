extends Node3D
## Test double for a bot: records damage from Weapon hitscans.
var last_damage := 0.0
var last_info := {}


func apply_damage(amount: float, info: Dictionary) -> void:
	last_damage = amount
	last_info = info
