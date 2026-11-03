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

signal health_changed(health: float, max_health: float)

## Base tuning (copy of player.json). Tests may replace it before _ready.
var tuning: Dictionary = {}
## Multiplier modifiers, see header. Read-only for everything but the API above.
var stat_mods: Dictionary = {}
var health := 0.0
var is_dead := false
## World positions to respawn at; Main assigns the arena's player spawns.
var spawn_points: Array[Vector3] = []
## False while a menu is open: look and movement input are ignored.
var input_enabled := true

var _pitch := 0.0
var _menu_open := false
var _respawn_timer := 0.0
var _spawn_index := 0

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


# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative)
	elif event is InputEventMouseButton and event.pressed and not _menu_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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


func get_pitch() -> float:
	return _pitch


# --- Movement -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
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
		jump_pressed = Input.is_action_pressed("jump")
	step_movement(delta, wish, jump_pressed)
	if global_position.y < float(tuning.get("fall_kill_y", -20.0)):
		take_damage(health, null)


## One movement tick. `wish` is a world-space direction (length <= 1).
## Split out from _physics_process so tests can drive it without input.
func step_movement(delta: float, wish: Vector3, jump_pressed: bool) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= float(tuning.get("gravity", 16.0)) * delta
	elif jump_pressed:
		velocity.y = effective(&"jump_velocity")
		on_floor = false

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var accel := effective(&"ground_accel" if on_floor else &"air_accel")
	if wish.length_squared() > 0.0001:
		var target := wish.normalized() * effective(&"move_speed") * minf(wish.length(), 1.0)
		horizontal = horizontal.move_toward(target, accel * delta)
	elif on_floor:
		horizontal = horizontal.move_toward(Vector3.ZERO, float(tuning.get("ground_friction", 40.0)) * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()


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


func _on_menu_toggled(_menu_id: StringName, open: bool) -> void:
	_menu_open = open
	input_enabled = not open
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
