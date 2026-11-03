class_name Weapon
extends Node3D
## One hitscan gun driven by an entry of data/guns.json.
##
## The magazine/reload/cooldown state machine is plain code advanced by tick(),
## so tests run it without a scene tree. Cheats change the gun only through
## `modifiers` (mag_mult, recoil_mult, spread_mult, infinite_reload).
##
## Hitbox contract (bots, TASK-003): hitboxes are Area3D on Layers.HITBOXES.
## A head hitbox has meta "headshot" = true. The raycast walks up from the hit
## Area3D to the first node with `apply_damage(amount: float, info: Dictionary)`.

signal shot_fired(hit: Dictionary)
signal reload_started
signal reload_finished

enum State { READY, RELOADING }

const MUZZLE_FLASH_S := 0.05
const RECOIL_RECOVERY_DEG_S := 12.0

var gun: Dictionary = {}
var state: State = State.READY
var ammo: int = 0
var modifiers := {"mag_mult": 1.0, "recoil_mult": 1.0, "spread_mult": 1.0, "infinite_reload": false}
## Camera pitch kick in degrees, positive = up. Decays back to 0.
var recoil_offset_deg: float = 0.0

var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _flash_left: float = 0.0
var _rng := RandomNumberGenerator.new()
var _flash: MeshInstance3D
var _sound: AudioStreamPlayer
var _camera: Camera3D


func setup(gun_def: Dictionary) -> void:
	gun = gun_def
	state = State.READY
	_cooldown = 0.0
	_reload_left = 0.0
	recoil_offset_deg = 0.0
	ammo = mag_size()
	_rng.randomize()
	_build_viewmodel()
	EventBus.ammo_changed.emit(ammo, mag_size())


func seed_rng(s: int) -> void:
	_rng.seed = s


# --- Effective values (data * modifiers) ------------------------------------------

func gun_id() -> String:
	return gun.get("id", "")


func mag_size() -> int:
	return maxi(1, roundi(float(gun.get("mag_size", 1)) * float(modifiers["mag_mult"])))


func recoil_deg() -> float:
	return float(gun.get("recoil_deg", 0.0)) * float(modifiers["recoil_mult"])


func spread_deg() -> float:
	return float(gun.get("spread_deg", 0.0)) * float(modifiers["spread_mult"])


func reload_time() -> float:
	if modifiers["infinite_reload"]:
		return 0.0
	return float(gun.get("reload_time_s", 0.0))


func fire_interval() -> float:
	return 1.0 / float(gun.get("fire_rate", 1.0))


func is_auto() -> bool:
	return bool(gun.get("auto", false))


func is_reloading() -> bool:
	return state == State.RELOADING


func set_modifier(key: String, value: Variant) -> void:
	modifiers[key] = value
	if key == "mag_mult":
		ammo = mini(ammo, mag_size())
		EventBus.ammo_changed.emit(ammo, mag_size())


func reset_modifiers() -> void:
	for key in ["mag_mult", "recoil_mult", "spread_mult"]:
		modifiers[key] = 1.0
	modifiers["infinite_reload"] = false
	ammo = mini(ammo, mag_size())


# --- State machine ------------------------------------------------------------------

func can_fire() -> bool:
	return state == State.READY and ammo > 0 and _cooldown <= 0.0


## Fires one shot if allowed. An empty magazine starts a reload instead.
func try_fire() -> bool:
	if state == State.READY and ammo <= 0:
		start_reload()
		return false
	if not can_fire():
		return false
	ammo -= 1
	_cooldown = fire_interval()
	recoil_offset_deg += recoil_deg()
	var hit := _hitscan() if is_inside_tree() else {}
	_flash_left = MUZZLE_FLASH_S
	if _flash:
		_flash.visible = true
	if _sound:
		_sound.play()
	EventBus.weapon_fired.emit(gun_id())
	EventBus.ammo_changed.emit(ammo, mag_size())
	shot_fired.emit(hit)
	if ammo <= 0:
		start_reload()
	return true


