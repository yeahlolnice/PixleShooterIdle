class_name Weapon
extends Node3D
## One hitscan gun driven by an entry of data/guns.json.
##
## The magazine/reload/cooldown state machine is plain code advanced by tick(),
## so tests run it without a scene tree. Cheats change the gun only through
## `modifiers` (mag_mult, recoil_mult, spread_mult, infinite_reload,
## force_headshot = every bot hit counts as a headshot, set by Aimbot at max).
##
## Weapon v2 (TASK-022), optional guns.json fields:
##   pellets         rays per shot (shotgun); damage is per pellet, recoil and ammo per shot
##   bloom_deg / bloom_max_deg / bloom_recovery_deg_s
##                   spread added per shot up to a max, recovering while not firing
##   zoom_fov / scoped_spread_mult
##                   WeaponManager zooms the camera to zoom_fov while aiming (RMB);
##                   spread is multiplied while scoped (sniper: inaccurate unscoped)
##   category / model_length_m   viewmodel shape (pistol, smg, shotgun, rifle, sniper, lmg)
##
## Hitbox contract (bots, TASK-003): hitboxes are Area3D on Layers.HITBOXES.
## A head hitbox has meta "headshot" = true. The raycast walks up from the hit
## Area3D to the first node with `apply_damage(amount: float, info: Dictionary)`.

signal shot_fired(hit: Dictionary)
signal reload_started
signal reload_finished
## One shot's aim kick in degrees, positive = up. The owner (WeaponManager -> Player)
## adds it to the real aim, so it stays until the player pulls the mouse back down.
signal recoil_kicked(pitch_deg: float)

enum State { READY, RELOADING }

const MUZZLE_FLASH_S := 0.05
## Viewmodel kick per shot (metres back) and how fast it returns. Feel, not balance.
const KICK_M := 0.06
const KICK_RECOVERY_M_S := 0.6

var gun: Dictionary = {}
var state: State = State.READY
var ammo: int = 0
var modifiers := {"mag_mult": 1.0, "recoil_mult": 1.0, "spread_mult": 1.0, "infinite_reload": false, "force_headshot": false}
## Gun upgrade multipliers (ShopService, TASK-024); WeaponManager sets them.
var damage_mult := 1.0
var fire_rate_mult := 1.0
## Extra spread from sustained fire (degrees), see bloom_* fields.
var bloom := 0.0
## True while aiming down the scope (set by WeaponManager).
var scoped := false

var _kick := 0.0
## Seconds since the last shot; bloom only recovers once you stop firing.
var _since_shot := INF
var _rest_position := Vector3.ZERO
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _flash_left: float = 0.0
var _rng := RandomNumberGenerator.new()
var _flash: MeshInstance3D
var _sound: AudioStreamPlayer
var _reload_sound: AudioStreamPlayer


func setup(gun_def: Dictionary) -> void:
	gun = gun_def
	state = State.READY
	_cooldown = 0.0
	_reload_left = 0.0
	bloom = 0.0
	scoped = false
	_kick = 0.0
	_rest_position = position
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
	var s := (float(gun.get("spread_deg", 0.0)) + bloom) * float(modifiers["spread_mult"])
	return s * float(gun.get("scoped_spread_mult", 1.0)) if scoped else s


func pellet_count() -> int:
	return int(gun.get("pellets", 1))


## Camera FOV while scoped; 0 = this gun has no scope.
func zoom_fov() -> float:
	return float(gun.get("zoom_fov", 0.0))


func category() -> String:
	return String(gun.get("category", "pistol"))


func reload_time() -> float:
	if modifiers["infinite_reload"]:
		return 0.0
	return float(gun.get("reload_time_s", 0.0))


func fire_interval() -> float:
	return 1.0 / (float(gun.get("fire_rate", 1.0)) * fire_rate_mult)


## Damage per hit (per pellet) after gun upgrades.
func damage() -> float:
	return float(gun.get("damage", 0.0)) * damage_mult


func is_auto() -> bool:
	return bool(gun.get("auto", false))


func is_reloading() -> bool:
	return state == State.RELOADING


func set_modifier(key: String, value: Variant) -> void:
	modifiers[key] = value
	if key == "mag_mult":
		ammo = mini(ammo, mag_size())
		EventBus.ammo_changed.emit(ammo, mag_size())
	elif key == "infinite_reload" and value and state == State.RELOADING:
		_finish_reload()


func reset_modifiers() -> void:
	for key in ["mag_mult", "recoil_mult", "spread_mult"]:
		modifiers[key] = 1.0
	modifiers["infinite_reload"] = false
	modifiers["force_headshot"] = false
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
	# Hitscan first: the shot goes where you aimed, the kick moves the next one.
	var hit := _fire_pellets()
	bloom = minf(bloom + float(gun.get("bloom_deg", 0.0)), float(gun.get("bloom_max_deg", 0.0)))
	_since_shot = 0.0
	_kick = KICK_M
	if recoil_deg() > 0.0:
		recoil_kicked.emit(recoil_deg())
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
	if _reload_sound and _reload_sound.is_inside_tree():
		_reload_sound.play()
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
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and _flash:
			_flash.visible = false
	_since_shot += delta
	if bloom > 0.0 and _since_shot > fire_interval() * 1.5:   # trigger released
		bloom = maxf(0.0, bloom - float(gun.get("bloom_recovery_deg_s", 0.0)) * delta)
	if _kick > 0.0:
		_kick = maxf(0.0, _kick - KICK_RECOVERY_M_S * delta)
		position = _rest_position + Vector3(0, 0, _kick)


func _physics_process(delta: float) -> void:
	tick(delta)


## Casts pellet_count() rays and merges them into one hit summary:
## {hit, headshot, damage (sum), position (first hit), pellets, pellets_hit, bots_hit, kills}.
func _fire_pellets() -> Dictionary:
	var n := pellet_count()
	var out := {"hit": false, "headshot": false, "damage": 0.0, "position": Vector3.ZERO, "pellets": n, "pellets_hit": 0, "bots_hit": 0, "kills": 0}
	if not is_inside_tree():
		return out
	for i in n:
		var h := _hitscan()
		if not h.get("hit", false):
			continue
		if not out["hit"]:
			out["position"] = h["position"]
		out["hit"] = true
		out["pellets_hit"] += 1
		out["headshot"] = out["headshot"] or h["headshot"]
		out["damage"] += h["damage"]
		out["bots_hit"] += h["bots_hit"]
		out["kills"] += h["kills"]
	return out


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


## How many extra bots one ray may pass through (guns.json "pierce", else economy.json
## collateral.pierce). Walls always stop it.
func pierce() -> int:
	return int(gun.get("pierce", DataRegistry.economy().get("collateral", {}).get("pierce", 0)))


## Casts the shot ray from the camera. It passes through up to pierce() bots
## (collateral), each later bot taking collateral.damage_falloff less, and stops at
## the world. Returns {hit, headshot, damage (sum), position (first hit), bots_hit, kills}.
## Two or more kills from one ray emit EventBus.collateral_kill.
func _hitscan() -> Dictionary:
	var result := {"hit": false, "headshot": false, "damage": 0.0, "position": Vector3.ZERO, "bots_hit": 0, "kills": 0}
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
	var falloff := float(DataRegistry.economy().get("collateral", {}).get("damage_falloff", 1.0))
	var dmg_scale := 1.0
	var exclude: Array[RID] = []
	var kill_pos := Vector3.ZERO
	for i in pierce() + 1:
		query.exclude = exclude
		var ray := space.intersect_ray(query)
		if ray.is_empty():
			break
		if not result["hit"]:
			result["position"] = ray["position"]
		result["hit"] = true
		var collider: Object = ray["collider"]
		if not (collider is Area3D):
			break   # world geometry stops the bullet
		var headshot: bool = bool(collider.get_meta("headshot", false)) or collider.get_meta("hit_kind", "") == "head" or bool(modifiers.get("force_headshot", false))
		var base := damage() * dmg_scale
		var dealt := base * (float(gun["headshot_mult"]) if headshot else 1.0)
		result["headshot"] = result["headshot"] or headshot
		result["damage"] += dealt
		var bot: Object = collider.get_meta("bot") if collider.has_meta("bot") else null
		if bot and bot.has_method("take_hit"):  # Bot hitboxes: Bot applies the headshot multiplier itself
			var was_alive: bool = not bot.is_dead()
			bot.take_hit("head" if headshot else "body", base, gun_id(), float(gun["headshot_mult"]))
			result["bots_hit"] += 1
			if was_alive and bot.is_dead():
				result["kills"] += 1
				kill_pos = (bot as Node3D).global_position
			for area in (bot as Node).find_children("*", "Area3D", true, false):
				exclude.append((area as Area3D).get_rid())
			dmg_scale *= falloff
			continue
		var target: Node = collider
		while target and not target.has_method("apply_damage"):
			target = target.get_parent()
		if target:
			target.apply_damage(dealt, {"headshot": headshot, "gun_id": gun_id(), "position": ray["position"]})
		break
	if result["kills"] >= 2:
		EventBus.collateral_kill.emit(int(result["kills"]), kill_pos)
	return result

# --- Procedural viewmodel, flash and sound --------------------------------------------

func _build_viewmodel() -> void:
	for child in get_children():
		child.queue_free()
	var color := DataRegistry.color(gun.get("color", "")) if DataRegistry.has_method("color") else Color.GRAY
	var dark := color.darkened(0.35)
	var length := float(gun.get("model_length_m", 0.3))
	var cat := category()
	var thick := 0.13 if cat in ["shotgun", "lmg"] else 0.1
	# Body runs from just behind the grip forward along -Z.
	_add_box(Vector3(0.08, thick, length), Vector3(0, 0, 0.15 - length * 0.5), color)
	_add_box(Vector3(0.07, 0.16, 0.09), Vector3(0, -0.12, 0.08), dark)                    # grip
	if cat in ["smg", "rifle", "sniper", "lmg"]:
		_add_box(Vector3(0.06, 0.12, 0.18), Vector3(0, -0.02, 0.24), dark)                # stock
	if cat in ["smg", "rifle"]:
		_add_box(Vector3(0.05, 0.16, 0.06), Vector3(0, -0.13, -0.08), dark)               # magazine
	if cat == "lmg":
		_add_box(Vector3(0.14, 0.14, 0.14), Vector3(0, -0.13, -0.05), dark)               # box mag
	if cat == "shotgun":
		_add_box(Vector3(0.09, 0.07, 0.16), Vector3(0, -0.08, 0.15 - length * 0.7), dark) # pump
	if zoom_fov() > 0.0:
		_add_box(Vector3(0.05, 0.06, 0.22), Vector3(0, thick * 0.5 + 0.04, 0.0), dark)    # scope
	_flash = _add_box(Vector3(0.1, 0.1, 0.08), Vector3(0, 0, 0.15 - length - 0.04), Color(1, 0.9, 0.4), true)
	_flash.visible = false
	SfxPlayer.ensure_bus()
	_sound = AudioStreamPlayer.new()
	_sound.stream = SfxSynth.shot(category())   # TASK-028: one sound per gun class
	_sound.bus = SfxPlayer.BUS
	_sound.max_polyphony = 4   # auto fire overlaps instead of cutting off
	add_child(_sound)
	_reload_sound = AudioStreamPlayer.new()
	_reload_sound.stream = SfxSynth.get_sound("reload")
	_reload_sound.bus = SfxPlayer.BUS
	add_child(_reload_sound)


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

