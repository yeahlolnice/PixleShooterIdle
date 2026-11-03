class_name Player
extends CharacterBody3D
## First-person player: mouse look, WASD with acceleration/friction, jump,
## gravity, health, death and respawn. All tuning comes from data/player.json.
##
## Stat modifier API (the ONLY way cheats/perks may change player stats):
##   set_stat_mod(&"move_speed_mult", 1.5)   # replaces the multiplier
##   get_stat_mod(&"move_speed_mult")        # 1.0 when unset
##   clear_stat_mod(&"move_speed_mult")      # back to base
##   reset_stat_mods()                       # remove all
##   effective(&"move_speed")                # base value * "<stat>_mult"
## Modifiers are multipliers stored in `stat_mods` keyed "<stat>_mult". Stats:
## move_speed, ground_accel, air_accel, jump_velocity, max_health. Setting a
## mod never touches the raw tuning, so clearing it restores base stats exactly.
##
## Air movement is Counter-Strike/Source air acceleration: in the air only the
## speed along the wish direction is capped (player.json air_speed_cap), so
## strafing sideways while turning the mouse the same way adds speed with no limit.
## Jumping on the landing tick skips ground friction, so the speed carries over.
## A jump press counts for the next physics tick only (mouse wheel is bound too),
## so hopping by hand takes CS-style timing.
##
## Auto Bhop hook (only the auto_bhop cheat calls these):
##   set_bhop({"max_hop_speed_mult": 6.5, "uncapped": false})
##   clear_bhop()                            # plain jumping again
## With it, holding jump hops perfectly on every landing tick; strafing is still
## up to the player. While it is on, speed gained by air strafing stops at
## effective move_speed * max_hop_speed_mult unless uncapped (it never slows the
## player). Without the cheat, hand bhopping is uncapped, as in CS.
##
## God Mode hook (only the god_mode cheat calls this):
##   set_god_mode(seconds_per_kill, permanent)   # (0, false) = off
## Every bot kill makes the player invulnerable for seconds_per_kill (it does
## not stack; the longer of what is left and the new grant wins); permanent
## ignores all damage. Falling out of the map still kills.
##
## Noclip hook (only the noclip cheat calls these):
##   set_noclip({"burst_s": 5.0, "max_wall_thickness_m": 1.0, "unlimited": false})
##   clear_noclip()
## With it, the noclip action (V) toggles flight: no gravity or world collision,
## fly where you look, hold jump to rise. Each round gives burst_s seconds of
## flight (refilled at freeze time) unless unlimited. One pass through solid
## geometry may go at most max_wall_thickness_m deep; deeper is blocked. Flight
## never ends inside geometry: it lasts until you are out.

signal health_changed(health: float, max_health: float)

## Base tuning (copy of player.json). Tests may replace it before _ready.
var tuning: Dictionary = {}
## Multiplier modifiers, see header. Read-only for everything but the API above.
var stat_mods: Dictionary = {}
## Auto Bhop settings, see header. Empty = off.
var bhop: Dictionary = {}
var health := 0.0
var is_dead := false
## World positions to respawn at; Main assigns the arena's player spawns.
var spawn_points: Array[Vector3] = []
## Mouse-look multiplier; WeaponManager lowers it while scoped (zoom ratio).
var look_scale := 1.0
## False while a menu is open: look and movement input are ignored.
var input_enabled := true

var _pitch := 0.0
## Ids of menus currently open (menu_toggled is per menu; input stays off while any is open).
var _open_menus: Dictionary = {}
var _respawn_timer := 0.0
var _spawn_index := 0
## A jump press waiting for the next physics tick.
var _jump_queued := false
## God Mode: seconds of invulnerability left, and the cheat's settings.
var invuln_left := 0.0
var _god_per_kill := 0.0
var _god_permanent := false
## Noclip settings, see header. Empty = off.
var noclip: Dictionary = {}
var noclipping := false
## Seconds of flight left this round (ignored when unlimited).
var noclip_fuel := 0.0
var _noclip_toggle_queued := false
var _noclip_in_wall := false
var _noclip_entry := Vector3.ZERO   ## last free position before entering geometry
var _saved_collision_mask := 0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	if tuning.is_empty():
		tuning = DataRegistry.player().duplicate()
	health = effective(&"max_health")
	health_changed.emit(health, health)
	EventBus.menu_toggled.connect(_on_menu_toggled)
	EventBus.bot_killed.connect(_on_bot_killed)
	EventBus.round_state_changed.connect(_on_round_state_changed)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Stat modifiers -------------------------------------------------------------