func start_reload() -> bool:
	if state == State.RELOADING or ammo >= mag_size():
		return false
	state = State.RELOADING
	_reload_left = reload_time()
	reload_started.emit()
	if _reload_left <= 0.0:
		_finish_reload()
	return true


func _finish_reload() -> void:
	state = State.READY
	_reload_left = 0.0
	ammo = mag_size()
	EventBus.ammo_changed.emit(ammo, mag_size())
	reload_finished.emit()


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if state == State.RELOADING:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if recoil_offset_deg > 0.0:
		recoil_offset_deg = maxf(0.0, recoil_offset_deg - RECOIL_RECOVERY_DEG_S * delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and _flash:
			_flash.visible = false


func _physics_process(delta: float) -> void:
	tick(delta)
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	if _camera:
		_camera.rotation.x = deg_to_rad(recoil_offset_deg)


# --- Hitscan --------------------------------------------------------------------------

## Random direction inside a cone of half-angle spread_deg around forward.
func spread_direction(forward: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return forward
	var angle := deg_to_rad(spread) * sqrt(_rng.randf())  # sqrt = uniform over the disc
	var around := _rng.randf() * TAU
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var true_up := right.cross(forward).normalized()
	var offset := right * cos(around) + true_up * sin(around)
	return (forward * cos(angle) + offset * sin(angle)).normalized()


## Casts the shot ray from the camera. Returns {hit, headshot, damage, position}.
func _hitscan() -> Dictionary:
	var result := {"hit": false, "headshot": false, "damage": 0.0, "position": Vector3.ZERO}
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return result
	var origin := cam.global_position
	var dir := spread_direction(-cam.global_transform.basis.z, spread_deg())
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + dir * float(gun.get("range_m", 50.0)), Layers.WORLD | Layers.HITBOXES)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var space := get_world_3d().direct_space_state
	var ray := space.intersect_ray(query)
	if ray.is_empty():
		return result
	result["hit"] = true
	result["position"] = ray["position"]
	var collider: Object = ray["collider"]
	if collider is Area3D:
		var headshot: bool = bool(collider.get_meta("headshot", false)) or collider.get_meta("hit_kind", "") == "head"
		var damage := float(gun["damage"]) * (float(gun["headshot_mult"]) if headshot else 1.0)
		result["headshot"] = headshot
		result["damage"] = damage
		var bot: Object = collider.get_meta("bot") if collider.has_meta("bot") else null
		if bot and bot.has_method("take_hit"):  # Bot hitboxes: Bot applies the headshot multiplier itself
			bot.take_hit("head" if headshot else "body", float(gun["damage"]), gun_id(), float(gun["headshot_mult"]))
			return result
		var target: Node = collider
		while target and not target.has_method("apply_damage"):
			target = target.get_parent()
		if target:
			target.apply_damage(damage, {"headshot": headshot, "gun_id": gun_id(), "position": ray["position"]})
	return result


# --- Procedural viewmodel, flash and sound --------------------------------------------

func _build_viewmodel() -> void:
	for child in get_children():
		child.queue_free()
	var color := DataRegistry.color(gun.get("color", "")) if DataRegistry.has_method("color") else Color.GRAY
	_add_box(Vector3(0.08, 0.1, 0.3), Vector3(0, 0, 0), color)               # slide
	_add_box(Vector3(0.07, 0.16, 0.09), Vector3(0, -0.12, 0.08), color.darkened(0.3))  # grip
	_flash = _add_box(Vector3(0.1, 0.1, 0.08), Vector3(0, 0, -0.2), Color(1, 0.9, 0.4), true)
	_flash.visible = false
	_sound = AudioStreamPlayer.new()
	_sound.stream = _make_shot_sound()
	add_child(_sound)


func _add_box(size: Vector3, pos: Vector3, color: Color, emissive: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	add_child(node)
	return node


## Short decaying noise burst, pitched by fire rate so guns sound distinct.
func _make_shot_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 0.12)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in count:
		var env := pow(1.0 - float(i) / count, 3.0)
		var s := (rng.randf() * 2.0 - 1.0) * env * 0.6
		bytes.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav
