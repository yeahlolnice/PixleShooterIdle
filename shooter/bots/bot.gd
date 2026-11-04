class_name Bot
extends CharacterBody3D
## Bot: wander -> chase on sight -> shoot, built from procedural boxes.
## Stats come from bots.json x the arena's bot_mults (DataRegistry.bot_stats).
## bots.json "behaviour" picks how it moves while shooting (TASK-025):
##   grunt  - stops and shoots inside shoot_range_ratio of its sight
##   sniper - shoots from its whole sight range, stays near its perch
##            (wander_radius_m) and backs off when closer than keep_distance_m
##   rusher - closes in fast, then strafes side to side (strafe_speed,
##            strafe_switch_s, flips early when it hits a wall)
## Hitboxes are Area3Ds on Layers.HITBOXES with meta "bot" and "hit_kind" ("head"/"body");
## weapons call take_hit() on the bot found through that meta.

enum State { WANDER, CHASE, SHOOT, DEAD }

const WANDER_RADIUS := 8.0       ## metres around the spawn point
const WANDER_PAUSE_S := 1.5
const SHOOT_RANGE_RATIO := 0.7   ## stops to shoot inside this fraction of sight_range_m
const GRAVITY := 20.0
const EYE_HEIGHT := 1.7
const TARGET_AIM_HEIGHT := 1.1   ## where bots aim on the player (chest)
const TRACER_LIFETIME_S := 0.12
const POP_PARTICLES := 8
const POP_TIME_S := 0.35
## Pop tweens shrink to this, not zero: a zero scale makes a singular basis ("det == 0" errors).
const POP_END_SCALE := Vector3.ONE * 0.001
const HEAD_SIZE := Vector3(0.5, 0.5, 0.5)
const DEFAULT_BODY_SIZE := Vector3(0.7, 1.2, 0.4)
const FACE_COLOR := "ui_bg"
const CONFETTI := 10   ## death burst: confetti cubes on top of POP_PARTICLES coins

## Head hitbox size multiplier for every bot; only the Hitbox Expander cheat sets
## it. Static so bots spawned later pick it up too. The head mesh never changes.
static var head_hitbox_scale := 1.0

var bot_id := "grunt"
var arena_id := ""
var stats := {}
var health := 0.0
var state: State = State.WANDER
var target: Node3D = null    ## anything in 3D space; take_damage(amount, source) is optional

var _home := Vector3.ZERO
var _agent: NavigationAgent3D
var _reaction_left := 0.0
var _fire_cooldown := 0.0
var _wander_pause := 0.0
var _rng := RandomNumberGenerator.new()
var _strafe_side := 1.0
## Came in through an entrance (BotSpawner): advances on the target instead of wandering.
var marching := false
var _strafe_left := 0.0
var _built := false
var _head_shape: BoxShape3D


## Resolves the stat block for a bot type in an arena (bots.json x arena multipliers).
static func resolve_stats(p_bot_id: String, p_arena_id: String) -> Dictionary:
	return DataRegistry.bot_stats(p_bot_id, p_arena_id)


## Damage a hit deals: head hits use the gun's headshot multiplier, body hits are 1x.
static func damage_for(base_damage: float, head: bool, headshot_mult: float) -> float:
	return base_damage * headshot_mult if head else base_damage


## Chance that one shot lands on a target of `target_radius` at `distance`, with the aim
## direction uniform inside a cone of half-angle `aim_error_deg`.
static func hit_probability(aim_error_deg: float, distance: float, target_radius: float) -> float:
	var spread := distance * tan(deg_to_rad(aim_error_deg))
	if spread <= target_radius:
		return 1.0
	return (target_radius * target_radius) / (spread * spread)


## Call before add_child (or right after; visuals are built on _ready / first use).
func configure(p_bot_id: String, p_arena_id: String, p_target: Node3D = null) -> void:
	bot_id = p_bot_id
	arena_id = p_arena_id
	target = p_target
	stats = resolve_stats(p_bot_id, p_arena_id)
	health = stats["health"]


func _ready() -> void:
	_rng.randomize()
	collision_layer = Layers.BOTS
	collision_mask = Layers.WORLD
	if stats.is_empty():
		configure(bot_id, arena_id if arena_id != "" else DataRegistry.first_arena_id(), target)
	_home = global_position
	_build_body()
	_agent = get_node_or_null("NavigationAgent3D")
	if _agent == null:
		_agent = NavigationAgent3D.new()
		_agent.name = "NavigationAgent3D"
		add_child(_agent)
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	_wander_pause = _rng.randf_range(0.0, WANDER_PAUSE_S)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	var sees := _can_see_target()
	match state:
		State.WANDER:
			if sees:
				_reaction_left = stats["reaction_time_s"]
				state = State.CHASE
			elif marching and target and is_instance_valid(target):
				_move_toward(target.global_position, delta)   # entrance bots press in
			else:
				_wander(delta)
		State.CHASE:
			if not sees:
				state = State.WANDER
			elif _reaction_left > 0.0:
				_reaction_left -= delta
				_face(target.global_position)
				_stop(delta)
			elif _distance_to_target() <= shoot_range():
				state = State.SHOOT
			else:
				_move_toward(target.global_position, delta)
		State.SHOOT:
			if not sees:
				state = State.CHASE
				_reaction_left = stats["reaction_time_s"]
			elif _distance_to_target() > shoot_range() * 1.2:
				state = State.CHASE
			else:
				_combat_move(delta)
				_face(target.global_position)
				if _fire_cooldown <= 0.0:
					_fire()
					_fire_cooldown = 1.0 / stats["fire_rate"]


# --- Damage --------------------------------------------------------------------

## Applies a hit. `hit_kind` is "head" or "body". Returns the damage dealt.
func take_hit(hit_kind: String, base_damage: float, gun_id: String = "", headshot_mult: float = 2.0) -> float:
	if state == State.DEAD:
		return 0.0
	var head := hit_kind == "head"
	var dealt := damage_for(base_damage, head, headshot_mult)
	health = maxf(0.0, health - dealt)
	if health <= 0.0:
		_die(head, gun_id)
	else:
		EventBus.bot_damaged.emit(self, {
			"amount": dealt, "headshot": head, "gun_id": gun_id,
			"position": global_position, "health_left": health,
		})
	return dealt


func is_dead() -> bool:
	return state == State.DEAD


func _die(headshot: bool, gun_id: String) -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	for area in find_children("*", "Area3D", true, false):
		(area as Area3D).set_deferred("monitorable", false)
		(area as Area3D).collision_layer = 0
	collision_layer = 0
	EventBus.bot_killed.emit(self, {
		"headshot": headshot, "gun_id": gun_id,
		"position": global_position, "bot_type": bot_id,
	})
	_pop()


func _pop() -> void:
	var parent := get_parent()
	if parent and is_inside_tree():
		# Coin + confetti burst (TASK-029): gold coins, then random-hue confetti.
		var coin_mat := _material("cash")
		for i in POP_PARTICLES + CONFETTI:
			var coin := i < POP_PARTICLES
			var cube := MeshInstance3D.new()
			cube.set_meta("pop", "coin" if coin else "confetti")   # names get deduped by the engine
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.2, 0.2, 0.05) if coin else Vector3.ONE * 0.08
			cube.mesh = mesh
			if coin:
				cube.material_override = coin_mat
			else:
				var confetti := StandardMaterial3D.new()
				confetti.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				confetti.albedo_color = Color.from_hsv(_rng.randf(), 0.75, 1.0)
				cube.material_override = confetti
			parent.add_child(cube)
			cube.global_position = global_position + Vector3(0, 1.0, 0)
			var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 1.5), _rng.randf_range(-1, 1)) * (1.0 if coin else 1.6)
			cube.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0)
			var tw := cube.create_tween().set_parallel(true)
			tw.tween_property(cube, "global_position", cube.global_position + dir * 1.2, POP_TIME_S)
			tw.tween_property(cube, "scale", POP_END_SCALE, POP_TIME_S)
			tw.chain().tween_callback(cube.queue_free)
	var tween := create_tween()
	tween.tween_property(self, "scale", POP_END_SCALE, POP_TIME_S)
	tween.tween_callback(queue_free)


# --- Perception / movement -------------------------------------------------------

func behaviour() -> String:
	return String(stats.get("behaviour", "grunt"))


## Distance inside which the bot stops chasing and shoots.
func shoot_range() -> float:
	return float(stats["sight_range_m"]) * float(stats.get("shoot_range_ratio", SHOOT_RANGE_RATIO))


func _distance_to_target() -> float:
	return global_position.distance_to(target.global_position)


func _can_see_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _distance_to_target() > stats["sight_range_m"]:
		return false
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)
	var to := target.global_position + Vector3(0, TARGET_AIM_HEIGHT, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _wander(delta: float) -> void:
	if _wander_pause > 0.0:
		_wander_pause -= delta
		_stop(delta)
		return
	if _agent.is_navigation_finished() or _agent.target_position == Vector3.ZERO:
		_pick_wander_target()
		return
	_move_toward(_agent.target_position, delta)
	if global_position.distance_to(_agent.target_position) < 0.8:
		_wander_pause = WANDER_PAUSE_S
		_agent.target_position = global_position


func _pick_wander_target() -> void:
	var offset := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * float(stats.get("wander_radius_m", WANDER_RADIUS))
	var dest := _home + offset
	var map := _agent.get_navigation_map()
	if NavigationServer3D.map_get_regions(map).size() > 0:
		dest = NavigationServer3D.map_get_closest_point(map, dest)
	_agent.target_position = dest


func _move_toward(dest: Vector3, delta: float) -> void:
	var goal := dest
	var map := _agent.get_navigation_map()
	if NavigationServer3D.map_get_regions(map).size() > 0:
		_agent.target_position = dest
		goal = _agent.get_next_path_position()
	var flat := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	var dir := flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	velocity.x = dir.x * stats["move_speed"]
	velocity.z = dir.z * stats["move_speed"]
	_apply_gravity(delta)
	if dir != Vector3.ZERO:
		_face(global_position + dir)
	move_and_slide()


## How this bot moves while shooting, by bots.json "behaviour".
func _combat_move(delta: float) -> void:
	match behaviour():
		"rusher":
			_strafe(delta)
		"sniper":
			if _distance_to_target() < float(stats.get("keep_distance_m", 0.0)):
				_retreat(delta)
			else:
				_stop(delta)
		_:
			_stop(delta)


## Sideways around the target; flips on a timer (jittered) or when blocked.
func _strafe(delta: float) -> void:
	_strafe_left -= delta
	if _strafe_left <= 0.0 or is_on_wall():
		_strafe_side = -_strafe_side
		_strafe_left = float(stats.get("strafe_switch_s", 0.8)) * _rng.randf_range(0.6, 1.4)
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		_stop(delta)
		return
	var side := to.normalized().cross(Vector3.UP) * _strafe_side
	var speed := float(stats.get("strafe_speed", stats["move_speed"]))
	velocity.x = side.x * speed
	velocity.z = side.z * speed
	_apply_gravity(delta)
	move_and_slide()


## Straight away from the target (navmesh-aware via _move_toward).
func _retreat(delta: float) -> void:
	var away := global_position - target.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD
	_move_toward(global_position + away.normalized() * 3.0, delta)


func _stop(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta


func _face(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.01:
		look_at(flat, Vector3.UP)


# --- Shooting ------------------------------------------------------------------

## Direction from the eye to `aim_point`, deflected by a random angle inside the
## aim-error cone (uniform over the cone's disc).
func aimed_direction(aim_point: Vector3) -> Vector3:
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)
	var dir := (aim_point - from).normalized()
	var max_angle := deg_to_rad(stats["aim_error_deg"])
	var angle := max_angle * sqrt(_rng.randf())
	var around := _rng.randf() * TAU
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var deflected := dir.rotated(side, angle)
	return deflected.rotated(dir, around)


func _fire() -> void:
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)
	var aim_point := target.global_position + Vector3(0, TARGET_AIM_HEIGHT, 0)
	var dir := aimed_direction(aim_point)
	var reach: float = stats["sight_range_m"]
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Layers.WORLD | Layers.PLAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = hit["position"] if not hit.is_empty() else from + dir * reach
	_spawn_tracer(from, end)
	if not hit.is_empty() and hit["collider"] is Node:
		var collider: Node = hit["collider"]
		if collider.is_in_group("player"):
			_damage_player(collider)


func _damage_player(player: Node) -> void:
	var amount: float = stats["damage"]
	if player.has_method("take_damage"):
		player.take_damage(amount, self)
	else:
		EventBus.player_damaged.emit(amount, -1.0, self)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var parent := get_parent()
	if parent == null or to.distance_to(from) < 0.1:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, from.distance_to(to))
	tracer.mesh = mesh
	tracer.material_override = _material("bot_rusher")
	parent.add_child(tracer)
	tracer.global_position = (from + to) * 0.5
	tracer.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	get_tree().create_timer(TRACER_LIFETIME_S).timeout.connect(tracer.queue_free)