func set_stat_mod(mod_name: StringName, value: float) -> void:
	stat_mods[mod_name] = value
	if mod_name == &"max_health_mult":
		_clamp_health()


func get_stat_mod(mod_name: StringName) -> float:
	return stat_mods.get(mod_name, 1.0)


func clear_stat_mod(mod_name: StringName) -> void:
	stat_mods.erase(mod_name)
	if mod_name == &"max_health_mult":
		_clamp_health()


func reset_stat_mods() -> void:
	stat_mods.clear()
	_clamp_health()


## Base tuning value for `stat` times its "<stat>_mult" modifier.
func effective(stat: StringName) -> float:
	return float(tuning.get(stat, 0.0)) * get_stat_mod(StringName(String(stat) + "_mult"))


# --- Auto Bhop ------------------------------------------------------------------

func set_bhop(settings: Dictionary) -> void:
	bhop = settings.duplicate()


func clear_bhop() -> void:
	bhop = {}


func has_bhop() -> bool:
	return not bhop.is_empty()


## Highest speed auto-strafe builds to (INF when uncapped). Speed Hack raises it.
func hop_speed_cap() -> float:
	if bool(bhop.get("uncapped", false)):
		return INF
	return effective(&"move_speed") * float(bhop.get("max_hop_speed_mult", 1.0))


# --- God Mode -------------------------------------------------------------------

func set_god_mode(seconds_per_kill: float, permanent: bool) -> void:
	_god_per_kill = maxf(seconds_per_kill, 0.0)
	_god_permanent = permanent
	if _god_per_kill <= 0.0:
		invuln_left = 0.0


func is_invulnerable() -> bool:
	return _god_permanent or invuln_left > 0.0


func _on_bot_killed(_bot: Node, _info: Dictionary) -> void:
	if _god_per_kill > 0.0 and not is_dead:
		invuln_left = maxf(invuln_left, _god_per_kill)


# --- Noclip ---------------------------------------------------------------------

func set_noclip(settings: Dictionary) -> void:
	if noclip.is_empty():
		noclip_fuel = float(settings.get("burst_s", 0.0))
	noclip = settings.duplicate()


func clear_noclip() -> void:
	noclip = {}
	_end_noclip()


func has_noclip() -> bool:
	return not noclip.is_empty()


func noclip_unlimited() -> bool:
	return bool(noclip.get("unlimited", false))


## Starts or stops flight. Stopping inside geometry is refused. Returns
## whether the player is flying afterwards.
func toggle_noclip() -> bool:
	if noclipping:
		if not _noclip_in_wall:
			_end_noclip()
	elif has_noclip() and not is_dead and (noclip_unlimited() or noclip_fuel > 0.0):
		noclipping = true
		_noclip_in_wall = false
		_saved_collision_mask = collision_mask
		collision_mask = 0
		velocity = Vector3.ZERO
	return noclipping


func _end_noclip() -> void:
	if not noclipping:
		return
	noclipping = false
	_noclip_in_wall = false
	collision_mask = _saved_collision_mask
	velocity = Vector3.ZERO


## One flight tick along `dir` (world space, length <= 1) at move speed. A step
## into geometry is allowed while it stays within max_wall_thickness_m (plus the
## body's own size along `dir`) of where the player went in; deeper is blocked.
## Burns fuel unless unlimited, and lands once the fuel is gone and the body is clear.
func step_noclip(delta: float, dir: Vector3) -> void:
	if not noclip_unlimited():
		noclip_fuel = maxf(0.0, noclip_fuel - delta)
	var step := dir.limit_length(1.0) * effective(&"move_speed") * delta
	var target := global_position + step
	if step.length_squared() > 0.0:
		if _overlaps_world(target):
			if not _noclip_in_wall:
				_noclip_in_wall = true
				_noclip_entry = global_position
			var reach := float(noclip.get("max_wall_thickness_m", 0.0)) + _body_extent(target - _noclip_entry)
			if target.distance_to(_noclip_entry) <= reach:
				global_position = target
		else:
			_noclip_in_wall = false
			global_position = target
	velocity = step / delta if delta > 0.0 else Vector3.ZERO
	if not noclip_unlimited() and noclip_fuel <= 0.0 and not _noclip_in_wall:
		_end_noclip()


