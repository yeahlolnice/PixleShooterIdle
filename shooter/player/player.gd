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
##   set_bhop({"autostrafe": 0.5, "max_hop_speed_mult": 1.5, "uncapped": false})
##   clear_bhop()                            # plain jumping again
## With it, holding jump hops on every landing tick. While `autostrafe` > 0 the
## cheat also strafes for you in the air: it pushes at right angles to the
## velocity (the best angle for gain), turning toward the move direction, and
## keeps that fraction of the gain. Auto-strafe speed stops at effective
## move_speed * max_hop_speed_mult unless uncapped; it never slows the player.

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
## False while a menu is open: look and movement input are ignored.
var input_enabled := true

var _pitch := 0.0
## Ids of menus currently open (menu_toggled is per menu; input stays off while any is open).
var _open_menus: Dictionary = {}
var _respawn_timer := 0.0
var _spawn_index := 0
## A jump press waiting for the next physics tick.
var _jump_queued := false
## Auto-strafe side, +1 left / -1 right; flips each tick to hold a straight line.
var _strafe_side := 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	if tuning.is_empty():
		tuning = DataRegistry.player().duplicate()
	health = effective(&"max_health")
	health_changed.emit(health, health)
	EventBus.menu_toggled.connect(_on_menu_toggled)
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


# --- Input ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# _input, not _unhandled_input: a focused UI button must not swallow Space.
	if event.is_action_pressed("jump"):
		_jump_queued = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative)
	elif event is InputEventMouseButton and event.pressed and _open_menus.is_empty() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Applies a mouse delta (pixels) to yaw and clamped pitch.
func look(relative: Vector2) -> void:
	if is_dead or not input_enabled:
		return
	var sens: float = tuning.get("mouse_sensitivity", 0.12)
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


func get_pitch() -> float:
	return _pitch


# --- Movement -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var jump_queued := _jump_queued
	_jump_queued = false
	if is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
		return
	var wish := Vector3.ZERO
	var jump_pressed := false
	if input_enabled:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = global_transform.basis * Vector3(input.x, 0.0, input.y)
		# A press counts for this tick only; holding jump re-jumps only with Auto Bhop.
		jump_pressed = jump_queued or (has_bhop() and Input.is_action_pressed("jump"))
	step_movement(delta, wish, jump_pressed)
	if global_position.y < float(tuning.get("fall_kill_y", -20.0)):
		take_damage(health, null)


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
	var autostrafe := float(bhop.get("autostrafe", 0.0))
	var speed := horizontal.length()
	if autostrafe > 0.0 and speed > 0.0:
		var heading := horizontal / speed
		var steer := wish.normalized() if wish.length_squared() > 0.0001 else heading
		if heading.dot(steer) >= 0.0:  # pressing back still brakes normally
			return _autostrafe(horizontal, heading, steer, autostrafe, delta)
	if wish.length_squared() <= 0.0001:
		return horizontal
	return air_accelerate(horizontal, wish.normalized(), effective(&"move_speed") * minf(wish.length(), 1.0), delta)


## Source PM_AirAccelerate: adds speed along `dir` only while the velocity's
## component along `dir` is below air_speed_cap. Pressing toward where you are
## already going adds nothing; pressing at right angles always adds a little.
func air_accelerate(horizontal: Vector3, dir: Vector3, wish_speed: float, delta: float) -> Vector3:
	var add := minf(wish_speed, float(tuning.get("air_speed_cap", 0.7))) - horizontal.dot(dir)
	if add <= 0.0:
		return horizontal
	return horizontal + dir * minf(effective(&"air_accel") * wish_speed * delta, add)


## Auto Bhop's strafe: a right-angle push on the side that turns toward `steer`;
## once on course it alternates sides so the path stays straight.
func _autostrafe(horizontal: Vector3, heading: Vector3, steer: Vector3, strength: float, delta: float) -> Vector3:
	var speed := horizontal.length()
	var left := Vector3.UP.cross(heading)
	var side := left.dot(steer)
	if absf(side) < float(tuning.get("air_speed_cap", 0.7)) / speed:
		_strafe_side = -_strafe_side
	else:
		_strafe_side = signf(side)
	var pushed := air_accelerate(horizontal, left * _strafe_side, effective(&"move_speed"), delta)
	var new_speed := minf(lerpf(speed, pushed.length(), strength), maxf(hop_speed_cap(), speed))
	return pushed.normalized() * new_speed


# --- Health ---------------------------------------------------------------------

func take_damage(amount: float, source: Node) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, effective(&"max_health"))
	EventBus.player_damaged.emit(amount, health, source)
	if health <= 0.0:
		die(source)


func die(killer: Node = null) -> void:
	if is_dead:
		return
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
