class_name WeaponManager
extends Node
## Holds the player's single equipped Weapon. Add as a child of the player.
## Equips by id from guns.json and falls back to the free starter gun when the
## id is empty or unknown. Also routes fire/reload input, and aiming (the aim
## action, RMB): guns with zoom_fov zoom the camera, hide the viewmodel and slow
## mouse look by the zoom ratio while held.

## Where the viewmodel is parented; resolved from the owner if left empty.
@export var mount_path: NodePath = ^"../Head/Camera3D/WeaponMount"

var weapon: Weapon
## Ids of menus currently open; firing is blocked while any is open.
var _open_menus: Dictionary = {}
var _can_shoot := true
var _aiming := false
var _camera: Camera3D
var _base_fov := 0.0


func _ready() -> void:
	EventBus.menu_toggled.connect(_on_menu_toggled)
	EventBus.round_state_changed.connect(_on_round_state)
	EventBus.player_died.connect(func(_info): equip_starter())
	EventBus.gun_upgraded.connect(_on_gun_upgraded)
	var mount := get_node_or_null(mount_path)
	if mount:
		_camera = mount.get_parent() as Camera3D
	_base_fov = _camera.fov if _camera else 0.0
	equip(GameState.equipped_gun_id)


## Equips gun_id, or the starter if it is empty/unknown. Returns the id equipped.
func equip(gun_id: String) -> String:
	var def := DataRegistry.gun(gun_id) if gun_id != "" else {}
	if def.is_empty():
		def = DataRegistry.gun(DataRegistry.starter_gun_id())
	set_aiming(false)
	if weapon:
		weapon.get_parent().remove_child(weapon)
		weapon.queue_free()
	weapon = Weapon.new()
	var mount: Node = get_node_or_null(mount_path)
	(mount if mount else self).add_child(weapon)
	var aim_owner := get_parent()
	if aim_owner and aim_owner.has_method("add_aim_kick"):
		weapon.recoil_kicked.connect(aim_owner.add_aim_kick)
	weapon.setup(def)
	apply_upgrades()
	EventBus.gun_equipped.emit(def["id"])
	return def["id"]


## Sets the weapon's damage / fire-rate multipliers from bought gun upgrades.
func apply_upgrades() -> void:
	if weapon:
		weapon.damage_mult = ShopService.upgrade_mult(weapon.gun_id(), "damage")
		weapon.fire_rate_mult = ShopService.upgrade_mult(weapon.gun_id(), "fire_rate")


## Scopes in or out. Only guns with zoom_fov zoom; others just stay unscoped.
func set_aiming(on: bool) -> void:
	var scope := on and weapon != null and weapon.zoom_fov() > 0.0
	_aiming = on
	if weapon:
		weapon.scoped = scope
		weapon.visible = not scope
	if _camera:
		_camera.fov = weapon.zoom_fov() if scope else _base_fov
	var p := get_parent()
	if p and "look_scale" in p:
		p.look_scale = (weapon.zoom_fov() / _base_fov) if scope and _base_fov > 0.0 else 1.0


func is_scoped() -> bool:
	return weapon != null and weapon.scoped


func _on_gun_upgraded(gun_id: String, _stat: String, _level: int) -> void:
	if weapon and gun_id == weapon.gun_id():
		apply_upgrades()


func _on_round_state(state: StringName, _info: Dictionary) -> void:
	_can_shoot = state == EventBus.ROUND_LIVE
	# The gun announced its ammo in equip(), before the HUD existed on first boot.
	if weapon:
		EventBus.ammo_changed.emit(weapon.ammo, weapon.mag_size())


func _on_menu_toggled(menu_id: StringName, open: bool) -> void:
	if open:
		_open_menus[menu_id] = true
		set_aiming(false)
	else:
		_open_menus.erase(menu_id)


## True while at least one menu is open (fire/reload input is ignored).
func is_menu_open() -> bool:
	return not _open_menus.is_empty()


## Fires one shot for a cheat (Triggerbot, Spinbot) under the same rules as the
## fire button: round live and no menu open. True if a shot went off.
func cheat_fire() -> bool:
	if weapon == null or not _open_menus.is_empty() or not _can_shoot:
		return false
	return weapon.try_fire()


func equip_starter() -> String:
	return equip(DataRegistry.starter_gun_id())


func _physics_process(_delta: float) -> void:
	if weapon == null or not _open_menus.is_empty():
		return
	var aim := Input.is_action_pressed("aim")
	if aim != _aiming:
		set_aiming(aim)
	if not _can_shoot:
		return
	var fire := Input.is_action_pressed("fire") if weapon.is_auto() else Input.is_action_just_pressed("fire")
	if fire:
		weapon.try_fire()
	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()