## True if the body's collision shape at `pos` overlaps world geometry.
func _overlaps_world(pos: Vector3) -> bool:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not is_inside_tree():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = Transform3D(Basis(), pos) * shape_node.transform
	query.collision_mask = Layers.WORLD
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Length of the body along `dir` (capsule: 2r sideways, full height vertically).
func _body_extent(dir: Vector3) -> float:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not (shape_node.shape is CapsuleShape3D) or dir.length_squared() < 0.000001:
		return 0.0
	var capsule := shape_node.shape as CapsuleShape3D
	var up := absf(dir.normalized().y)
	return 2.0 * capsule.radius + (capsule.height - 2.0 * capsule.radius) * up


func _on_round_state_changed(state: StringName, _info: Dictionary) -> void:
	if state == EventBus.ROUND_FREEZE and has_noclip():
		noclip_fuel = float(noclip.get("burst_s", 0.0))


# --- Input ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# _input, not _unhandled_input: a focused UI button must not swallow Space.
	if event.is_action_pressed("jump"):
		_jump_queued = true
	elif event.is_action_pressed("noclip"):
		_noclip_toggle_queued = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative)
	elif event is InputEventMouseButton and event.pressed and _open_menus.is_empty() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Applies a mouse delta (pixels) to yaw and clamped pitch.
func look(relative: Vector2) -> void:
	if is_dead or not input_enabled:
		return
	var sens: float = float(tuning.get("mouse_sensitivity", 0.12)) * look_scale
	rotate_y(-deg_to_rad(relative.x * sens))
	var limit := deg_to_rad(float(tuning.get("pitch_limit_deg", 89)))
	_pitch = clampf(_pitch - deg_to_rad(relative.y * sens), -limit, limit)
	head.rotation.x = _pitch


## Weapon recoil: pushes the real aim up by `pitch_deg` (clamped like mouse look).
## Nothing pulls it back; the player compensates with the mouse.
func add_aim_kick(pitch_deg: float) -> void:
	if is_dead:
		return
	var limit := deg_to_rad(float(tuning.get("pitch_limit_deg", 89)))
	_pitch = clampf(_pitch + deg_to_rad(pitch_deg), -limit, limit)
	head.rotation.x = _pitch


## Turns the view toward world `point` by `fraction` (0..1, 1 = snap). Only aim
## cheats (Aimbot, Spinbot) call this.
func aim_at(point: Vector3, fraction: float) -> void:
	var dir := point - camera.global_position
	if dir.length_squared() < 0.0001 or fraction <= 0.0:
		return
	dir = dir.normalized()
	var limit := deg_to_rad(float(tuning.get("pitch_limit_deg", 89)))
	var t := minf(fraction, 1.0)
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), t)
	_pitch = lerpf(_pitch, clampf(asin(dir.y), -limit, limit), t)
	head.rotation.x = _pitch


func get_pitch() -> float:
	return _pitch


# --- Movement -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var jump_queued := _jump_queued
	var noclip_toggle := _noclip_toggle_queued
	_jump_queued = false
	_noclip_toggle_queued = false
	if is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
		return
	invuln_left = maxf(0.0, invuln_left - delta)
	if noclip_toggle and input_enabled:
		toggle_noclip()
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if noclipping:
		# Fly where the camera looks; hold jump to rise.
		var fly := camera.global_transform.basis * Vector3(input.x, 0.0, input.y)
		if input_enabled and Input.is_action_pressed("jump"):
			fly += Vector3.UP
		step_noclip(delta, fly)
		return
	var wish := global_transform.basis * Vector3(input.x, 0.0, input.y)
	# A press counts for this tick only; holding jump re-jumps only with Auto Bhop.
	var jump_pressed := input_enabled and (jump_queued or (has_bhop() and Input.is_action_pressed("jump")))
	step_movement(delta, wish, jump_pressed)
	if global_position.y < float(tuning.get("fall_kill_y", -20.0)):
		_fall_out()