# --- Procedural body -------------------------------------------------------------

func _build_body() -> void:
	if _built:
		return
	_built = true
	var body_color: String = stats.get("body_color", "bot_grunt")
	var head_color: String = stats.get("head_color", "bot_skin")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	# Torso + legs share the body hitbox; the cube head has its own. Body size is
	# per type (bots.json body_size), so silhouettes differ and hitboxes match.
	var body_size: Vector3 = stats.get("body_size", DEFAULT_BODY_SIZE)
	_add_part("Body", body_size, Vector3(0, body_size.y * 0.5, 0), body_color, "body")
	var head_y := body_size.y + HEAD_SIZE.y * 0.5
	_head_shape = _add_part("Head", HEAD_SIZE, Vector3(0, head_y, 0), head_color, "head")
	apply_head_hitbox_scale()
	_add_face(head_y)


## Eyes and mouth on the head's front (-Z, the way the bot faces), plus a
## per-behaviour accessory: sniper cap, rusher headband (TASK-029). Visual only.
func _add_face(head_y: float) -> void:
	var front := -HEAD_SIZE.z * 0.5 - 0.01
	var dark := FACE_COLOR
	_add_deco("EyeL", Vector3(0.09, 0.09, 0.02), Vector3(-0.11, head_y + 0.06, front), dark)
	_add_deco("EyeR", Vector3(0.09, 0.09, 0.02), Vector3(0.11, head_y + 0.06, front), dark)
	_add_deco("Mouth", Vector3(0.2, 0.04, 0.02), Vector3(0, head_y - 0.1, front), dark)
	var top := head_y + HEAD_SIZE.y * 0.5
	match behaviour():
		"sniper":
			_add_deco("Cap", Vector3(0.54, 0.09, 0.54), Vector3(0, top + 0.04, 0), String(stats.get("body_color", "bot_sniper")), 0.35)
			_add_deco("CapBrim", Vector3(0.5, 0.03, 0.18), Vector3(0, top + 0.01, -0.33), String(stats.get("body_color", "bot_sniper")), 0.35)
		"rusher":
			_add_deco("Headband", Vector3(0.53, 0.08, 0.53), Vector3(0, head_y + 0.15, 0), "danger")


## A visual-only box (no hitbox). `darken` 0..1 shades the palette colour.
func _add_deco(part_name: String, size: Vector3, pos: Vector3, color_name: String, darken: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := _material(color_name)
	mat.albedo_color = mat.albedo_color.darkened(darken)
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


## Resizes the head hitbox to HEAD_SIZE * head_hitbox_scale (Hitbox Expander).
func apply_head_hitbox_scale() -> void:
	if _head_shape:
		_head_shape.size = HEAD_SIZE * head_hitbox_scale


func head_hitbox_size() -> Vector3:
	return _head_shape.size if _head_shape else Vector3.ZERO


## Builds one visible box and its matching hitbox; returns the hitbox shape.
func _add_part(part_name: String, size: Vector3, pos: Vector3, color_name: String, kind: String) -> BoxShape3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _material(color_name)
	mi.position = pos
	add_child(mi)
	var area := Area3D.new()
	area.name = part_name + "Hitbox"
	area.collision_layer = Layers.HITBOXES
	area.collision_mask = 0
	area.set_meta("bot", self)
	area.set_meta("hit_kind", kind)
	area.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	add_child(area)
	return box


func _material(color_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DataRegistry.color(color_name)
	mat.roughness = 1.0
	return mat
