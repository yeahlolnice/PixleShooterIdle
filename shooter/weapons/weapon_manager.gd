class_name WeaponManager
extends Node
## Holds the player's single equipped Weapon. Add as a child of the player.
## Equips by id from guns.json and falls back to the free starter gun when the
## id is empty or unknown. Also routes fire/reload input.

## Where the viewmodel is parented; resolved from the owner if left empty.
@export var mount_path: NodePath = ^"../Head/Camera3D/WeaponMount"

var weapon: Weapon
var _menu_open := false
var _can_shoot := true


func _ready() -> void:
	EventBus.menu_toggled.connect(func(_id, open): _menu_open = open)
	EventBus.round_state_changed.connect(func(state, _info): _can_shoot = state == EventBus.ROUND_LIVE)
	EventBus.player_died.connect(func(_info): equip_starter())
	equip(GameState.equipped_gun_id)


## Equips gun_id, or the starter if it is empty/unknown. Returns the id equipped.
func equip(gun_id: String) -> String:
	var def := DataRegistry.gun(gun_id) if gun_id != "" else {}
	if def.is_empty():
		def = DataRegistry.gun(DataRegistry.starter_gun_id())
	if weapon:
		weapon.get_parent().remove_child(weapon)
		weapon.queue_free()
	weapon = Weapon.new()
	var mount: Node = get_node_or_null(mount_path)
	(mount if mount else self).add_child(weapon)
	weapon.setup(def)
	EventBus.gun_equipped.emit(def["id"])
	return def["id"]


func equip_starter() -> String:
	return equip(DataRegistry.starter_gun_id())


func _physics_process(_delta: float) -> void:
	if weapon == null or _menu_open or not _can_shoot:
		return
	var fire := Input.is_action_pressed("fire") if weapon.is_auto() else Input.is_action_just_pressed("fire")
	if fire:
		weapon.try_fire()
	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()