## One movement tick. `wish` is a world-space direction (length <= 1).
## `jump_pressed` means "jump this tick if on the floor".
## Split out from _physics_process so tests can drive it without input.
func step_movement(delta: float, wish: Vector3, jump_pressed: bool) -> void:
	var on_floor := is_on_floor()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if not on_floor:
		velocity.y -= float(tuning.get("gravity", 16.0)) * delta
	elif jump_pressed:
		# Jumping on the landing tick leaves on_floor false, so ground friction
		# and ground accel are skipped this tick and the speed carries over.
		velocity.y = effective(&"jump_velocity")
		on_floor = false

	if on_floor:
		horizontal = _ground_move(horizontal, wish, delta)
	else:
		horizontal = _air_move(horizontal, wish, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()


func _ground_move(horizontal: Vector3, wish: Vector3, delta: float) -> Vector3:
	if wish.length_squared() > 0.0001:
		var target := wish.normalized() * effective(&"move_speed") * minf(wish.length(), 1.0)
		return horizontal.move_toward(target, effective(&"ground_accel") * delta)
	return horizontal.move_toward(Vector3.ZERO, float(tuning.get("ground_friction", 40.0)) * delta)


func _air_move(horizontal: Vector3, wish: Vector3, delta: float) -> Vector3:
	if wish.length_squared() <= 0.0001:
		return horizontal
	var speed := horizontal.length()
	var out := air_accelerate(horizontal, wish.normalized(), effective(&"move_speed") * minf(wish.length(), 1.0), delta)
	if has_bhop():
		# Auto Bhop cap: strafing cannot build past it, but never slows the player.
		var limit := maxf(hop_speed_cap(), speed)
		if out.length() > limit:
			out = out.normalized() * limit
	return out


## Source PM_AirAccelerate: adds speed along `dir` only while the velocity's
## component along `dir` is below air_speed_cap. Pressing toward where you are
## already going adds nothing; pressing at right angles always adds a little.
func air_accelerate(horizontal: Vector3, dir: Vector3, wish_speed: float, delta: float) -> Vector3:
	var add := minf(wish_speed, float(tuning.get("air_speed_cap", 0.7))) - horizontal.dot(dir)
	if add <= 0.0:
		return horizontal
	return horizontal + dir * minf(effective(&"air_accel") * wish_speed * delta, add)


# --- Health ---------------------------------------------------------------------

func take_damage(amount: float, source: Node) -> void:
	if is_dead or amount <= 0.0 or is_invulnerable():
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, effective(&"max_health"))
	EventBus.player_damaged.emit(amount, health, source)
	if health <= 0.0:
		die(source)


## Fell below fall_kill_y: dies even through God Mode, so nobody falls forever.
func _fall_out() -> void:
	var amount := health
	health = 0.0
	health_changed.emit(health, effective(&"max_health"))
	EventBus.player_damaged.emit(amount, health, null)
	die(null)


func die(killer: Node = null) -> void:
	if is_dead:
		return
	_end_noclip()
	is_dead = true
	velocity = Vector3.ZERO
	_respawn_timer = float(tuning.get("respawn_delay_s", 3.0))
	EventBus.player_died.emit({"position": global_position, "killer": killer})


func respawn() -> void:
	is_dead = false
	velocity = Vector3.ZERO
	health = effective(&"max_health")
	health_changed.emit(health, health)
	if not spawn_points.is_empty():
		global_position = spawn_points[_spawn_index % spawn_points.size()]
		_spawn_index += 1
	EventBus.player_spawned.emit(self)


func _clamp_health() -> void:
	var max_hp := effective(&"max_health")
	health = minf(health, max_hp)
	health_changed.emit(health, max_hp)


func _on_menu_toggled(menu_id: StringName, open: bool) -> void:
	if open:
		_open_menus[menu_id] = true
	else:
		_open_menus.erase(menu_id)
	var any_open := is_menu_open()
	input_enabled = not any_open
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if any_open else Input.MOUSE_MODE_CAPTURED


## True while at least one menu (buy menu, mod menu, ...) is open.
func is_menu_open() -> bool:
	return not _open_menus.is_empty()
